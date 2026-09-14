# WebKitDOM 0.1.0

Initial public release of WebKitDOM, a Swift Package for interacting with DOM elements in an existing `WKWebView`.

- Fill text fields, select native options, update checkboxes and radio buttons, and click elements.
- Find a text-matching element inside a specific container, including dynamically rendered options.
- Attach image data to native file inputs and read back DOM values for verification.
- Observe operation diagnostics with privacy-conscious logging and structured errors.
- Supports iOS 15+ and macOS 12+. Requires Swift 6.3 or later.
- Distributed under the MIT License.

The host app remains responsible for navigation, authentication, page-specific selectors, upload confirmation, and final submission. Browser or server acceptance is not guaranteed by a successful DOM operation.
