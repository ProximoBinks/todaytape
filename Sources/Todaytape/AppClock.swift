import Foundation
import Combine

/// Only time-dependent views observe this clock. A tick must not invalidate
/// settings, the app scene, or the hidden overlay.
@MainActor
final class AppClock: ObservableObject {
    static let shared = AppClock()

    @Published private(set) var now = Date()
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        now = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
