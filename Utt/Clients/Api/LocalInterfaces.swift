import Darwin
import Foundation
import UttCore

/// The networks this Mac is actually attached to.
///
/// Read fresh every time rather than cached: a laptop changes networks by being
/// carried into another room, and a stale prefix is either a connection refused for
/// no reason or — the direction that matters — one allowed for no reason.
/// `getifaddrs` costs microseconds; a wrong answer costs more.
enum LocalInterfaces {
    /// Every up, non-loopback interface's network. Loopback is left out because the
    /// access filter answers for it directly, and an empty list is the honest
    /// answer for a Mac that is on no network — `.localNetwork` then admits only
    /// loopback and the same physical link, which is what being on no network means.
    static func prefixes() -> [IPPrefix] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var found: [IPPrefix] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(bitPattern: interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let rawAddress = interface.pointee.ifa_addr,
                  let rawMask = interface.pointee.ifa_netmask,
                  let address = numericHost(rawAddress).flatMap(IPAddress.init),
                  let bits = numericHost(rawMask).flatMap(IPAddress.init)?.prefixLength
            else { continue }
            found.append(IPPrefix(address: address, bits: bits))
        }
        return found
    }

    /// `getnameinfo` rather than reaching into `sin_addr` by hand: one call covers
    /// both address families, and a netmask that does not render as an address is
    /// one this has no business guessing at.
    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(address.pointee.sa_len)
        guard length > 0,
              getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(cString: host)
    }
}
