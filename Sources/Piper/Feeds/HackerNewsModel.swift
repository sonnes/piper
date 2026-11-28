import Feeds
import Foundation

/// The stories of the Hacker News tab.
///
/// Piper keeps the stories in memory while it runs. It writes no story and no
/// read mark to the database. Keep is the only way to save a story.
@MainActor @Observable
final class HackerNewsModel {

    // MARK: - Properties

    /// The stories of the front page, after the last fetch that worked.
    private(set) var stories: [HackerNews.Story] = []
    private(set) var loading = false
    /// The error of the last fetch, until the next fetch starts.
    private(set) var error: String?
    var selectedID: Int?
    /// Reads the front page. A test replaces it, so that no request leaves the Mac.
    @ObservationIgnored var fetch: () async throws -> [HackerNews.Story] = { try await HackerNews.topStories() }
    /// The fetch that runs. A test waits for it.
    @ObservationIgnored private(set) var task: Task<Void, Never>?

    // MARK: - API

    var selected: HackerNews.Story? { stories.first { $0.id == selectedID } }

    /// Reads the front page when the tab shows for the first time.
    func loadIfEmpty() {
        guard stories.isEmpty, !loading else { return }
        refresh()
    }

    /// Reads the front page again. A new fetch cancels the fetch that runs.
    func refresh() {
        task?.cancel()
        loading = true
        error = nil
        let fetch = fetch
        task = Task { [weak self] in
            let result: Result<[HackerNews.Story], Error>
            do { result = .success(try await fetch()) } catch { result = .failure(error) }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let stories):
                self.stories = stories
                if let selectedID, !stories.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
            case .failure(let error):
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
