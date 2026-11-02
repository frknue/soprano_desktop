import Foundation

/// The Folio alert sound: a short, soft pencil-on-paper tap — a woody C6 partial with a
/// quieter octave, a 3 ms attack and a ~35 ms decay, plus a tiny filtered noise grain at the
/// onset. Synthesised deterministically into a 16-bit mono AIFF (the format macOS's alert
/// sounds use), so the file never needs to ship in the repo.
enum AlertSound {
    static let fileName = "Soprano.aiff"
    static let sampleRate = 44_100
    static let duration = 0.16

    /// The 16-bit samples, peak about −6 dBFS.
    static func samples() -> [Int16] {
        let count = Int(Double(sampleRate) * duration)
        var noiseState: UInt32 = 0x50_52_41_4e
        var smoothed = 0.0
        return (0..<count).map { index in
            let t = Double(index) / Double(sampleRate)
            let attack = min(1, t / 0.003)
            let body = exp(-t / 0.035)
            let tone = sin(2 * .pi * 1046.5 * t) + 0.28 * sin(2 * .pi * 2093 * t) + 0.12 * sin(2 * .pi * 3140 * t)
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            let white = Double(noiseState >> 8) / Double(1 << 24) * 2 - 1
            smoothed += 0.35 * (white - smoothed)
            let grain = smoothed * exp(-t / 0.006) * 0.6
            let value = (tone * body * attack / 1.4 + grain) * 0.5
            return Int16(max(-1, min(1, value)) * Double(Int16.max))
        }
    }

    /// A complete AIFF file (FORM/COMM/SSND, big-endian).
    static func aiff() -> Data {
        let pcm = samples()
        var ssnd = Data()
        ssnd.append(uint32: 0) // offset
        ssnd.append(uint32: 0) // block size
        for sample in pcm {
            ssnd.append(uint16: UInt16(bitPattern: sample))
        }
        var comm = Data()
        comm.append(uint16: 1) // channels
        comm.append(uint32: UInt32(pcm.count))
        comm.append(uint16: 16)
        comm.append(extended80: Double(sampleRate))

        var body = Data("AIFF".utf8)
        body.append(chunk: "COMM", comm)
        body.append(chunk: "SSND", ssnd)
        var file = Data("FORM".utf8)
        file.append(uint32: UInt32(body.count))
        file.append(body)
        return file
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xff)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)])
    }

    mutating func append(chunk id: String, _ payload: Data) {
        append(Data(id.utf8))
        append(uint32: UInt32(payload.count))
        append(payload)
        if payload.count % 2 == 1 { append(0) }
    }

    /// IEEE 754 80-bit extended, as AIFF's sample rate field wants.
    mutating func append(extended80 value: Double) {
        guard value > 0 else {
            append(contentsOf: [UInt8](repeating: 0, count: 10))
            return
        }
        let exponent = Int(floor(log2(value)))
        let mantissa = UInt64(value / pow(2, Double(exponent - 63)))
        let biased = UInt16(exponent + 16383)
        append(uint16: biased)
        for shift in stride(from: 56, through: 0, by: -8) {
            append(UInt8((mantissa >> UInt64(shift)) & 0xff))
        }
    }
}
