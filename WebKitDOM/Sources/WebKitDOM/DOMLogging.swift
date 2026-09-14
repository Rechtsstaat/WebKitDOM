//
//  DOMLogging.swift
//  WebKitDOM
//
//  Created by Neon.
//

import Foundation
import OSLog

public enum DOMLogLevel: Int, Sendable {
    case debug = 0
    case error = 1
}

public enum DOMLogPhase: String, Sendable {
    case started
    case succeeded
    case failed
}

public enum DOMLogOperation: String, CaseIterable, Sendable {
    case waitForElement
    case fill
    case select
    case setChecked
    case click
    case clickElement
    case attachImages
    case value
    case matchesValue
}

/// Metadata only. Form values, image bytes, cookies, and page URLs are never included.
public struct DOMLogEvent: Sendable {
    public let id: UUID
    public let operation: DOMLogOperation
    public let phase: DOMLogPhase
    public let level: DOMLogLevel
    public let selector: String?
    public let durationMilliseconds: Int?
    public let errorCode: String?
}

/// A destination supplied by the host app. Called on the main actor with WKWebView operations.
@MainActor
public protocol DOMEventLogger {
    func log(_ event: DOMLogEvent)
}

/// Unified logging destination with a package-owned subsystem and DOM category.
@MainActor
public struct UnifiedDOMLogger: DOMEventLogger {
    private let logger = Logger(subsystem: "WebKitDOM", category: "DOM")

    public init() {}

    public func log(_ event: DOMLogEvent) {
        let duration = event.durationMilliseconds.map(String.init) ?? "-"
        let code = event.errorCode ?? "-"
        let selector = event.selector ?? "-"
        let message = "[WebKitDOM] id=\(event.id) operation=\(event.operation.rawValue) phase=\(event.phase.rawValue) durationMs=\(duration) errorCode=\(code) selector=\(selector)"
        switch event.level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }
}
