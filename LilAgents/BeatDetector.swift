import AVFoundation
import CoreMedia
import ScreenCaptureKit

class BeatDetector: NSObject {
    var onBeat: (() -> Void)?

    private var stream: SCStream?
    private var rmsHistory: [Float] = []
    private var lastBeatTime: TimeInterval = 0
    private let minBeatInterval: TimeInterval = 0.25
    private var bufferCount = 0

    func start() {
        Task { await startStream() }
    }

    func stop() {
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
    }

    private func startStream() async {
        print("[BeatDetector] starting...")

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                print("[BeatDetector] no display found")
                return
            }
            print("[BeatDetector] got display: \(display)")

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudioFromCapture = true
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )

            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(self, type: .audio,
                                  sampleHandlerQueue: .global(qos: .userInteractive))
            try await s.startCapture()
            stream = s
            print("[BeatDetector] stream started OK")
        } catch {
            print("[BeatDetector] ERROR: \(error)")
        }
    }
}

extension BeatDetector: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("[BeatDetector] stream stopped with error: \(error)")
    }
}

extension BeatDetector: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Get required buffer list size first
        var audioListSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &audioListSize,
            bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: nil)

        guard audioListSize > 0 else { return }

        // Allocate correctly-sized buffer list
        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: audioListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil,
            bufferListOut: rawPtr.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: audioListSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer)

        guard status == noErr else { return }

        // Sum RMS across all buffers/channels
        let bufferList = UnsafeMutableAudioBufferListPointer(
            rawPtr.assumingMemoryBound(to: AudioBufferList.self))
        var sum: Float = 0
        var totalCount = 0
        for buf in bufferList {
            guard let data = buf.mData else { continue }
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<count { sum += samples[i] * samples[i] }
            totalCount += count
        }
        guard totalCount > 0 else { return }
        let rms = sqrt(sum / Float(totalCount))

        // Log first few buffers so we can confirm audio is arriving
        bufferCount += 1
        if bufferCount <= 5 {
            print("[BeatDetector] buffer \(bufferCount): rms=\(rms)")
        }

        rmsHistory.append(rms)
        if rmsHistory.count > 43 { rmsHistory.removeFirst() }
        let avg = rmsHistory.reduce(0, +) / Float(max(rmsHistory.count, 1))

        let now = CACurrentMediaTime()
        if rms > max(avg * 1.6, 0.002) && now - lastBeatTime > minBeatInterval {
            lastBeatTime = now
            print("[BeatDetector] BEAT rms=\(rms) avg=\(avg)")
            DispatchQueue.main.async { [weak self] in self?.onBeat?() }
        }
    }
}
