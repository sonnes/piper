import SwiftUI
import WebKit

/// A web page where the user signs in to a site. It uses the data store of the
/// Web tab and of the brief, so the sign-in stays. Browser sign-ins do not apply.
struct BriefSignInSheet: View {
    let host: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to \(host)").font(PiperTheme.ui(13, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.text).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Rule()
            SignInWebView(url: URL(string: "https://\(host)/"))
        }
        .foregroundStyle(PiperTheme.ink)
        .background(PiperTheme.page)
        .frame(width: AppDefaults.Brief.signInSize.width, height: AppDefaults.Brief.signInSize.height)
    }
}

private struct SignInWebView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        if let url { view.load(URLRequest(url: url)) }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}
}
