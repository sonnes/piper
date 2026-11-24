import Captures
import CapturesDatabase
import Foundation

extension CaptureStore {
    /// A store on the database at a URL, as the app opens it.
    convenience init(url: URL) {
        self.init(database: Result { try Database(url: url) })
    }
}
