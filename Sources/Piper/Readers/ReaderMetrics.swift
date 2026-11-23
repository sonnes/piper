import Foundation

/// The values that several reader views share.
enum ReaderMetrics {
    /// The wait after the last key before a note or a summary saves.
    static let saveDelay = Duration.milliseconds(600)
}
