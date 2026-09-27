import CoreText
import SwiftUI

/// The offset deliberately does not invalidate the workspace on every scroll event.
@MainActor @Observable
final class RecordGalleryScrollState {
    let geometry = RecordGalleryLayout()
    @ObservationIgnored var offset: CGFloat = 0
    private(set) var resetGeneration = 0

    func reset() {
        offset = 0
        resetGeneration += 1
    }
}

struct RecordMasonryLayout {
    var minimumColumnWidth: CGFloat
    var spacing: CGFloat = 16

    func columnCount(for width: CGFloat) -> Int {
        max(1, Int((max(0, width) + spacing) / (minimumColumnWidth + spacing)))
    }

    func columnWidth(for width: CGFloat) -> CGFloat {
        let count = columnCount(for: width)
        return max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
    }

    func frames(for width: CGFloat, heights: [CGFloat]) -> [CGRect] {
        let count = columnCount(for: width)
        let cardWidth = columnWidth(for: width)
        var bottoms = Array(repeating: CGFloat.zero, count: count)
        return heights.map { height in
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let frame = CGRect(x: CGFloat(column) * (cardWidth + spacing), y: bottoms[column], width: cardWidth, height: height)
            bottoms[column] = frame.maxY + spacing
            return frame
        }
    }
}

/// Per-column binary search keeps scroll queries proportional to the viewport,
/// rather than scanning every cached frame in a large library.
struct RecordMasonryIndex {
    let frames: [CGRect]
    private let columns: [[Int]]
    let contentSize: CGSize

    init(layout: RecordMasonryLayout, width: CGFloat, heights: [CGFloat]) {
        let innerWidth = max(0, width - 40)
        frames = layout.frames(for: innerWidth, heights: heights).map { $0.offsetBy(dx: 20, dy: 20) }
        var columns = Array(repeating: [Int](), count: layout.columnCount(for: innerWidth))
        for (index, frame) in frames.enumerated() {
            let column = Int(((frame.minX - 20) / (layout.columnWidth(for: innerWidth) + layout.spacing)).rounded())
            columns[column].append(index)
        }
        self.columns = columns
        contentSize = CGSize(width: width, height: (frames.map(\.maxY).max() ?? 20) + 20)
    }

    func items(in rect: CGRect) -> [Int] {
        var result: [Int] = []
        for column in columns {
            var lower = 0
            var upper = column.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if frames[column[middle]].maxY < rect.minY { lower = middle + 1 } else { upper = middle }
            }
            for position in lower..<column.count {
                let index = column[position]
                if frames[index].minY > rect.maxY { break }
                if frames[index].intersects(rect) { result.append(index) }
            }
        }
        return result.sorted()
    }
}

struct RecordCardPreview: Equatable {
    let id: UUID
    let title: String
    let summary: String
    let updatedAt: Date

    init(note: Note) {
        id = note.id
        title = note.displayTitle
        let text = note.text
        summary = text.isEmpty ? L10n.string("note.body.empty") : String(text.prefix(600))
        updatedAt = note.updatedAt
    }
}

struct RecordCardTypography: Equatable {
    let title: Font.Resolved
    let summary: Font.Resolved
    let caption: Font.Resolved
    let minimumHeight: CGFloat
    let maximumHeight: CGFloat

    func height(for preview: RecordCardPreview, width: CGFloat) -> CGFloat {
        let textWidth = max(1, width - 32)
        let titleHeight = textHeight(preview.title, font: title.ctFont, width: max(1, textWidth - 8), lines: 2)
        let summaryHeight = textHeight(preview.summary, font: summary.ctFont, width: textWidth, lines: 12)
        let dateHeight = ceil(CTFontGetAscent(caption.ctFont) + CTFontGetDescent(caption.ctFont) + CTFontGetLeading(caption.ctFont))
        return min(maximumHeight, max(minimumHeight, ceil(titleHeight + summaryHeight + dateHeight + 56)))
    }

    private func textHeight(_ text: String, font: CTFont, width: CGFloat, lines: Int) -> CGFloat {
        let lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: lineHeight * CGFloat(lines)), nil)
        return min(lineHeight * CGFloat(lines), max(lineHeight, ceil(size.height)))
    }
}

/// Caches bounded text measurements, not offscreen SwiftUI views or rich documents.
@MainActor
final class RecordGalleryLayout {
    private(set) var previews: [RecordCardPreview] = []
    private var typography: RecordCardTypography?
    private var cachedTypography: RecordCardTypography?
    private var cachedWidth: CGFloat = -1
    private var heights: [UUID: (preview: RecordCardPreview, height: CGFloat)] = [:]
    private var needsLayout = true
    private(set) var measurementCount = 0
    private(set) var index = RecordMasonryIndex(layout: RecordMasonryLayout(minimumColumnWidth: 220), width: 0, heights: [])

    func update(previews: [RecordCardPreview], typography: RecordCardTypography) -> Bool {
        guard self.previews != previews || self.typography != typography else { return false }
        self.previews = previews
        self.typography = typography
        let ids = Set(previews.map(\.id))
        heights = heights.filter { ids.contains($0.key) }
        needsLayout = true
        return true
    }

    func prepare(width: CGFloat, minimumColumnWidth: CGFloat) {
        guard width > 0, let typography else { return }
        let layout = RecordMasonryLayout(minimumColumnWidth: minimumColumnWidth)
        let cardWidth = layout.columnWidth(for: max(0, width - 40))
        guard needsLayout || index.contentSize.width != width else { return }
        if cachedWidth != cardWidth || cachedTypography != typography {
            heights.removeAll(keepingCapacity: true)
            cachedWidth = cardWidth
            cachedTypography = typography
        }
        let values = previews.map { preview in
            if let cached = heights[preview.id], cached.preview == preview { return cached.height }
            let height = typography.height(for: preview, width: cardWidth)
            heights[preview.id] = (preview, height)
            measurementCount += 1
            return height
        }
        index = RecordMasonryIndex(layout: layout, width: width, heights: values)
        needsLayout = false
    }
}
