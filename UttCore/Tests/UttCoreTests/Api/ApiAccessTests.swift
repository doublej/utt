//
//  ApiAccessTests.swift
//  UttCoreTests
//
//  The access scope is the whole security decision for the transcription API, so
//  the peer filter is pinned here rather than trusted to read correctly. It fails
//  towards `.anywhere`: anything it cannot classify is treated as the internet.
//

import Foundation
import Testing
@testable import UttCore

struct ApiAccessTests {
    // MARK: - Scope

    /// What this Mac's own interfaces say its networks are. `.localNetwork` is
    /// decided against these, not against the private ranges.
    private let home = [
        IPPrefix(address: IPAddress("192.168.178.0")!, bits: 24),
        IPPrefix(address: IPAddress("2001:db8:1234:5678::")!, bits: 64)
    ]

    @Test("this Mac lets loopback in and nothing else")
    func thisMacIsLoopbackOnly() {
        #expect(ApiAccess.thisMac.allows(peer: "127.0.0.1", localPrefixes: home))
        #expect(ApiAccess.thisMac.allows(peer: "::1", localPrefixes: home))
        #expect(!ApiAccess.thisMac.allows(peer: "192.168.178.20", localPrefixes: home))
        #expect(!ApiAccess.thisMac.allows(peer: "8.8.8.8", localPrefixes: home))
    }

    @Test("the local network is the networks this Mac is actually on")
    func localNetworkFollowsTheInterfaces() {
        #expect(ApiAccess.localNetwork.allows(peer: "127.0.0.1", localPrefixes: home))
        #expect(ApiAccess.localNetwork.allows(peer: "192.168.178.20", localPrefixes: home))
        #expect(!ApiAccess.localNetwork.allows(peer: "192.168.178.20", localPrefixes: []))
        #expect(!ApiAccess.localNetwork.allows(peer: "8.8.8.8", localPrefixes: home))
    }

    /// The reason this is not a private-range test. A phone on the same Wi-Fi very
    /// often has only a globally routable IPv6 address, and refusing it refuses the
    /// case the feature exists for.
    @Test("a globally addressed IPv6 peer on this Mac's own subnet is local")
    func globalIPv6OnTheSameSubnetIsLocal() {
        #expect(ApiAccess.localNetwork.allows(peer: "2001:db8:1234:5678::42", localPrefixes: home))
        #expect(!ApiAccess.localNetwork.allows(peer: "2001:db8:9999::1", localPrefixes: home))
    }

    /// The other half. A VPN hands out a private address for a network on the far
    /// side of the world; "looks private" would have let it straight in.
    @Test("a private address on someone else's network is not local")
    func privateAddressesElsewhereAreRefused() {
        for peer in ["10.8.0.6", "172.16.3.1", "192.168.1.20", "fd12:3456::1"] {
            #expect(!ApiAccess.localNetwork.allows(peer: peer, localPrefixes: home), "\(peer) is not on this Mac")
        }
    }

    /// Link-local is the same physical link by definition, and carries no prefix an
    /// interface reports.
    @Test("link-local peers are local")
    func linkLocalIsLocal() {
        #expect(ApiAccess.localNetwork.allows(peer: "fe80::1c2b:3d4e:5f60:7a8b%en0", localPrefixes: []))
        #expect(ApiAccess.localNetwork.allows(peer: "169.254.4.4", localPrefixes: []))
    }

    @Test("anywhere means anywhere, parseable or not")
    func anywhereAllowsEverything() {
        #expect(ApiAccess.anywhere.allows(peer: "8.8.8.8", localPrefixes: []))
        #expect(ApiAccess.anywhere.allows(peer: "", localPrefixes: []))
    }

    /// A loopback caller reaching a dual-stack listener arrives as `::ffff:127.0.0.1`,
    /// and an IPv6 link-local peer carries the interface it came in on. Neither is a
    /// reason to refuse a connection that is genuinely local.
    @Test("mapped IPv4 and zone ids are read, not refused")
    func normalizesAddressForms() {
        #expect(ApiAccess.thisMac.allows(peer: "::ffff:127.0.0.1", localPrefixes: home))
        #expect(ApiAccess.thisMac.allows(peer: "[::1]", localPrefixes: home))
    }

    /// The narrow scopes are the ones a wrong answer opens up, so anything that is
    /// not an address is the internet as far as they are concerned. The last two are
    /// what a split-on-the-separator reader gets wrong: dropping the parts that will
    /// not convert leaves four octets that read as loopback, and "starts with fd" is
    /// true of a word as much as of an address.
    @Test("an unreadable address is refused by every scope but anywhere")
    func unparseableAddressesAreRefused() {
        for peer in ["", "not-an-address", "999.1.1.1", "127.0.0", "127.0.0.1.extra", "fdgarbage"] {
            #expect(!ApiAccess.thisMac.allows(peer: peer, localPrefixes: home), "\(peer) is not loopback")
            #expect(!ApiAccess.localNetwork.allows(peer: peer, localPrefixes: home), "\(peer) is not local")
        }
    }

    // MARK: - Settings

    @Test("the API is off, loopback-only and tokenless by default")
    func defaultsAreClosed() {
        let api = ApiSettings()
        #expect(!api.enabled)
        #expect(api.access == .thisMac)
        #expect(api.configuration == nil)
    }

    /// The settings can hold "enabled with no token" — the toggle is written before
    /// the token is minted — and that state must never reach the listener.
    @Test("no configuration without a token")
    func failsClosedWithoutAToken() {
        var api = ApiSettings()
        api.enabled = true
        #expect(api.configuration == nil)

        api.token = "deadbeef"
        #expect(api.configuration?.token == "deadbeef")
    }

    @Test("a port no socket can carry yields no configuration")
    func failsClosedOnAnImpossiblePort() {
        var api = ApiSettings()
        api.enabled = true
        api.token = "deadbeef"
        for port in [0, -1, 70_000] {
            api.port = port
            #expect(api.configuration == nil, "port \(port) should not be servable")
        }
    }

    @Test("an absent api key decodes to the closed defaults")
    func decodesFromAnOlderFile() throws {
        let settings = try JSONDecoder().decode(UttSettings.self, from: Data("{}".utf8))
        #expect(settings.api == ApiSettings())
    }

    @Test("a half-written api object keeps the other defaults")
    func decodesKeyByKey() throws {
        let json = Data(#"{"api":{"access":"localNetwork"}}"#.utf8)
        let settings = try JSONDecoder().decode(UttSettings.self, from: json)
        #expect(settings.api.access == .localNetwork)
        #expect(!settings.api.enabled)
        #expect(settings.api.port == ApiSettings().port)
    }

    // MARK: - Token

    @Test("generated tokens are 32 hex characters and not each other")
    func generatesDistinctTokens() {
        let token = ApiToken.generate()
        let isHex = token.allSatisfy(\.isHexDigit)
        #expect(token.count == 32)
        #expect(isHex)
        #expect(token != ApiToken.generate())
    }

    @Test("only the exact token matches")
    func matchesOnlyTheWholeToken() {
        let token = ApiToken.generate()
        #expect(ApiToken.matches(token, token))
        #expect(!ApiToken.matches(String(token.dropLast()), token))
        #expect(!ApiToken.matches(token + "0", token))
        #expect(!ApiToken.matches("", token))
    }

    /// An empty stored token is "the API is not configured", never "anything goes".
    @Test("an empty token matches nothing, itself included")
    func anEmptyTokenNeverMatches() {
        #expect(!ApiToken.matches("", ""))
        #expect(!ApiToken.matches("anything", ""))
    }
}
