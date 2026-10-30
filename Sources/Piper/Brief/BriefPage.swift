import AppKit
import Briefs
import Captures
import SwiftUI

/// The page that the main window opens on. It shows the brief of one day, the
/// state of a build, and the sites of the first build.
struct BriefPage: View {
    let model: AppModel

    @State private var showsSites = false

    private var brief: BriefBuilder { model.brief }

    private var selectedIndex: Int? {
        guard !brief.files.isEmpty else { return nil }
        return brief.files.firstIndex { $0.id == brief.selectedID } ?? 0
    }

    var body: some View {
        Group {
            if let index = selectedIndex {
                VStack(spacing: 0) {
                    status
                    header(index)
                    Rule()
                    BriefReader(model: model, file: brief.files[index], text: brief.body(of: brief.files[index]) ?? "")
                        .id(brief.files[index].id)
                }
                .background(PiperTheme.reader)
            } else {
                VStack(spacing: 0) {
                    status
                    BriefSitesView(brief: brief)
                }
                .background(PiperTheme.page)
            }
        }
        .foregroundStyle(PiperTheme.ink)
        .sheet(isPresented: $showsSites) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { showsSites = false }.buttonStyle(.text).keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Rule()
                BriefSitesView(brief: brief)
            }
            .foregroundStyle(PiperTheme.ink)
            .background(PiperTheme.page)
            .frame(width: AppDefaults.Brief.signInSize.width, height: AppDefaults.Brief.signInSize.height)
        }
    }

    /// The bar over a brief, as the address bar is over an article.
    private func header(_ index: Int) -> some View {
        let file = brief.files[index]
        let line = [Self.dateLine(of: file.id), DetailHeader.readingTime(of: brief.body(of: file) ?? "")]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 8) {
            Text(line)
                .font(PiperTheme.ui(AppDefaults.ArticleReader.addressFontSize))
                .foregroundStyle(PiperTheme.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Sites") { showsSites = true }.buttonStyle(.text)
            Button("Rebuild") {
                brief.selectedID = nil
                brief.build()
            }
            .buttonStyle(.text)
            .disabled(brief.state.isBuilding)
            IconButton(title: "Earlier Brief", icon: "chevron.left") { brief.selectedID = brief.files[index + 1].id }
                .disabled(index + 1 >= brief.files.count)
            IconButton(title: "Later Brief", icon: "chevron.right") { brief.selectedID = brief.files[index - 1].id }
                .disabled(index == 0)
        }
        .padding(.horizontal, AppDefaults.ArticleReader.horizontalInset)
        .frame(height: AppDefaults.ArticleReader.addressHeight)
    }

    /// A date such as "October 30, 2026", from the file name of a brief.
    static func dateLine(of id: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: id)?.formatted(date: .long, time: .omitted) ?? id
    }

    @ViewBuilder private var status: some View {
        switch brief.state {
        case .idle:
            if brief.asksAboutMorning { morningQuestion }
        case .scanning: progress("Reading history and feeds…")
        case .choosing: progress("Choosing sites…")
        case .reading(let hosts): progress("Reading \(hosts.joined(separator: ", "))…")
        case .writing: progress("Writing the brief…")
        case .failed(let message):
            statusRow {
                Text("Today's brief was not built. \(message)")
                    .font(PiperTheme.ui(12))
                    .foregroundStyle(PiperTheme.danger)
                    .lineLimit(3)
                Spacer(minLength: 8)
                Button("Try Again") { brief.build() }.buttonStyle(.text)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        statusRow {
            ProgressView().controlSize(.small)
            Text(text).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var morningQuestion: some View {
        statusRow {
            Text("Build a brief each morning while Piper is open?")
                .font(PiperTheme.ui(12))
                .foregroundStyle(PiperTheme.secondary)
            Spacer(minLength: 8)
            Button("Not Now") { brief.answerMorning(false) }.buttonStyle(.text)
            Button("Build Each Morning") { brief.answerMorning(true) }.buttonStyle(.text)
        }
    }

    private func statusRow(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Rule()
        }
    }
}

/// The sites that the next build uses, with the controls that limit them.
struct BriefSitesView: View {
    let brief: BriefBuilder

    @State private var digest: HistoryDigest?
    @State private var signInHost: SignInHost?

    private struct SignInHost: Identifiable {
        let id: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("What Claude receives").font(PiperTheme.ui(15, weight: .semibold))
                        Text(subtitle).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Build Brief") { brief.build() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.defaultAction)
                        .disabled(brief.state.isBuilding || digest == nil)
                }
                .padding(.bottom, 28)

                Text("SITES")
                    .font(PiperTheme.ui(11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PiperTheme.secondary)
                    .padding(.bottom, 4)
                ForEach(digest?.sites ?? []) { site in
                    row(site)
                    Rule()
                }
                if digest?.sites.isEmpty == true {
                    Text("Piper found no history to use.")
                        .font(PiperTheme.ui(12))
                        .foregroundStyle(PiperTheme.faint)
                        .padding(.vertical, 8)
                }
                Text("Claude also receives the text of up to 8 of these sites, recent NetNewsWire articles, and the popular Hacker News submissions of the last day. Pages load with the sign-ins that you add in Piper.")
                    .font(PiperTheme.ui(11))
                    .foregroundStyle(PiperTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            .frame(maxWidth: AppDefaults.Reader.columnWidth, alignment: .leading)
            .padding(.horizontal, AppDefaults.Reader.horizontalInset)
            .padding(.top, AppDefaults.Reader.headerTopInset)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: reload)
        .sheet(item: $signInHost) { BriefSignInSheet(host: $0.id) }
    }

    private func row(_ site: DigestSite) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.host).font(PiperTheme.ui(13, weight: .semibold)).lineLimit(1)
                Text("\(site.visits) visits · \(site.sampleTitles.joined(separator: ", "))")
                    .font(PiperTheme.ui(11))
                    .foregroundStyle(PiperTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Sign In") { signInHost = SignInHost(id: site.host) }.buttonStyle(.text)
            Button("Never Send") {
                brief.block(site.host)
                reload()
            }
            .buttonStyle(.text)
        }
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        guard let digest else { return "Reading your history…" }
        return "Top \(digest.sites.count) of \(digest.totalSites) sites in the last \(HistoryDigest.days) days"
    }

    private func reload() {
        Task { digest = await brief.preview() }
    }
}

/// Shows one brief in the reader page, with the highlights and the notes of the
/// brief. The text cannot change.
private struct BriefReader: View {
    let model: AppModel
    let file: BriefFile
    let text: String

    @State private var places = NotePlaces()
    @State private var scroll: ReaderScroll?

    private static let source = "Brief"

    init(model: AppModel, file: BriefFile, text: String) {
        self.model = model
        self.file = file
        self.text = text
        let block = model.brief.readingBlocks[file.id] ?? 0
        _scroll = State(initialValue: block > 0 ? ReaderScroll(block: block, in: UUID()) : nil)
    }

    private var link: String { "piper-brief://" + file.id }
    private var title: String { "Brief for " + (BriefPage.dateLine(of: file.id) ?? file.id) }

    private var article: ReaderArticle {
        let blocks = BriefDocument.blocks(in: text).map { block in
            ReaderArticle.Block(kind: block.kind, text: block.text, links: block.links.map {
                ReaderArticle.Block.Link(offset: $0.offset, length: $0.length, url: $0.url)
            })
        }
        return ReaderArticle(url: URL(string: link) ?? file.url, site: Self.source, title: title, author: "", blocks: blocks)
    }

    /// The note that holds the highlights. It does not exist before the first highlight.
    private var parent: UUID? {
        model.store.notes.first { $0.parent == nil && $0.sourceURLs.contains(link) }?.id
    }

    var body: some View {
        let article = article
        ReaderPageView(state: .loaded(article), placeholder: ReaderPlaceholder(site: Self.source, title: title),
                       notes: parent.map { ReaderMarks.payload(model: model, parent: $0, article: article, places: places) } ?? [],
                       scroll: scroll, perform: { perform($0, article: article) }, scrolled: { _ in })
    }

    private func perform(_ message: [String: Any], article: ReaderArticle) {
        switch message["action"] as? String {
        case "link":
            guard let url = (message["url"] as? String).flatMap(URL.init(string:)),
                  let note = model.store.saveArticle(url, source: Self.source) else { return }
            model.articleTab = .web
            model.showNote?(note.id)
        case "position":
            if let block = message["block"] as? Int { model.brief.readingBlocks[file.id] = block }
        default:
            ReaderMarks.perform(message, model: model, article: article) {
                model.store.pageNote(for: link, title: title, source: Self.source)?.id
            }
        }
    }
}
