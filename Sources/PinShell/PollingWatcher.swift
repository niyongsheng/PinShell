import Foundation

/// 轮询签名并在稳定窗口后回调的通用监视器。
/// 定时读取 `signature`，连续两次一致才在主线程回调，避免读到半截写入。
final class PollingWatcher<Signature: Equatable> {
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let pollInterval: TimeInterval
    private let settleDelay: TimeInterval
    private let leeway: DispatchTimeInterval
    private let signature: () -> Signature
    private let onChange: () -> Void

    private var timer: DispatchSourceTimer?
    private var lastSignature: Signature?
    private var pending: DispatchWorkItem?
    private var started = false

    init(label: String,
         pollInterval: TimeInterval,
         settleDelay: TimeInterval,
         leeway: DispatchTimeInterval = .milliseconds(100),
         signature: @escaping () -> Signature,
         onChange: @escaping () -> Void) {
        self.queue = DispatchQueue(label: label)
        self.pollInterval = pollInterval
        self.settleDelay = settleDelay
        self.leeway = leeway
        self.signature = signature
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopLocked()
        } else {
            queue.sync { stopLocked() }
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.started else { return }
            self.started = true
            self.lastSignature = self.signature()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.pollInterval,
                           repeating: self.pollInterval,
                           leeway: self.leeway)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopLocked()
        } else {
            queue.sync { stopLocked() }
        }
    }

    private func stopLocked() {
        started = false
        pending?.cancel()
        pending = nil
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard started else { return }
        let current = signature()
        guard current != lastSignature else { return }
        lastSignature = current

        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.started, self.signature() == current else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }
}
