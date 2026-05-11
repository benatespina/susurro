import Foundation

enum PlaybackSpeed {
    static let steps: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    static let `default`: Float = 1.0

    static func next(from current: Float) -> Float {
        let index = nearestIndex(to: current)
        let nextIndex = (index + 1) % steps.count
        return steps[nextIndex]
    }

    static func previous(from current: Float) -> Float {
        let index = nearestIndex(to: current)
        let previousIndex = (index - 1 + steps.count) % steps.count
        return steps[previousIndex]
    }

    static func formatted(_ rate: Float) -> String {
        String(format: "%g", rate) + "x"
    }

    private static func nearestIndex(to value: Float) -> Int {
        var bestIndex = 0
        var bestDistance = abs(steps[0] - value)
        for (i, step) in steps.enumerated() {
            let distance = abs(step - value)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }
        return bestIndex
    }
}
