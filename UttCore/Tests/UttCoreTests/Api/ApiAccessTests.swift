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

    @Test("this Mac lets loopback in and nothing else")
    func thisMacIsLoopbackOnly() {
        #expect(ApiAccess.thisMac.allows(peer: "127.0.0.1"))
        #expect(ApiAccess.thisMac.allows(peer: "::1"))
        #expect(!ApiAccess.thisMac.allows(peer: "192.168.1.20"))
        #expect(!ApiAccess.thisMac.allows(peer: "8.8.8.8"))
    }

    @Test("the local network is loopback plus the private ranges")
    func localNetworkCoversPrivateRanges() {
        for peer in ["127.0.0.1", "10.0.0.4", "172.16.3.1", "172.31.255.254", "192.168.1.20", "169.254.4.4"] {
            #expect(ApiAccess.localNetwork.allows(peer: peer), "\(peer) should be local")
        }
        for peer in ["8.8.8.8", "172.15.0.1", "172.32.0.1", "1.1.1.1"] {
            #expect(!ApiAccess.localNetwork.allows(peer: peer), "\(peer) should not be local")
        }
    }

    @Test("IPv6 unique-local and link-local count as the local network")
    func localNetworkCoversIPv6() {
        #expect(ApiAccess.localNetwork.allows(peer: "fd12:3456::1"))
        #expect(ApiAccess.localNetwork.allows(peer: "fe80::1c2b:3d4e:5f60:7a8b"))
        #expect(!ApiAccess.localNetwork.allows(peer: "2001:db8::1"))
    }

    @Test("anywhere means anywhere")
    func anywhereAllowsEverything() {
        #expect(ApiAccess.anywhere.allows(peer: "8.8.8.8"))
        #expect(ApiAccess.anywhere.allows(peer: ""))
    }

    /// A loopback caller reaching a dual-stack listener arrives as `::ffff:127.0.0.1`,
    /// and an IPv6 link-local peer carries the interface it came in on. Neither is a
    /// reason to refuse a connection that is genuinely local.
    @Test("mapped IPv4 and zone ids are read, not refused")
    func normalizesAddressForms() {
        #expect(ApiAccess.thisMac.allows(peer: "::ffff:127.0.0.1"))
        #expect(ApiAccess.localNetwork.allows(peer: "fe80::1%en0"))
        #expect(ApiAccess.thisMac.allows(peer: "[::1]"))
    }

    /// The narrow scopes are the ones a wrong answer would open up, so an address
    /// this cannot parse is the internet as far as they are concerned.
    @Test("an unreadable address is refused by every scope but anywhere")
    func unparseableAddressesAreRefused() {
        for peer in ["", "not-an-address", "999.1.1.1", "127.0.0"] {
            #expect(!ApiAccess.thisMac.allows(peer: peer), "\(peer) should not be loopback")
            #expect(!ApiAccess.localNetwork.allows(peer: peer), "\(peer) should not be local")
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
