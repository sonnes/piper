import Foundation
import Testing
@testable import Feeds

struct HackerNewsTests {

    private func item(_ id: Int, _ json: String) -> (String, StubProtocol.Answer) {
        ("https://hacker-news.firebaseio.com/v0/item/\(id).json", .init(status: 200, body: json))
    }

    @Test func topStoriesKeepTheOrderOfTheFrontPageAndSkipADeadStory() async throws {
        StubProtocol.serve(Dictionary(uniqueKeysWithValues: [
            ("https://hacker-news.firebaseio.com/v0/topstories.json", .init(status: 200, body: "[9003, 9001, 9002]")),
            item(9003, #"{"id":9003,"type":"story","by":"ada","title":"Tide &amp; time","url":"https://harbor.example/tides","score":40,"descendants":3,"time":1795835960,"kids":[1,2]}"#),
            item(9001, #"{"id":9001,"type":"story","by":"bo","title":"Ask HN: Ferries?","score":12,"descendants":0,"time":1795835000}"#),
            item(9002, #"{"id":9002,"type":"story","dead":true,"title":"Gone","time":1795835000}"#),
        ]))
        let stories = try await HackerNews.topStories(session: StubProtocol.session())
        #expect(stories.map(\.id) == [9003, 9001])
        #expect(stories[0].title == "Tide & time")
        #expect(stories[0].link == "https://harbor.example/tides")
        #expect(stories[1].url == nil)
        #expect(stories[1].link == "https://news.ycombinator.com/item?id=9001", "An Ask HN post links to its page.")
        #expect(stories[0].article.feedID == HackerNews.feedID)
    }

    @Test func theThreadKeepsTheOrderOfTheStoryPageAndSkipsADeletedComment() async throws {
        let story = HackerNews.Story(id: 9100, title: "Tides", url: nil, author: "ada", points: 1, comments: 3,
                                     time: Date(), kids: [3, 1])
        StubProtocol.serve(["https://hn.algolia.com/api/v1/items/9100": .init(status: 200, body: """
        {"id":9100,"text":"<p>Ask text","children":[
          {"id":1,"author":"bo","text":"First","created_at_i":1795835960,"children":[
            {"id":4,"author":null,"text":null,"children":[]}]},
          {"id":2,"author":"cy","text":"Not ranked","created_at_i":1795835960,"children":[]},
          {"id":3,"author":"di","text":"Top","created_at_i":1795835960,"children":[]}]}
        """)])
        let thread = try await HackerNews.thread(of: story, session: StubProtocol.session())
        #expect(thread.comments.map(\.id) == [3, 1, 2])
        #expect(thread.comments[1].replies.isEmpty)
        #expect(thread.text.map { String($0.characters) } == "Ask text")
    }

    @Test func theTextOfACommentKeepsParagraphsItalicsAndLinks() throws {
        let text = HackerNews.text(of: #"It&#x27;s <i>fast</i>.<p>See <a href="https:&#x2F;&#x2F;a.example&#x2F;x">a.example</a>"#)
        #expect(String(text.characters) == "It's fast.\n\nSee a.example")
        let italic = try #require(text.runs.first { $0.inlinePresentationIntent == .emphasized })
        #expect(String(text[italic.range].characters) == "fast")
        let link = try #require(text.runs.first { $0.link != nil })
        #expect(link.link == URL(string: "https://a.example/x"))
    }

    @Test func aCollapsedCommentHidesItsRepliesAndKeepsTheirCount() {
        let reply = HackerNews.Comment(id: 2, author: "b", text: "r", time: Date(),
                                       replies: [HackerNews.Comment(id: 3, author: "c", text: "rr", time: Date())])
        let comments = [HackerNews.Comment(id: 1, author: "a", text: "t", time: Date(), replies: [reply])]
        let open = HackerNews.rows(of: comments, collapsed: [])
        #expect(open.map(\.depth) == [0, 1, 2])
        #expect(open[2].ancestors == [1, 2], "The thread lines of a reply belong to the comments above it.")
        let collapsed = HackerNews.rows(of: comments, collapsed: [1])
        #expect(collapsed.map(\.id) == [1])
        #expect(collapsed[0].replyCount == 2)
    }
}
