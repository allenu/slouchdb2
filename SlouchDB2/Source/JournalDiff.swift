//
//  JournalDiff.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/16/19.
//  Copyright © 2019 Ussher Press. All rights reserved.
//

import Foundation

public enum DiffType: String, Codable {
    case add = "add"
    case remove = "remove"
    case update = "update"
}

public struct JournalDiff: Codable {
    let diffType: DiffType
    let type: String?
    let identifier: String
    let timestamp: Date
    
    let properties: [String : JSONValue]
    
    public init(diffType: DiffType, type: String?, identifier: String, timestamp: Date, properties: [String : JSONValue]) {
        self.diffType = diffType
        self.identifier = identifier
        self.type = type
        self.timestamp = timestamp
        self.properties = properties
    }
}
