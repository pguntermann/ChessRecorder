//
//  AudioPCMBufferLevel.swift
//  Chess Recorder
//

import AVFoundation

enum AudioPCMBufferLevel {
    struct Metrics {
        let rms: Float
        let peakAmplitude: Float
        /// Log-scaled 0…1 value for the live meter bar only (assessment uses raw `rms` / `peakAmplitude`).
        let displayLevel: Float
    }

    /// Maps linear amplitude to a 0…1 meter position using a standard −60…0 dBFS log scale.
    static func meterDisplayLevel(linear: Float) -> Float {
        guard linear > 0 else { return 0 }
        let floor: Float = 0.001
        let db = 20 * log10f(max(linear, floor))
        return min(1, max(0, (db + 60) / 60))
    }

    static func analyze(_ buffer: AVAudioPCMBuffer) -> Metrics? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let metrics: (rms: Float, peak: Float)?

        if buffer.format.isInterleaved {
            metrics = metricsFromInterleaved(buffer: buffer, frameCount: frameCount)
        } else if let floatChannels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var bestRMS: Float = 0
            var bestPeak: Float = 0
            for channel in 0..<channelCount {
                let channelMetrics = metricsFromFloat(samples: floatChannels[channel], count: frameCount)
                bestRMS = max(bestRMS, channelMetrics.rms)
                bestPeak = max(bestPeak, channelMetrics.peak)
            }
            metrics = bestRMS > 0 ? (bestRMS, bestPeak) : nil
        } else if let int16Channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var bestRMS: Float = 0
            var bestPeak: Float = 0
            for channel in 0..<channelCount {
                let channelMetrics = metricsFromInt16(samples: int16Channels[channel], count: frameCount)
                bestRMS = max(bestRMS, channelMetrics.rms)
                bestPeak = max(bestPeak, channelMetrics.peak)
            }
            metrics = bestRMS > 0 ? (bestRMS, bestPeak) : nil
        } else {
            metrics = nil
        }

        guard let metrics, metrics.peak > 0 else { return nil }

        return Metrics(
            rms: metrics.rms,
            peakAmplitude: metrics.peak,
            displayLevel: meterDisplayLevel(linear: metrics.peak)
        )
    }

    private static func metricsFromInterleaved(buffer: AVAudioPCMBuffer, frameCount: Int) -> (rms: Float, peak: Float)? {
        if let floatChannels = buffer.floatChannelData {
            return metricsFromFloat(samples: floatChannels[0], count: frameCount)
        }
        if let int16Channels = buffer.int16ChannelData {
            return metricsFromInt16(samples: int16Channels[0], count: frameCount)
        }
        return nil
    }

    private static func metricsFromFloat(samples: UnsafePointer<Float>, count: Int) -> (rms: Float, peak: Float) {
        var sum: Float = 0
        var peak: Float = 0
        for index in 0..<count {
            let sample = abs(samples[index])
            peak = max(peak, sample)
            sum += sample * sample
        }
        return (sqrt(sum / Float(count)), peak)
    }

    private static func metricsFromInt16(samples: UnsafePointer<Int16>, count: Int) -> (rms: Float, peak: Float) {
        var sum: Float = 0
        var peak: Float = 0
        for index in 0..<count {
            let sample = abs(Float(samples[index]) / 32_768)
            peak = max(peak, sample)
            sum += sample * sample
        }
        return (sqrt(sum / Float(count)), peak)
    }
}
