//
//  IPAddressTests.swift
//  UttCoreTests
//
//  The access filter is only as good as the parser under it, and a parser that
//  fails open is the whole bug class. Everything here is about what must NOT
//  parse, and about a prefix meaning the same thing in both address families.
//

import Foundation
import Testing
@testable import UttCore

struct IPAddressTests {
    // MARK: - Parsing

    @Test("real addresses parse to their bytes")
    func parsesRealAddresses() throws {
        #expect(try #require(IPAddress("127.0.0.1")).bytes == [127, 0, 0, 1])
        #expect(try #require(IPAddress("192.168.178.20")).family == .version4)
        #expect(try #require(IPAddress("::1")).family == .version6)
        #expect(try #require(IPAddress("2001:db8::42")).bytes.count == 16)
    }

    /// A peer on a dual-stack socket arrives mapped. It is an IPv4 address and has
    /// to be classified as one, or loopback stops looking like loopback.
    @Test("a mapped IPv4 address comes back as IPv4")
    func unwrapsMappedAddresses() throws {
        let mapped = try #require(IPAddress("::ffff:127.0.0.1"))
        #expect(mapped.family == .version4)
        #expect(mapped.bytes == [127, 0, 0, 1])
        #expect(mapped.isLoopback)
    }

    @Test("brackets and zone ids are tolerated")
    func toleratesTheFormsPeersArriveIn() throws {
        #expect(try #require(IPAddress("[::1]")).isLoopback)
        #expect(try #require(IPAddress("fe80::1%en0")).isLinkLocal)
    }

    /// The two cases a split-and-drop reader gets wrong, and the reason this goes
    /// through `inet_pton` instead.
    @Test("things that merely look like addresses do not parse")
    func refusesNonAddresses() {
        for text in ["", "127.0.0.1.extra", "fdgarbage", "999.1.1.1", "127.0.0", "localhost", "1.2.3.4:8756"] {
            #expect(IPAddress(text) == nil, "\(text) is not an address")
        }
    }

    // MARK: - Classification

    @Test("loopback and link-local are recognised in both families")
    func classifiesTheSpecialRanges() throws {
        #expect(try #require(IPAddress("127.0.0.1")).isLoopback)
        #expect(try #require(IPAddress("127.1.2.3")).isLoopback)
        #expect(try #require(IPAddress("::1")).isLoopback)
        #expect(try #require(IPAddress("169.254.4.4")).isLinkLocal)
        #expect(try #require(IPAddress("fe80::1")).isLinkLocal)
        #expect(try #require(IPAddress("fec0::1")).isLinkLocal == false)
        #expect(try #require(IPAddress("192.168.1.1")).isLoopback == false)
    }

    // MARK: - Netmasks

    @Test("a netmask reads as the number of bits it sets")
    func readsPrefixLengths() throws {
        #expect(try #require(IPAddress("255.255.255.0")).prefixLength == 24)
        #expect(try #require(IPAddress("255.255.0.0")).prefixLength == 16)
        #expect(try #require(IPAddress("255.255.255.252")).prefixLength == 30)
        #expect(try #require(IPAddress("0.0.0.0")).prefixLength == 0)
        #expect(try #require(IPAddress("ffff:ffff:ffff:ffff::")).prefixLength == 64)
    }

    /// A mask with a hole in it is not a mask, and guessing a length from it would
    /// invent a network this Mac is not on.
    @Test("a mask with a gap is not a mask")
    func refusesADiscontiguousMask() throws {
        #expect(try #require(IPAddress("255.0.255.0")).prefixLength == nil)
    }

    // MARK: - Prefixes

    @Test("a prefix contains its own network and nothing outside it")
    func matchesWithinAPrefix() throws {
        let network = IPPrefix(address: try #require(IPAddress("192.168.178.0")), bits: 24)
        #expect(network.contains(try #require(IPAddress("192.168.178.1"))))
        #expect(network.contains(try #require(IPAddress("192.168.178.255"))))
        #expect(!network.contains(try #require(IPAddress("192.168.179.1"))))
    }

    @Test("a prefix that does not end on a byte still cuts in the right place")
    func matchesOnARaggedBoundary() throws {
        let network = IPPrefix(address: try #require(IPAddress("10.0.0.0")), bits: 12)
        #expect(network.contains(try #require(IPAddress("10.15.255.1"))))
        #expect(!network.contains(try #require(IPAddress("10.16.0.1"))))
    }

    /// The numbers can line up across families; the addresses still are not the
    /// same machine.
    @Test("an IPv4 peer is never inside an IPv6 prefix")
    func keepsTheFamiliesApart() throws {
        let network = IPPrefix(address: try #require(IPAddress("2001:db8::")), bits: 32)
        #expect(!network.contains(try #require(IPAddress("32.1.13.184"))))
        #expect(network.contains(try #require(IPAddress("2001:db8:1::9"))))
    }
}
