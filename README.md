# WebKitDOM
A Swift package for interacting with and verifying DOM elements in WKWebView.

## Public API

`DOMSession` wraps an existing `WKWebView`. The app owns the web view and its navigation; the package handles small, verifiable DOM operations.

```swift
let session = DOMSession(webView: webView)
try await session.waitForElement("input[name=title]")
try await session.fill("input[name=title]", with: "Sunny studio")
try await session.select("select[name=direction]", value: "SOUTH")
try await session.setChecked("input[name=parking]", to: true)
try await session.click("button[name=next]")

let title = try await session.value(of: "input[name=title]")
let matches = try await session.matchesValue("Sunny studio", at: "input[name=title]")
```

The operations are `async`, main-actor isolated, and throw `DOMError` on failure. Selectors must match exactly one element. `waitForElement` waits for at least one match without a fixed sleep. `fill`, `select`, and `setChecked` verify the resulting DOM state.

The package does not navigate particular sites, automate custom Radix-style dropdowns, access cross-origin iframe DOM, upload files, or submit forms. Site-specific selectors, conditional input order, and value mapping belong in an app-level adapter. A DOM value match does not by itself prove that a site's framework or server accepted a change.

## Requirements

- iOS 15 or later, macOS 12 or later
- Swift 6
