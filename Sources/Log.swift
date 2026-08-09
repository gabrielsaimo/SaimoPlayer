import Foundation
import Combine

final class Log: ObservableObject {
    static let shared = Log()

    @Published private(set) var lines: [String] = []

    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func write(_ msg: String) {
        let line = "[\(fmt.string(from: Date()))] \(msg)"
        NSLog("%@", line)
        DispatchQueue.main.async {
            self.lines.append(line)
            if self.lines.count > 400 { self.lines.removeFirst(self.lines.count - 400) }
        }
    }

    func clear() {
        DispatchQueue.main.async { self.lines.removeAll() }
    }
}
