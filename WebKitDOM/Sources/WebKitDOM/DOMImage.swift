//
//  DOMImage.swift
//  WebKitDOM
//
//  Created by Neon.
//

import Foundation

/// Image bytes to attach to a native HTML file input.
public struct DOMImage: Sendable {
    public let data: Data
    public let fileName: String
    public let mimeType: String

    public init(data: Data, fileName: String, mimeType: String) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}
