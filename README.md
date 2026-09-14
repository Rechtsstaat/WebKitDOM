# WebKitDOM
A Swift package for interacting with and verifying DOM elements in WKWebView.

WebKitDOM works with a `WKWebView` your app already owns. It does not create a web view, navigate to a site, or store login credentials. The app remains responsible for the web view's `WKWebsiteDataStore` and cookie policy.

## Public API

`DOMSession` wraps an existing `WKWebView`. The app owns the web view and its navigation; the package handles small, verifiable DOM operations.

```swift
let session = DOMSession(webView: webView)
try await session.waitForElement("input[name=title]")
try await session.fill("input[name=title]", with: "Sunny studio")
try await session.select("select[name=direction]", value: "SOUTH")
try await session.setChecked("input[name=parking]", to: true)
try await session.attachImages(
    [DOMImage(data: photoData, fileName: "room.jpg", mimeType: "image/jpeg")],
    to: "input[type=file][name=photos]"
)
try await session.click("button[name=next]")
try await session.clickElement(
    matchingText: "오픈형 원룸",
    in: "#sales-type-field"
)

let title = try await session.value(of: "input[name=title]")
let matches = try await session.matchesValue("Sunny studio", at: "input[name=title]")
```

The operations are `async`, main-actor isolated, and throw `DOMError` on failure. Selectors must match exactly one element. `waitForElement` waits for at least one match without a fixed sleep. `fill`, `select`, and `setChecked` verify the resulting DOM state.

`clickElement(matchingText:in:elementSelector:timeout:)` finds exactly one container, then clicks an element inside it whose `textContent` matches after trimming surrounding whitespace. It defaults to `button` elements; pass another CSS `elementSelector` for a different control. If the target has not appeared, it observes that container until it appears or the timeout expires. Missing or duplicate containers, duplicate matching targets, invalid selectors, and timeouts produce distinct `DOMError` cases. For Seed-style dropdowns, click the trigger first, then call this method on the field container. A click does not by itself prove that the site's framework accepted the selection; inspect a site-specific state change afterward.

### SwiftUI example

Keep the same `WKWebView` instance while presenting and dismissing its SwiftUI wrapper. Create the session from that instance after the page has loaded. This example uses Observation and therefore requires iOS 17 or later; the package itself supports iOS 15 or later:

```swift
import SwiftUI
import Observation
import WebKit
import WebKitDOM

@MainActor
@Observable
final class ListingBrowser {
    let webView = WKWebView()

    func fillListing() async throws {
        let dom = DOMSession(webView: webView)
        try await dom.waitForElement("input[name=title]")
        try await dom.fill("input[name=title]", with: "Sunny studio")
        try await dom.fill("textarea[name=description]", with: "Near transit")
        // Leave final submission to the user or explicit app-level workflow.
    }

    func attachPhoto(_ data: Data) async throws {
        let dom = DOMSession(webView: webView)
        try await dom.waitForElement("input[type=file][name=photos]")
        try await dom.attachImages(
            [DOMImage(data: data, fileName: "room.jpg", mimeType: "image/jpeg")],
            to: "input[type=file][name=photos]"
        )
    }
}

struct ListingPage: UIViewRepresentable {
    let browser: ListingBrowser

    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
```

Use `WKWebsiteDataStore.default()` (the default for `WKWebView`) when you want normal persistent website data; a nonpersistent data store will not retain cookies across sessions. Keeping the same web view also preserves the currently loaded page when SwiftUI redraws the wrapper. Login persistence across app launches still depends on each site's cookie lifetime and login policy.

### Error and verification behavior

- Invalid, missing, and non-unique CSS selectors have distinct `DOMError` cases.
- `fill` supports text inputs and textareas, `select` supports native `<select>`, and `setChecked` supports checkboxes and radio buttons.
- Input operations dispatch bubbling `input` and `change` events, then read back the DOM value. `waitForElement` uses `MutationObserver` and throws `timedOut` when necessary.
- `attachImages` creates browser `File` objects from image bytes, assigns them to a native `<input type="file">`, dispatches `input`/`change`, and checks file metadata. The caller supplies the image bytes, for example from PhotosPicker. More than one image requires a `multiple` file input.
- A JavaScript or navigation failure becomes `executionFailed`. The app should wait for the correct page before invoking the session and re-check after navigation.

The package does not navigate particular sites, know their dropdown structure, access cross-origin iframe DOM, or submit forms. It attaches images to native file inputs but does not guarantee upload to a server. Some sites require a genuine user-initiated file selection, reject untrusted events, or use custom upload components; those flows need site-specific handling. Site-specific selectors, conditional input order, and value mapping belong in an app-level adapter. A DOM value match does not by itself prove that a site's framework or server accepted a change.

## Tests

The same Swift Testing suite loads a real `WKWebView` on macOS and iOS. It covers text/event dispatch, select, checkbox, click, scoped text click, Seed-style dynamically created options, image file inputs, dynamic elements, and error cases.

```sh
cd WebKitDOM
swift test
xcodebuild test -scheme WebKitDOM -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The iOS Simulator run passed all 10 tests on an iPhone 17 simulator with iOS 26.5 (2026-09-14). This does not establish behavior on iOS 15, physical devices, or live real-estate sites; those require separate testing. The macOS test run requires an environment that permits WebKit's web content process.

## Requirements

- iOS 15 or later, macOS 12 or later
- Swift 6
