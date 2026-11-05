import Briefs
import SwiftUI

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
                        Text("What Claude receives").font(PiperTheme.ui(.reading, weight: .semibold))
                        Text(subtitle).font(PiperTheme.ui(.secondary)).foregroundStyle(PiperTheme.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Build Brief") { brief.build() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(brief.state.isBuilding || digest == nil)
                }
                .padding(.bottom, 28)

                Text("SITES")
                    .font(PiperTheme.ui(.caption, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(PiperTheme.secondary)
                    .padding(.bottom, 4)
                ForEach(digest?.sites ?? []) { site in
                    row(site)
                    Rule()
                }
                if digest?.sites.isEmpty == true {
                    Text("Piper found no history to use.")
                        .font(PiperTheme.ui(.secondary))
                        .foregroundStyle(PiperTheme.faint)
                        .padding(.vertical, 8)
                }
                Text("Claude also receives the link titles of up to 8 of these sites, recent NetNewsWire articles, and the popular Hacker News submissions of the last day. Pages load with the sign-ins that you add in Piper.")
                    .font(PiperTheme.ui(.caption))
                    .foregroundStyle(PiperTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            .padding(24)
        }
        .onAppear(perform: reload)
        .sheet(item: $signInHost) { BriefSignInSheet(host: $0.id) }
    }

    private func row(_ site: DigestSite) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.host).font(PiperTheme.ui(.body, weight: .semibold)).lineLimit(1)
                Text("\(site.visits) visits · \(site.sampleTitles.joined(separator: ", "))")
                    .font(PiperTheme.ui(.caption))
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
