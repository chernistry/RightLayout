//
//  LayoutData.swift
//  RightLayout
//

import Foundation

/// Top-level container for the layouts.json data.
struct LayoutData: Codable {
    let layouts: [LayoutInfo]
    let map: [String: [String: KeyMapping]]
}

struct LayoutInfo: Codable {
    let id: String
    let name: String
    let language: String
    let appleId: String
}

struct KeyMapping: Codable {
    let n: String?
    let s: String?
    let a: String?
    let sa: String?
}
