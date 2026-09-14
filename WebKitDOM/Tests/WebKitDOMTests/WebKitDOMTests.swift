//
//  WebKitDOMTests.swift
//  WebKitDOMTests
//
//  Created by Neon.
//

import Testing
import WebKit
@testable import WebKitDOM

@MainActor
struct WebKitDOMTests {
    @Test func fillsFieldsAndDispatchesEvents() async throws {
        let (webView, session) = try await makeSession(html: """
            <input id="title"><textarea id="description"></textarea>
            <output id="events"></output>
            <script>
              let count = 0;
              for (const id of ['title', 'description']) {
                for (const event of ['input', 'change']) {
                  document.getElementById(id).addEventListener(event, () => {
                    document.getElementById('events').textContent = String(++count);
                  });
                }
              }
            </script>
            """)
        try await session.fill("#title", with: "새 매물")
        try await session.fill("#description", with: "방 2개")
        #expect(try await session.value(of: "#title") == "새 매물")
        #expect(try await session.matchesValue("방 2개", at: "#description"))
        #expect(try await webView.evaluateJavaScript("document.querySelector('#events').textContent") as? String == "4")
    }

    @Test func selectsChecksAndClicks() async throws {
        let (webView, session) = try await makeSession(html: """
            <select id="type"><option value="apartment">아파트</option><option value="house">주택</option></select>
            <input id="parking" type="checkbox">
            <button id="next" onclick="document.body.dataset.clicked = 'yes'">다음</button>
            """)
        try await session.select("#type", value: "house")
        try await session.setChecked("#parking", to: true)
        try await session.click("#next")
        #expect(try await session.value(of: "#type") == "house")
        #expect(try await webView.evaluateJavaScript("document.querySelector('#parking').checked") as? Bool == true)
        #expect(try await webView.evaluateJavaScript("document.body.dataset.clicked") as? String == "yes")
        try await session.setChecked("#parking", to: false)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#parking').checked") as? Bool == false)
    }

    @Test func waitsForDynamicallyInsertedElement() async throws {
        let (webView, session) = try await makeSession(html: "<main></main>")
        let waiter = Task { try await session.waitForElement("#late", timeout: 2) }
        try await Task.sleep(nanoseconds: 100_000_000)
        _ = try await webView.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend', '<input id=\"late\">')")
        try await waiter.value
        try await session.fill("#late", with: "ready")
        #expect(try await session.value(of: "#late") == "ready")
    }

    @Test func reportsSelectorAndValueErrors() async throws {
        let (_, session) = try await makeSession(html: """
            <input class="duplicate"><input class="duplicate">
            <select id="type"><option value="house">주택</option></select>
            """)
        await #expect(throws: DOMError.invalidSelector("[")) { try await session.click("[") }
        await #expect(throws: DOMError.elementNotFound("#missing")) { try await session.click("#missing") }
        await #expect(throws: DOMError.ambiguousSelector(".duplicate")) { try await session.fill(".duplicate", with: "x") }
        await #expect(throws: DOMError.unsupportedElement("#type")) { try await session.fill("#type", with: "x") }
        await #expect(throws: DOMError.invalidValue("other")) { try await session.select("#type", value: "other") }
        await #expect(throws: DOMError.timedOut("#missing")) { try await session.waitForElement("#missing", timeout: 0.05) }
    }

    private func makeSession(html: String) async throws -> (WKWebView, DOMSession) {
        let webView = WKWebView()
        let loader = PageLoader()
        webView.navigationDelegate = loader
        try await loader.load(html, in: webView)
        return (webView, DOMSession(webView: webView))
    }
}

@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
