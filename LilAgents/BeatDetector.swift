import AVFoundation
import CoreMedia
import ScreenCaptureKit

// Captures system audio output (Spotify, YouTube, etc.) via ScreenCaptureKit
// and fires onBeat on detected amplitude onsets.
class BeatDetector: NSObject {
    var onBeat: (() -> Void)?

    private var stream: SCStream?
    private var rmsHistory: [Float] = []
    private var lastBeatTime: TimeInterval = 0
    private let minBeatInterval: TimeInterval = 0.25

    func start() {
        Task { await startStream() }
    }

    func stop() {
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
    }

    private func startStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return }

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudioFromCapture = true
            // Minimal video — we only care about audio
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )

            let s = SCStream(filter: filter, configuration: config, delegate: nil)
            try s.addStreamOutput(self, type: .audio,
                                  sampleHandlerQueue: .global(qos: .userInteractive))
            try await s.startCapture()
            stream = s
        } catch {
            print("BeatDetector: \(error)")
        }
    }
}

extension BeatDetector: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Pull raw Float32 PCM samples out of the CMSampleBuffer
        var blockBuffer: CMBlockBuffer?
        var audioList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let data = audioList.mBuffers.mData else { return }

        let count = Int(audioList.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return }

        let samples = data.assumingMemoryBound(to: Float.self)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = sqrt(sum / Float(count))

        rmsHistory.append(rms)
        if rmsHistory.count > 43 { rmsHistory.removeFirst() }
        let avg = rmsHistory.reduce(0, +) / Float(max(rmsHistory.count, 1))

        let now = CACurrentMediaTime()
        if rms > max(avg * 1.6, 0.002) && now - lastBeatTime > minBeatInterval {
            lastBeatTime = now
            DispatchQueue.main.async { [weak self] in self?.onBeat?() }
        }
    }
}
