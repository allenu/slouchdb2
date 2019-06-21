//
//  Journal.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/16/19.
//  Copyright © 2019 Ussher Press. All rights reserved.
//

import Foundation

public class Journal: Codable {
    public let identifier: String
    public var diffs: [JournalDiff]
    
    public init(identifier: String) {
        self.identifier = identifier
        diffs = []
    }
}
