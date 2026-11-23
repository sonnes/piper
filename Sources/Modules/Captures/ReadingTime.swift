import Foundation

/// The reading time of a text, at 230 words a minute.
public enum ReadingTime {
    private static let wordsPerMinute: Double = 230

    public static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Whole minutes, and at least one.
    public static func minutes(words: Int) -> Int {
        max(1, Int((Double(words) / wordsPerMinute).rounded()))
    }
}
