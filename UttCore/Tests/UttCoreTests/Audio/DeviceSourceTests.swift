//
//  DeviceSourceTests.swift
//  UttCoreTests
//
//  The codes below are not invented: they are what `kAudioDevicePropertyTransportType`
//  and `kAudioDevicePropertyDataSource` actually returned when enumerated on a
//  MacBook Pro with an iPhone attached as a Continuity microphone, BlackHole
//  installed and Virtual Desktop running.
//

import Foundation
import Testing
@testable import UttCore

struct DeviceSourceTests {
    @Test("the codes a real Mac reports land on the right source")
    func classifiesMeasuredCodes() {
        #expect(DeviceSource.from(transport: "ccwd") == .continuityWired)
        #expect(DeviceSource.from(transport: "bltn", dataSource: "imic") == .builtIn)
        #expect(DeviceSource.from(transport: "virt") == .virtual)
    }

    /// The phone either way, but not the same situation: a wireless link is the one
    /// that drops, and "plug it in" is only advice worth giving if the label says
    /// which of the two you are looking at.
    @Test("wired and wireless Continuity are told apart")
    func bothContinuityTransports() {
        #expect(DeviceSource.from(transport: "ccwd") == .continuityWired)
        #expect(DeviceSource.from(transport: "ccwl") == .continuityWireless)
        #expect(DeviceSource.continuityWired.label == "Continuity · USB")
        #expect(DeviceSource.continuityWireless.label == "Continuity · Wi-Fi")
    }

    /// The one case where the transport alone is not enough — the jack and the
    /// internal microphone are both `bltn`.
    @Test("the data source separates the jack from the internal microphone")
    func splitsTheBuiltInDevice() {
        #expect(DeviceSource.from(transport: "bltn", dataSource: "emic") == .headphoneJack)
        #expect(DeviceSource.from(transport: "bltn", dataSource: nil) == .builtIn)
        // Only meaningful on the built-in device; a USB interface reporting some
        // data source of its own is still USB.
        #expect(DeviceSource.from(transport: "usb ", dataSource: "emic") == .usb)
    }

    /// Half these codes are padded to four characters and half are not, which is
    /// exactly the kind of difference that goes unnoticed until a device is
    /// mislabelled.
    @Test("padded and trimmed codes mean the same thing")
    func toleratesPadding() {
        #expect(DeviceSource.from(transport: "usb ") == .usb)
        #expect(DeviceSource.from(transport: "usb") == .usb)
    }

    @Test("an unrecognised transport is unlabelled rather than guessed at")
    func failsToOther() {
        #expect(DeviceSource.from(transport: "zzzz") == .other)
        #expect(DeviceSource.from(transport: "") == .other)
        #expect(DeviceSource.other.label == nil)
    }

    /// Reopening the input is offered for the source that goes quiet on its own and
    /// no other — a USB microphone that stopped has been unplugged.
    @Test("only Continuity offers a reconnect")
    func onlyContinuityReconnects() {
        let reconnectable = DeviceSource.allCases.filter(\.canReconnect)
        #expect(reconnectable == [.continuityWired, .continuityWireless])
    }

    @Test("every source but the unknown one has a label")
    func everythingElseIsLabelled() {
        let unlabelled = DeviceSource.allCases.filter { $0.label == nil }
        #expect(unlabelled == [.other])
    }
}
