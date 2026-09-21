#if os(macOS)
import WebKit

/// WebKit is used only as an offline HTML parser. Widget controls remain AppKit.
@MainActor
final class NativePageExtractor: NSObject, WKNavigationDelegate {
    private static var rules: WKContentRuleList?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<CustomWidgetInput, Error>?
    private var timeout: Task<Void, Never>?
    private var html = ""
    private var selector = ""
    private var attribute = ""

    func extract(html: String, selector: String, attribute: String) async throws -> CustomWidgetInput {
        if Self.rules == nil {
            Self.rules = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "OpenDocOfflineHTML", encodedContentRuleList: "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block\"}}]")
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let rules = Self.rules { configuration.userContentController.add(rules) }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView; webView.navigationDelegate = self
        self.html = html; self.selector = selector; self.attribute = attribute
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(CustomWidgetError.message("HTML parsing timed out.")))
            }
            webView.loadHTMLString("<!doctype html><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'\"><title>Open Doc parser</title>", baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const nodes = Array.from(doc.querySelectorAll(selector)).slice(0, 20);
        if (!nodes.length) throw new Error('No elements match this CSS selector. This reads the returned HTML, not content loaded later by page scripts.');
        const matches = nodes.map(node => {
            if (attribute && !node.hasAttribute(attribute)) throw new Error('The selected element has no ' + attribute + ' attribute.');
            return (attribute ? node.getAttribute(attribute) : node.textContent).replace(/\\s+/g, ' ').trim().slice(0, 512);
        });
        return {text: matches[0], matches};
        """
        webView.callAsyncJavaScript(script, arguments: ["html": html, "selector": selector, "attribute": attribute], in: nil, in: .defaultClient) { [weak self] result in
            switch result {
            case .success(let value):
                guard let object = value as? [String: Any], let text = object["text"] as? String,
                      let matches = object["matches"] as? [String] else {
                    self?.finish(.failure(CustomWidgetError.message("The page returned an invalid value."))); return
                }
                self?.finish(.success(CustomWidgetInput(text: text, matches: matches)))
            case .failure(let error): self?.finish(.failure(error))
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(CustomWidgetError.message("The HTML parser stopped. Try refreshing."))) }
    private func finish(_ result: Result<CustomWidgetInput, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        webView?.navigationDelegate = nil; webView?.stopLoading(); webView = nil
        continuation.resume(with: result)
    }
}
#endif
