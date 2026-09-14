# WebKitDOM

Control and verify DOM elements in an existing `WKWebView` from Swift. Fill a form, choose a native option, click a dynamically rendered button, or attach images without building a new web-view wrapper.

WebKitDOM is a low-level Swift Package, not a site automation service. Your app owns navigation, authentication, the `WKWebView`, and the decision to submit a form.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Common operations](#common-operations)
- [SwiftUI integration](#swiftui-integration)
- [Diagnostics](#diagnostics)
- [Errors and verification](#errors-and-verification)
- [What it does not do](#what-it-does-not-do)
- [Tests](#tests)

## Requirements

- iOS 15+ or macOS 12+
- Swift 6 and WebKit
- An existing `WKWebView` with a loaded main document you can interact with

The SwiftUI Observation example below requires iOS 17+, but the package API does not.

## Installation

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/Rechtsstaat/WebKitDOM.git`, select version **0.1.0 or later**, and add the `WebKitDOM` product to your app target. Then `import WebKitDOM`.

For a Swift package that consumes WebKitDOM:

```swift
dependencies: [
    .package(url: "https://github.com/Rechtsstaat/WebKitDOM.git", from: "0.1.0")
],
targets: [
    .target(name: "YourAppModule", dependencies: ["WebKitDOM"])
]
```

For local development, clone this repository and choose **File → Add Package Dependencies → Add Local** in Xcode. Select the **repository root** containing `Package.swift`, not the inner source directory. You can also use `.package(path: "/path/to/WebKitDOM")` from another local Swift package.

## Quick start

Load this small form in your app's `WKWebView` (or use a page with equivalent selectors):

```html
<input id="title" type="text">
<select id="direction">
  <option value="N">North</option>
  <option value="S">South</option>
</select>
<input id="parking" type="checkbox">
<button id="next" type="button">Next</button>
```

After the page finishes loading, create a session from **that same web view**:

```swift
import WebKit
import WebKitDOM

let dom = DOMSession(webView: webView)
try await dom.waitForElement("#title")
try await dom.fill("#title", with: "Example title")
try await dom.select("#direction", value: "S")
try await dom.setChecked("#parking", to: true)

let title = try await dom.value(of: "#title")
assert(title == "Example title")
try await dom.click("#next")
```

Call the `@MainActor` API from a main-actor context, such as a SwiftUI action or an `@MainActor` model. A DOM value match confirms the page value, not that a site's framework or server accepted it.

## Common operations

| API | Use it for | Important limit |
| --- | --- | --- |
| `waitForElement(_:timeout:)` | Wait for a selector to appear | Waits for at least one match |
| `fill(_:with:)` | Text inputs and textareas | Not file, checkbox, radio, or hidden inputs |
| `select(_:value:)` | Native `<select>` | Does not operate a custom dropdown |
| `setChecked(_:to:)` | Native checkbox and radio | A radio cannot be directly unchecked |
| `click(_:)` | One element by CSS selector | May trigger navigation or submission |
| `clickElement(matchingText:in:elementSelector:timeout:)` | A text-labeled option inside one container | Defaults to buttons; trims outer whitespace |
| `attachImages(_:to:)` | Native `<input type="file">` | DOM attachment is not server upload |
| `value(of:)`, `matchesValue(_:at:)` | Read and compare a DOM value | Framework state may differ |

### Dynamic dropdown example

For a custom dropdown, click its trigger first. The option must be found in the **container where the site renders it**; a portal may be outside the trigger's parent.

```swift
try await dom.click("#menu-trigger")
try await dom.clickElement(
    matchingText: "Option B",
    in: "#menu-options",
    elementSelector: "[role=option]",
    timeout: 5
)
```

The selectors above are illustrative. If two matching options exist in the container, the call throws instead of guessing. Verify the page's selected state after clicking.

### Image input example

```swift
let photo = DOMImage(data: jpegData, fileName: "sample.jpg", mimeType: "image/jpeg")
try await dom.attachImages([photo], to: "input[type=file][name=photos]")
```

For multiple images, pass multiple `DOMImage` values and target an input with the `multiple` attribute. WebKitDOM creates browser `File` objects, dispatches `input` and `change`, and checks their names, MIME types, and sizes. Your app must provide image bytes, for example from PhotosPicker. Sites may impose additional format, file-size, count, or user-gesture requirements.

## Diagnostics

By default, `DOMSession` writes failures to Unified Logging with subsystem `WebKitDOM` and category `DOM`. Set `minimumLogLevel: .debug` to see the start and success of each operation too. Each event includes an operation name, phase, correlation ID, elapsed milliseconds after completion, and an error code on failure. The thrown `DOMError` is unchanged.

```swift
let dom = DOMSession(webView: webView, minimumLogLevel: .debug)
// Filter Console.app or Xcode logs by subsystem "WebKitDOM".
```

An app can receive the same structured events through `DOMEventLogger`, or pass `logger: nil` to disable logging:

```swift
@MainActor
final class AppDOMLogger: DOMEventLogger {
    func log(_ event: DOMLogEvent) {
        // Forward to the app's logging or diagnostics system.
        print("\(event.id) \(event.operation.rawValue) \(event.phase.rawValue)")
    }
}

let dom = DOMSession(
    webView: webView,
    logger: AppDOMLogger(),
    minimumLogLevel: .debug
)
```

Selectors are omitted by default because a CSS selector can contain private data. Only set `includeSelectorsInLogs: true` after reviewing the selectors used by your app. Form values, image bytes, cookie contents, page URLs, and raw JavaScript error descriptions are never included in `DOMLogEvent`. Debug logging may be more verbose, so leave the default `.error` level in release builds unless diagnostics require otherwise.

## SwiftUI integration

Keep the same `WKWebView` instance while presenting and dismissing its SwiftUI wrapper. Create the session from that instance after the page has loaded. This example uses Observation and therefore requires iOS 17 or later; the package itself supports iOS 15 or later:

```swift
import SwiftUI
import Observation
import WebKit
import WebKitDOM

@MainActor
@Observable
final class FormBrowser {
    let webView = WKWebView()

    func fillForm() async throws {
        let dom = DOMSession(webView: webView)
        try await dom.waitForElement("input[name=title]")
        try await dom.fill("input[name=title]", with: "Example title")
        try await dom.fill("textarea[name=description]", with: "Example description")
        // Leave final submission to the user or explicit app-level workflow.
    }

    func attachImage(_ data: Data) async throws {
        let dom = DOMSession(webView: webView)
        try await dom.waitForElement("input[type=file][name=photos]")
        try await dom.attachImages(
            [DOMImage(data: data, fileName: "sample.jpg", mimeType: "image/jpeg")],
            to: "input[type=file][name=photos]"
        )
    }
}

struct FormPage: UIViewRepresentable {
    let browser: FormBrowser

    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
```

Use `WKWebsiteDataStore.default()` (the default for `WKWebView`) when you want normal persistent website data; a nonpersistent data store will not retain cookies across sessions. Keeping the same web view also preserves the currently loaded page when SwiftUI redraws the wrapper. Login persistence across app launches still depends on each site's cookie lifetime and login policy.

`FormPage` only displays the supplied web view. Load the target URL or HTML and observe navigation in the host app before calling `fillForm()`. The selectors above are examples; adapt them to the page you load.

## Errors and verification

- Invalid, missing, and non-unique CSS selectors have distinct `DOMError` cases.
- `fill` supports text inputs and textareas, `select` supports native `<select>`, and `setChecked` supports checkboxes and radio buttons.
- Input operations dispatch bubbling `input` and `change` events, then read back the DOM value. `waitForElement` uses `MutationObserver` and throws `timedOut` when necessary.
- `attachImages` creates browser `File` objects from image bytes, assigns them to a native `<input type="file">`, dispatches `input`/`change`, and checks file metadata. The caller supplies the image bytes, for example from PhotosPicker. More than one image requires a `multiple` file input.
- A JavaScript or navigation failure becomes `executionFailed`. The app should wait for the correct page before invoking the session and re-check after navigation.

Handle expected failures explicitly in the host app:

```swift
do {
    try await dom.fill("#title", with: "Example title")
} catch DOMError.elementNotFound(let selector) {
    // The page may not be ready, or the site's markup may have changed.
    print("Missing element: \(selector)")
} catch DOMError.ambiguousSelector(let selector) {
    // Narrow the CSS selector before retrying.
    print("More than one element: \(selector)")
} catch {
    // Preserve the error for the app's own diagnostics or UI.
    print(error)
}
```

`fill`, `select`, and `attachImages` read back the immediate DOM result. They cannot prove that a framework state update, validation rule, preview, network request, or server save succeeded. Check an application-specific confirmation signal before treating an operation as complete. If a page reformats a value (for example `6545` into `6,545`), compare a normalized value in the host app rather than relying on `matchesValue`'s exact string comparison.

## What it does not do

- Create or navigate a `WKWebView`, sign in, or manage cookies for the host app.
- Target iframe DOM (including same-origin frames) or control a separate popup window; operations currently run in the main document only.
- Know a website's selectors, field dependencies, value mapping, or validation rules.
- Guarantee that a programmatically attached file is uploaded or accepted by the server.
- Submit a form unless the host app explicitly calls `click` on a submit control.

Some sites require a genuine user-initiated file selection, reject untrusted events, or use custom upload components. Those flows require a site-specific approach rather than an assumption that DOM attachment is enough.

## Tests

The same Swift Testing suite loads a real `WKWebView` on macOS and iOS. It covers text/event dispatch, select, checkbox, click, scoped text click, dynamically created options, image file inputs, dynamic elements, and error cases.

```sh
swift test
xcodebuild test -scheme WebKitDOM -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The iOS Simulator run passed all 14 tests on an iPhone 17 simulator with iOS 26.5 (2026-09-14). The tests include logger correlation, failure codes, privacy defaults, opt-in selectors, and disabled logging. This does not establish behavior on iOS 15, physical devices, or production websites; those require separate testing. The macOS test run requires an environment that permits WebKit's web content process.
