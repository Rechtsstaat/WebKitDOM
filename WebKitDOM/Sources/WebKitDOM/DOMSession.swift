//
//  DOMSession.swift
//  WebKitDOM
//
//  Created by Neon.
//

import Foundation
import WebKit

public enum DOMError: Error, Equatable, Sendable {
    case invalidSelector(String)
    case elementNotFound(String)
    case ambiguousSelector(String)
    case unsupportedElement(String)
    case invalidValue(String)
    case verificationFailed(String)
    case timedOut(String)
    case executionFailed(String)
}

/// Performs small DOM operations in the page content world of an existing web view.
@MainActor
public final class DOMSession {
    private let webView: WKWebView
    private let logger: (any DOMEventLogger)?
    private let minimumLogLevel: DOMLogLevel
    private let includeSelectorsInLogs: Bool

    public init(
        webView: WKWebView,
        logger: (any DOMEventLogger)? = UnifiedDOMLogger(),
        minimumLogLevel: DOMLogLevel = .error,
        includeSelectorsInLogs: Bool = false
    ) {
        self.webView = webView
        self.logger = logger
        self.minimumLogLevel = minimumLogLevel
        self.includeSelectorsInLogs = includeSelectorsInLogs
    }

    public func waitForElement(_ selector: String, timeout: TimeInterval = 10) async throws {
        try await logged(.waitForElement, selector: selector) {
            let milliseconds = try validatedMilliseconds(for: timeout)
            _ = try await perform("wait", selector: selector, milliseconds: milliseconds)
        }
    }

    public func fill(_ selector: String, with value: String) async throws {
        try await logged(.fill, selector: selector) {
            _ = try await perform("fill", selector: selector, value: value)
        }
    }

    public func select(_ selector: String, value: String) async throws {
        try await logged(.select, selector: selector) {
            _ = try await perform("select", selector: selector, value: value)
        }
    }

    public func setChecked(_ selector: String, to checked: Bool) async throws {
        try await logged(.setChecked, selector: selector) {
            _ = try await perform("check", selector: selector, checked: checked)
        }
    }

    public func click(_ selector: String) async throws {
        try await logged(.click, selector: selector) {
            _ = try await perform("click", selector: selector)
        }
    }

    /// Clicks one element whose trimmed text exactly matches within one container.
    public func clickElement(
        matchingText text: String,
        in containerSelector: String,
        elementSelector: String = "button",
        timeout: TimeInterval = 10
    ) async throws {
        try await logged(.clickElement, selector: containerSelector) {
            guard !text.isEmpty else { throw DOMError.invalidValue("Target text must not be empty") }
            let milliseconds = try validatedMilliseconds(for: timeout)
            _ = try await perform(
                "clickText",
                selector: containerSelector,
                milliseconds: milliseconds,
                targetText: text,
                targetSelector: elementSelector
            )
        }
    }

    /// Replaces the files of a native file input and dispatches input/change events.
    public func attachImages(_ images: [DOMImage], to selector: String) async throws {
        try await logged(.attachImages, selector: selector) {
            guard !images.isEmpty,
                  images.allSatisfy({ !$0.data.isEmpty && !$0.fileName.isEmpty && !$0.fileName.contains("/") && !$0.fileName.contains("\\") && $0.mimeType.hasPrefix("image/") }) else {
                throw DOMError.invalidValue("Provide nonempty image data, a simple file name, and an image MIME type")
            }
            let payload = images.map { image in
                ["base64": image.data.base64EncodedString(), "fileName": image.fileName, "mimeType": image.mimeType]
            }
            _ = try await perform("attachImages", selector: selector, images: payload)
        }
    }

    public func value(of selector: String) async throws -> String {
        try await logged(.value, selector: selector) {
            try await perform("value", selector: selector)
        }
    }

    public func matchesValue(_ expected: String, at selector: String) async throws -> Bool {
        try await logged(.matchesValue, selector: selector) {
            try await perform("value", selector: selector) == expected
        }
    }

    private func logged<Result>(
        _ operation: DOMLogOperation,
        selector: String,
        perform body: () async throws -> Result
    ) async throws -> Result {
        let id = UUID()
        let startedAt = ProcessInfo.processInfo.systemUptime
        emit(id: id, operation: operation, phase: .started, level: .debug, selector: selector)
        do {
            let result = try await body()
            let duration = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            emit(id: id, operation: operation, phase: .succeeded, level: .debug, selector: selector, duration: duration)
            return result
        } catch {
            let duration = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            let code: String
            if let domError = error as? DOMError {
                code = Self.errorCode(for: domError)
            } else if error is CancellationError {
                code = "cancelled"
            } else {
                code = "unexpectedError"
            }
            emit(id: id, operation: operation, phase: .failed, level: .error, selector: selector, duration: duration, errorCode: code)
            throw error
        }
    }

    private func emit(
        id: UUID,
        operation: DOMLogOperation,
        phase: DOMLogPhase,
        level: DOMLogLevel,
        selector: String,
        duration: Int? = nil,
        errorCode: String? = nil
    ) {
        guard level.rawValue >= minimumLogLevel.rawValue else { return }
        logger?.log(DOMLogEvent(
            id: id,
            operation: operation,
            phase: phase,
            level: level,
            selector: includeSelectorsInLogs ? selector : nil,
            durationMilliseconds: duration,
            errorCode: errorCode
        ))
    }

    private static func errorCode(for error: DOMError) -> String {
        switch error {
        case .invalidSelector: "invalidSelector"
        case .elementNotFound: "elementNotFound"
        case .ambiguousSelector: "ambiguousSelector"
        case .unsupportedElement: "unsupportedElement"
        case .invalidValue: "invalidValue"
        case .verificationFailed: "verificationFailed"
        case .timedOut: "timedOut"
        case .executionFailed: "executionFailed"
        }
    }

    private func validatedMilliseconds(for timeout: TimeInterval) throws -> Int {
        guard timeout.isFinite, timeout >= 0, timeout <= Double(Int32.max) / 1_000 else {
            throw DOMError.invalidValue("Timeout must be between 0 and \(Double(Int32.max) / 1_000) seconds")
        }
        return Int(timeout * 1_000)
    }

    private func perform(
        _ operation: String,
        selector: String,
        value: String = "",
        checked: Bool = false,
        milliseconds: Int = 0,
        images: [[String: String]] = [],
        targetText: String = "",
        targetSelector: String = "button"
    ) async throws -> String {
        try Task.checkCancellation()
        let arguments: [String: Any] = [
            "operation": operation,
            "selector": selector,
            "value": value,
            "checked": checked,
            "milliseconds": milliseconds,
            "images": images,
            "targetText": targetText,
            "targetSelector": targetSelector
        ]

        let rawResult: Any?
        do {
            rawResult = try await webView.callAsyncJavaScript(
                Self.script,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DOMError.executionFailed(error.localizedDescription)
        }
        try Task.checkCancellation()

        guard let result = rawResult as? [String: Any],
              let success = result["ok"] as? Bool else {
            throw DOMError.executionFailed("Unexpected JavaScript response")
        }
        if !success {
            let message = result["message"] as? String ?? selector
            switch result["code"] as? String {
            case "invalidSelector": throw DOMError.invalidSelector(message)
            case "elementNotFound": throw DOMError.elementNotFound(message)
            case "ambiguousSelector": throw DOMError.ambiguousSelector(message)
            case "unsupportedElement": throw DOMError.unsupportedElement(message)
            case "invalidValue": throw DOMError.invalidValue(message)
            case "verificationFailed": throw DOMError.verificationFailed(message)
            case "timedOut": throw DOMError.timedOut(message)
            default: throw DOMError.executionFailed(message)
            }
        }
        return result["value"] as? String ?? ""
    }

    private static let script = #"""
    const fail = (code, message) => ({ ok: false, code, message });
    const find = () => {
      try { return document.querySelectorAll(selector); }
      catch (error) { return null; }
    };
    let elements = find();
    if (elements === null) return fail('invalidSelector', selector);

    if (operation === 'clickText') {
      if (elements.length === 0) return fail('elementNotFound', selector);
      if (elements.length !== 1) return fail('ambiguousSelector', selector);
      const container = elements[0];
      try { container.querySelectorAll(targetSelector); }
      catch (error) { return fail('invalidSelector', targetSelector); }
      const matches = () => Array.from(container.querySelectorAll(targetSelector))
        .filter(element => element.textContent.trim() === targetText);
      const choose = candidates => {
        if (candidates.length !== 1) return fail('ambiguousSelector', targetText);
        candidates[0].click();
        return { ok: true };
      };
      const initial = matches();
      if (initial.length > 0) return choose(initial);
      return await new Promise(resolve => {
        let timer;
        const observer = new MutationObserver(() => {
          const candidates = matches();
          if (candidates.length > 0) {
            observer.disconnect();
            clearTimeout(timer);
            resolve(choose(candidates));
          }
        });
        observer.observe(container, { childList: true, subtree: true, characterData: true });
        timer = setTimeout(() => {
          observer.disconnect();
          resolve(fail('timedOut', targetText));
        }, milliseconds);
      });
    }

    if (operation === 'wait') {
      if (elements.length > 0) return { ok: true };
      return await new Promise(resolve => {
        let observer;
        const finish = result => { observer.disconnect(); clearTimeout(timer); resolve(result); };
        observer = new MutationObserver(() => {
          const current = find();
          if (current && current.length > 0) finish({ ok: true });
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
        const timer = setTimeout(() => finish(fail('timedOut', selector)), milliseconds);
      });
    }

    if (elements.length === 0) return fail('elementNotFound', selector);
    if (elements.length !== 1) return fail('ambiguousSelector', selector);
    const element = elements[0];

    if (operation === 'click') {
      element.click();
      return { ok: true };
    }
    if (operation === 'check') {
      if (!(element instanceof HTMLInputElement) || !['checkbox', 'radio'].includes(element.type)) {
        return fail('unsupportedElement', selector);
      }
      if (element.type === 'radio' && !checked) return fail('invalidValue', 'A radio button cannot be unchecked directly');
      if (element.checked !== checked) element.click();
      if (element.checked !== checked) return fail('verificationFailed', selector);
      return { ok: true };
    }
    if (operation === 'attachImages') {
      if (!(element instanceof HTMLInputElement) || element.type !== 'file' || element.disabled) {
        return fail('unsupportedElement', selector);
      }
      if (images.length > 1 && !element.multiple) return fail('invalidValue', 'File input does not allow multiple files');
      const transfer = new DataTransfer();
      for (const image of images) {
        const bytes = Uint8Array.from(atob(image.base64), character => character.charCodeAt(0));
        transfer.items.add(new File([bytes], image.fileName, { type: image.mimeType }));
      }
      element.files = transfer.files;
      element.dispatchEvent(new Event('input', { bubbles: true }));
      element.dispatchEvent(new Event('change', { bubbles: true }));
      const attached = Array.from(element.files || []);
      if (attached.length !== images.length || attached.some((file, index) =>
        file.name !== images[index].fileName || file.size !== atob(images[index].base64).length || file.type !== images[index].mimeType)) {
        return fail('verificationFailed', selector);
      }
      return { ok: true };
    }
    if (operation === 'value') {
      if (!('value' in element)) return fail('unsupportedElement', selector);
      return { ok: true, value: String(element.value) };
    }
    if (operation === 'fill' || operation === 'select') {
      const isSelect = element instanceof HTMLSelectElement;
      const isText = element instanceof HTMLTextAreaElement ||
        (element instanceof HTMLInputElement && !['checkbox', 'radio', 'file', 'hidden', 'button', 'submit'].includes(element.type));
      if (operation === 'select' && !isSelect || operation === 'fill' && !isText) {
        return fail('unsupportedElement', selector);
      }
      if (element.disabled || element.readOnly) return fail('unsupportedElement', selector);
      if (isSelect && !Array.from(element.options).some(option => option.value === value)) {
        return fail('invalidValue', value);
      }
      const prototype = isSelect ? HTMLSelectElement.prototype :
        element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
      if (!setter) return fail('unsupportedElement', selector);
      setter.call(element, value);
      element.dispatchEvent(new Event('input', { bubbles: true }));
      element.dispatchEvent(new Event('change', { bubbles: true }));
      if (String(element.value) !== value) return fail('verificationFailed', selector);
      return { ok: true };
    }
    return fail('invalidValue', operation);
    """#
}
