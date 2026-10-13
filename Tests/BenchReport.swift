import CoreGraphics
import Foundation
import UttCore

/// Everything a dictation produced that an optimization must leave alone. JSON
/// fields are kept as sorted text with the timings and clock stamps taken out —
/// those are the one part of each that is meant to move.
struct BenchOutput: Codable, Equatable {
    var delivered: String?
    var transcript: String?
    var filterInput: String?
    var extensionFile: String?
    var history: String?
    var clipboardRestored: Bool?
    var jobAnswer: String?

    static func stripped(_ data: Data, dropping keys: Set<String>) -> String? {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for key in keys { object[key] = nil }
        guard let clean = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        else { return nil }
        return String(bytes: clean, encoding: .utf8)
    }

    static func stripped(_ value: some Encodable, dropping keys: Set<String>) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { stripped($0, dropping: keys) }
    }
}

/// One distinct output and how many runs produced it. Cleanup runs a language
/// model, so a fixture can have more than one; a change is suspect when it
/// produces one the run before never did.
struct BenchVariant: Codable, Equatable {
    let runs: Int
    let output: BenchOutput

    static func of(_ outputs: [BenchOutput]) -> [BenchVariant] {
        var distinct: [BenchOutput] = []
        for output in outputs where !distinct.contains(output) { distinct.append(output) }
        return distinct
            .map { variant in BenchVariant(runs: outputs.filter { $0 == variant }.count, output: variant) }
            .sorted { $0.runs > $1.runs }
    }
}

struct BenchSummary: Codable {
    let median: Double
    let p90: Double
    let samples: [Double]
}

struct BenchResult: Codable {
    let label: String
    let date: Date
    let runs: Int
    let warmups: Int
    let modelLoadMs: Double
    let fixtureSeconds: [String: Double]
    let safety: [String: String]
    let scenarios: [String: [String: BenchSummary]]
}

extension [Double] {
    /// Linear interpolation between closest ranks, so the median of an even count
    /// is the mean of the middle two.
    func percentile(_ fraction: Double) -> Double {
        let sorted = sorted()
        let rank = fraction * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down)), high = Int(rank.rounded(.up))
        return sorted[low] + (sorted[high] - sorted[low]) * (rank - Double(low))
    }
}

enum BenchReport {
    /// Headlines first, then the stages in the order they happen.
    static let order = [
        "a.text", "b.pasteFinished", "c.handoff", "stop", "transcribe", "decode", "rules", "cleanup",
        "filter", "paste", "restore", "frontmost", "history", "transcriptJson", "liveFinish",
        "total", "pickup", "work", "answer"
    ]
    static let scenarioOrder = ["hotkey-3s", "hotkey-11s", "hotkey-30s", "jobs-11s", "cold"]

    /// What the brief promises about this process, checked rather than assumed: no
    /// event tap of its own, nothing listening (8756 least of all), and every file
    /// under the bench's own root.
    static func safety() -> [String: String] {
        var count: UInt32 = 0
        CGGetEventTapList(0, nil, &count)
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        CGGetEventTapList(count, &taps, &count)
        let own = taps.prefix(Int(count)).filter { $0.tappingProcess == getpid() }.count

        let lsof = Process()
        lsof.executableURL = URL(filePath: "/usr/sbin/lsof")
        lsof.arguments = ["-nP", "-a", "-p", "\(getpid())", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        try? lsof.run()
        let listening = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        lsof.waitUntilExit()
        return [
            "pid": "\(getpid())",
            "eventTapsInThisProcess": "\(own)",
            "listeningSockets": listening.isEmpty ? "none" : listening,
            "applicationSupport": (try? URL.uttApplicationSupport.path) ?? "unresolved"
        ]
    }

    static func write(_ result: BenchResult, outputs: [String: [BenchOutput]], to directory: URL) throws {
        let prior = rotate(directory.appending(path: "latest.json"), to: directory.appending(path: "previous.json"))
        let priorOutputs = rotate(directory.appending(path: "outputs.json"), to: directory.appending(path: "outputs-previous.json"))
        let variants = outputs.mapValues(BenchVariant.of)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)
        try data.write(to: directory.appending(path: "latest.json"))
        let runs = directory.appending(path: "runs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
        try data.write(to: runs.appending(path: "\(ISO8601DateFormatter().string(from: result.date))-\(result.label).json"))
        try encoder.encode(variants).write(to: directory.appending(path: "outputs.json"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = render(
            result,
            against: prior.flatMap { try? decoder.decode(BenchResult.self, from: $0) },
            outputs: outputsLine(variants, prior: priorOutputs.flatMap { try? decoder.decode([String: [BenchVariant]].self, from: $0) })
        )
        try report.write(to: directory.appending(path: "report.txt"), atomically: true, encoding: .utf8)
    }

    static func summarize(_ runs: [[String: Double]]) -> [String: BenchSummary] {
        let stages = Set(runs.flatMap(\.keys))
        return Dictionary(uniqueKeysWithValues: stages.map { stage in
            let values = runs.compactMap { $0[stage] }
            return (stage, BenchSummary(median: values.percentile(0.5), p90: values.percentile(0.9), samples: values))
        })
    }

    /// The last run's file becomes `previous`, and its bytes come back for comparing.
    private static func rotate(_ latest: URL, to previous: URL) -> Data? {
        guard let data = try? Data(contentsOf: latest) else { return nil }
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: latest, to: previous)
        return data
    }

    private static func outputsLine(_ variants: [String: [BenchVariant]], prior: [String: [BenchVariant]]?) -> String {
        let varied = variants.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value.map { String($0.runs) }.joined(separator: "+"))" }
        let consistency = varied.isEmpty ? "every run produced the same outputs" : "outputs varied within this run: \(varied)"
        guard let prior else { return "outputs: no previous run to compare; \(consistency)" }
        let new = variants.filter { scenario, mine in
            let theirs = prior[scenario]?.map(\.output) ?? []
            return mine.contains { !theirs.contains($0.output) }
        }.keys.sorted()
        return new.isEmpty
            ? "outputs: nothing the previous run did not also produce; \(consistency)"
            : "outputs: NEW, never produced by the previous run, in \(new); \(consistency)"
    }

    private static func render(_ result: BenchResult, against prior: BenchResult?, outputs: String) -> String {
        var lines = [
            "utt bench \(result.label) at \(result.date.formatted(.iso8601))" +
                " — \(result.runs) runs after \(result.warmups) warm-ups, model load \(format(result.modelLoadMs)) ms",
            outputs,
            "safety: \(result.safety.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))",
            prior.map { "Δ median against \($0.label) at \($0.date.formatted(.iso8601))" } ?? "no previous run",
            ""
        ]
        for scenario in scenarioOrder {
            guard let stages = result.scenarios[scenario] else { continue }
            let fixture = ["jobs-11s": "hotkey-11s", "cold": "hotkey-11s"][scenario] ?? scenario
            let seconds = result.fixtureSeconds[fixture] ?? 0
            lines.append("\(scenario) (\(format(seconds, digits: 1)) s clip)".padding(26) + "median".padded(10) + "p90".padded(10) + "Δmedian".padded(10))
            for stage in order where stages[stage] != nil {
                guard let summary = stages[stage] else { continue }
                let delta = prior?.scenarios[scenario]?[stage].map { format(summary.median - $0.median) } ?? ""
                lines.append("  \(stage)".padding(26) + format(summary.median).padded(10) + format(summary.p90).padded(10) + delta.padded(10))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

private extension String {
    func padding(_ width: Int) -> String { padding(toLength: max(width, count), withPad: " ", startingAt: 0) }
    func padded(_ width: Int) -> String { String(repeating: " ", count: max(0, width - count)) + self }
}
