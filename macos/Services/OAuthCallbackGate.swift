import Foundation

final class OAuthCallbackGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func run(_ action: () -> Void) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        action()
    }
}
