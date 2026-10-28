/// Which part of the live words is already on screen, so only the rest is written in.
public enum WritingSplit {
    /// The leading part of `current` that `previous` already showed.
    ///
    /// Growth keeps everything shown, mid-word included, so letters keep arriving
    /// after the ones before them. A revision cuts back to the last whole word, so a
    /// word the recogniser changed is written again whole rather than from its middle.
    public static func settled(previous: String, current: String) -> String {
        let shared = zip(previous, current).prefix { $0 == $1 }.count
        guard shared < previous.count, shared < current.count else {
            return String(current.prefix(shared))
        }
        let kept = current.prefix(shared)
        guard let space = kept.lastIndex(where: \.isWhitespace) else { return "" }
        return String(kept[...space])
    }
}
