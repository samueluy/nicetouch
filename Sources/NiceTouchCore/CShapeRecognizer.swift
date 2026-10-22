import Foundation

/// A fixed, orientation-sensitive template matcher. AI never sees touch traces.
/// Accepts either stroke direction, with the opening on the right.
struct CShapeRecognizer {
    private var points: [Contact] = []
    private var began: Double?
    private var previousTime = 0.0
    private var invalid = false
    mutating func feed(_ contacts: [Contact], time: Double) -> RecognizedGesture? {
        guard time.isFinite, contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            invalid = true; return nil
        }
        if contacts.isEmpty {
            defer { self = CShapeRecognizer() }
            guard !invalid, let began, time >= previousTime, (0.2...3).contains(time - began), points.count >= 8,
                  matches(points), let start = points.first else { return nil }
            return RecognizedGesture(gesture: Gesture(kind: .drawC, fingers: 1, direction: .none), x: start.x, y: start.y)
        }
        if began == nil { began = time; previousTime = time }
        guard !invalid, contacts.count == 1, time >= previousTime, time - began! <= 3 else { invalid = true; return nil }
        previousTime = time
        let point = contacts[0]
        if let last = points.last, distance(last, point) < 0.003 { return nil }
        if points.count == 256 { points = stride(from: 0, to: points.count, by: 2).map { points[$0] } }
        points.append(point)
        return nil
    }
    private func matches(_ path: [Contact]) -> Bool {
        let xs = path.map(\.x), ys = path.map(\.y)
        let width = xs.max()! - xs.min()!, height = ys.max()! - ys.min()!
        guard width >= 0.15, height >= 0.15, (0.45...2).contains(width / height) else { return false }
        let first = path.first!, last = path.last!, minX = xs.min()!
        guard first.x > minX + width * 0.65, last.x > minX + width * 0.65,
              abs(first.y - last.y) > height * 0.45, abs(first.x - last.x) < width * 0.35 else { return false }
        let normalized = normalize(resample(path))
        let template = normalize(resample((0...64).map { index in
            let angle = Double.pi / 4 + Double(index) / 64 * 1.5 * Double.pi
            return Contact(x: cos(angle), y: sin(angle))
        }))
        let forward = zip(normalized, template).map(distance).reduce(0, +) / Double(template.count)
        let backward = zip(normalized.reversed(), template).map(distance).reduce(0, +) / Double(template.count)
        return min(forward, backward) < 0.13
    }
    private func normalize(_ points: [Contact]) -> [Contact] {
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        // Normalize each axis to accommodate the physical trackpad aspect ratio.
        return points.map { Contact(x: ($0.x - minX) / (maxX - minX), y: ($0.y - minY) / (maxY - minY)) }
    }
    private func resample(_ points: [Contact]) -> [Contact] {
        var lengths = [0.0]
        for index in 1..<points.count { lengths.append(lengths.last! + distance(points[index - 1], points[index])) }
        let total = lengths.last!
        var segment = 1
        return (0..<48).map { index in
            let target = total * Double(index) / 47
            while segment < points.count - 1 && lengths[segment] < target { segment += 1 }
            let span = lengths[segment] - lengths[segment - 1]
            let fraction = span > 0 ? (target - lengths[segment - 1]) / span : 0
            let a = points[segment - 1], b = points[segment]
            return Contact(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
        }
    }
    private func distance(_ a: Contact, _ b: Contact) -> Double { hypot(a.x - b.x, a.y - b.y) }
}
