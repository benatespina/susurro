import Testing
@testable import Susurro

struct PlaybackSpeedTests {
    @Test func stepsMatchExpected() {
        #expect(PlaybackSpeed.steps == [0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
    }

    @Test func defaultIsOne() {
        #expect(PlaybackSpeed.default == 1.0)
    }

    @Test func nextFromOneIsOneTwentyFive() {
        #expect(PlaybackSpeed.next(from: 1.0) == 1.25)
    }

    @Test func nextFromTwoWrapsToZeroSevenFive() {
        #expect(PlaybackSpeed.next(from: 2.0) == 0.75)
    }

    @Test func previousFromOneTwentyFiveIsOne() {
        #expect(PlaybackSpeed.previous(from: 1.25) == 1.0)
    }

    @Test func previousFromZeroSevenFiveWrapsToTwo() {
        #expect(PlaybackSpeed.previous(from: 0.75) == 2.0)
    }

    @Test func formattedOneIsOneX() {
        #expect(PlaybackSpeed.formatted(1.0) == "1x")
    }

    @Test func formattedOneTwentyFiveIsOneTwentyFiveX() {
        #expect(PlaybackSpeed.formatted(1.25) == "1.25x")
    }

    @Test func formattedOneFiftyIsOneFiftyX() {
        #expect(PlaybackSpeed.formatted(1.5) == "1.5x")
    }

    @Test func formattedZeroSevenFiveIsZeroSevenFiveX() {
        #expect(PlaybackSpeed.formatted(0.75) == "0.75x")
    }

    @Test func formattedTwoIsTwoX() {
        #expect(PlaybackSpeed.formatted(2.0) == "2x")
    }
}
