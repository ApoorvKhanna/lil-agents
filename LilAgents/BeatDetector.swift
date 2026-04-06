import AVFoundation

class BeatDetector {
    var onBeat: (() -> Void)?

    private var engine = AVAudioEngine()
    private var rmsHistory: [Float] = []
    private var lastBeatTime: TimeInterval = 0
    private let minBeatInterval: TimeInterval = 0.25 // max ~4 beats/sec
    private var isRunning = false

    func start() {
        guard !isRunning else { return }

        // Request mic permission then start
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.startEngine() } }
            }
        default:
            break
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func startEngine() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("BeatDetector: couldn't start audio engine: \(error)")
        }
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)

        // RMS of this buffer
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(count))

        // Rolling average over ~0.5 s (≈43 buffers at 44100/1024)
        rmsHistory.append(rms)
        if rmsHistory.count > 43 { rmsHistory.removeFirst() }
        let avg = rmsHistory.reduce(0, +) / Float(rmsHistory.count)

        let now = CACurrentMediaTime()
        // Onset: current RMS is notably louder than recent average
        if rms > max(avg * 1.6, 0.015) && now - lastBeatTime > minBeatInterval {
            lastBeatTime = now
            DispatchQueue.main.async { [weak self] in self?.onBeat?() }
        }
    }
}
