import SwiftUI
import Testing

@testable import Weave

struct RecordMasonryLayoutTests {
    @Test func shortCardsFillTheShortestColumn() {
        let layout = RecordMasonryLayout(minimumColumnWidth: 220)
        let frames = layout.frames(for: 692, heights: [120, 320, 200, 150, 180])
        #expect(frames[3].minX == frames[0].minX)
        #expect(frames[3].minY == 136)
        #expect(frames[4].minX == frames[2].minX)
        #expect(frames[4].minY == 216)
    }

    @Test(arguments: [CGFloat(100), 219, 455, 456, 691, 692, 1000, 1600])
    func responsiveCardsFitWithoutOverlapping(width: CGFloat) {
        let layout = RecordMasonryLayout(minimumColumnWidth: 220)
        let heights: [CGFloat] = [120, 320, 150, 210, 280, 120, 170, 310, 230]
        let frames = layout.frames(for: width, heights: heights)
        #expect(frames.count == heights.count)
        for (index, frame) in frames.enumerated() {
            #expect(frame.minX >= 0)
            #expect(frame.maxX <= width + 0.001)
            #expect(frame.height == heights[index])
            for other in frames.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
        #expect(layout.columnCount(for: 455) == 1)
        #expect(layout.columnCount(for: 456) == 2)
        #expect(layout.columnCount(for: 692) == 3)
        #expect(layout.frames(for: width, heights: []).isEmpty)
    }
}
