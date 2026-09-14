//
//  WebKitDOMTests.swift
//  WebKitDOMTests
//
//  Created by Neon.
//

import Testing
import Foundation
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

    @Test func attachesImagesToFileInput() async throws {
        let (webView, session) = try await makeSession(html: """
            <input id="photos" type="file" accept="image/*" multiple>
            <output id="events"></output>
            <script>
              document.querySelector('#photos').addEventListener('change', event => {
                document.querySelector('#events').textContent = Array.from(event.target.files).map(file => file.name).join(',');
              });
            </script>
            """)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII="))
        let image = DOMImage(data: png, fileName: "room.png", mimeType: "image/png")
        let secondImage = DOMImage(data: png, fileName: "kitchen.png", mimeType: "image/png")
        try await session.attachImages([image, secondImage], to: "#photos")
        #expect(try await webView.evaluateJavaScript("document.querySelector('#photos').files[0].name") as? String == "room.png")
        #expect(try await webView.evaluateJavaScript("document.querySelector('#photos').files.length") as? Int == 2)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#photos').files[0].size") as? Int == png.count)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#events').textContent") as? String == "room.png,kitchen.png")
        let copiedBytes = try await webView.callAsyncJavaScript(
            "return Array.from(new Uint8Array(await document.querySelector('#photos').files[0].arrayBuffer())).join(',')",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
        #expect(copiedBytes == png.map(String.init).joined(separator: ","))
    }

    @Test func rejectsMultipleImagesForSingleFileInput() async throws {
        let (_, session) = try await makeSession(html: "<input id='photo' type='file'>")
        let image = DOMImage(data: Data([1]), fileName: "room.png", mimeType: "image/png")
        await #expect(throws: DOMError.invalidValue("File input does not allow multiple files")) {
            try await session.attachImages([image, image], to: "#photo")
        }
    }

    @Test func clicksExactTextOnlyInsideContainer() async throws {
        let (webView, session) = try await makeSession(html: """
            <section id="outside"><button onclick="document.body.dataset.clicked='outside'">원룸</button></section>
            <section id="listing">
              <button onclick="document.body.dataset.clicked='inside'">원룸</button>
              <button onclick="document.body.dataset.clicked='wrong'">분리형 원룸</button>
            </section>
            """)
        try await session.clickElement(matchingText: "원룸", in: "#listing")
        #expect(try await webView.evaluateJavaScript("document.body.dataset.clicked") as? String == "inside")
    }

    @Test func supportsCustomTargetSelectorAndTrimsOuterWhitespace() async throws {
        let (webView, session) = try await makeSession(html: """
            <section id="options">
              <div role="option" onclick="document.body.dataset.selected='south'"> 남향 </div>
              <div role="option" onclick="document.body.dataset.selected='south-east'">남동향</div>
            </section>
            """)
        try await session.clickElement(
            matchingText: "남향",
            in: "#options",
            elementSelector: "[role=option]"
        )
        #expect(try await webView.evaluateJavaScript("document.body.dataset.selected") as? String == "south")
    }

    @Test func clicksDynamicallyCreatedSeedStyleOption() async throws {
        let (webView, session) = try await makeSession(html: """
            <div class="seed-field" id="sales-type">
              <button name="salesType"></button>
            </div>
            <script>
              document.querySelector('[name=salesType]').addEventListener('click', () => {
                setTimeout(() => {
                  const option = document.createElement('button');
                  option.textContent = '오픈형 원룸';
                  option.addEventListener('click', () => document.body.dataset.selected = 'studio');
                  document.querySelector('#sales-type').append(option);
                }, 50);
              });
            </script>
            """)
        try await session.click("button[name=salesType]")
        try await session.clickElement(matchingText: "오픈형 원룸", in: "#sales-type", timeout: 2)
        #expect(try await webView.evaluateJavaScript("document.body.dataset.selected") as? String == "studio")
    }

    @Test func reportsScopedTextClickErrors() async throws {
        let (_, session) = try await makeSession(html: """
            <section class="group"><button>주택</button><button>주택</button></section>
            <section class="group"><button>아파트</button></section>
            """)
        await #expect(throws: DOMError.invalidSelector("[")) {
            try await session.clickElement(matchingText: "주택", in: "[")
        }
        await #expect(throws: DOMError.invalidSelector("[")) {
            try await session.clickElement(matchingText: "주택", in: ".group:first-child", elementSelector: "[")
        }
        await #expect(throws: DOMError.elementNotFound("#missing")) {
            try await session.clickElement(matchingText: "주택", in: "#missing")
        }
        await #expect(throws: DOMError.ambiguousSelector(".group")) {
            try await session.clickElement(matchingText: "주택", in: ".group")
        }
        await #expect(throws: DOMError.ambiguousSelector("주택")) {
            try await session.clickElement(matchingText: "주택", in: ".group:first-child")
        }
        await #expect(throws: DOMError.timedOut("빌라")) {
            try await session.clickElement(matchingText: "빌라", in: ".group:first-child", timeout: 0.05)
        }
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
