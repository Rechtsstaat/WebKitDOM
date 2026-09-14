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

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func waitForElement(_ selector: String, timeout: TimeInterval = 10) async throws {
        guard timeout.isFinite, timeout >= 0, timeout <= Double(Int32.max) / 1_000 else {
            throw DOMError.invalidValue("Timeout must be between 0 and \(Double(Int32.max) / 1_000) seconds")
        }
        let milliseconds = Int(timeout * 1_000)
        _ = try await perform("wait", selector: selector, milliseconds: milliseconds)
    }

    public func fill(_ selector: String, with value: String) async throws {
        _ = try await perform("fill", selector: selector, value: value)
    }

    public func select(_ selector: String, value: String) async throws {
        _ = try await perform("select", selector: selector, value: value)
    }

    public func setChecked(_ selector: String, to checked: Bool) async throws {
        _ = try await perform("check", selector: selector, checked: checked)
    }

    public func click(_ selector: String) async throws {
        _ = try await perform("click", selector: selector)
    }

    public func value(of selector: String) async throws -> String {
        try await perform("value", selector: selector)
    }

    public func matchesValue(_ expected: String, at selector: String) async throws -> Bool {
        try await value(of: selector) == expected
    }

    private func perform(
        _ operation: String,
        selector: String,
        value: String = "",
        checked: Bool = false,
        milliseconds: Int = 0
    ) async throws -> String {
        try Task.checkCancellation()
        let arguments: [String: Any] = [
            "operation": operation,
            "selector": selector,
            "value": value,
            "checked": checked,
            "milliseconds": milliseconds
        ]

        let rawResult: Any?
        do {
            rawResult = try await webView.callAsyncJavaScript(
                Self.script,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
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
