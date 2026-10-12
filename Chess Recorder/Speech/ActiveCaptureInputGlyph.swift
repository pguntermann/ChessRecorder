//
//  ActiveCaptureInputGlyph.swift
//  Chess Recorder
//

import AVFoundation
import UIKit

/// Maps the active capture route to a native SF Symbol (AirPods, iPhone/iPad, etc.).
enum ActiveCaptureInputGlyph {
    struct Snapshot: Equatable {
        let systemImage: String
        let accessibilityName: String
    }

    /// Uses the live capture route (true active input). Callers should debounce
    /// brief transitional route changes during session activation.
    static func snapshot(session: AVAudioSession = .sharedInstance()) -> Snapshot? {
        guard let port = session.currentRoute.inputs.first ?? session.preferredInput else {
            return nil
        }
        return Snapshot(
            systemImage: systemImage(for: port),
            accessibilityName: port.portName
        )
    }

    static func systemImage(for port: AVAudioSessionPortDescription) -> String {
        systemImage(portName: port.portName, portType: port.portType.rawValue)
    }

    private static func systemImage(portName: String, portType: String) -> String {
        let name = portName.lowercased()
        let port = AVAudioSession.Port(rawValue: portType)

        switch port {
        case .builtInMic:
            return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        case .headsetMic:
            if name.contains("earpods") {
                return "earpods"
            }
            return "earbuds"
        case .bluetoothHFP, .bluetoothLE:
            return bluetoothSystemImage(forPortName: name)
        case .usbAudio:
            return "cable.connector"
        case .carAudio:
            return "car"
        default:
            return "mic"
        }
    }

    private static func bluetoothSystemImage(forPortName name: String) -> String {
        if name.contains("airpods max") {
            return "airpods.max"
        }
        if name.contains("airpods pro") {
            return "airpods.pro"
        }
        if name.contains("airpods") {
            if name.contains("gen 4") || name.contains("gen4") || name.contains("4.") {
                return "airpods.gen4"
            }
            if name.contains("gen 3") || name.contains("gen3") || name.contains("3.") {
                return "airpods.gen3"
            }
            return "airpods"
        }
        if name.contains("beats") {
            if name.contains("fit") {
                return "beats.fitpro"
            }
            if name.contains("pill") {
                return "beats.pill"
            }
            if name.contains("studio") || name.contains("solo") || name.contains("headphones") {
                return "beats.headphones"
            }
            return "beats.earphones"
        }
        return "headphones"
    }
}
