//
//  DatabaseObject.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/16/19.
//  Copyright © 2019 Ussher Press. All rights reserved.
//

import Foundation

public struct DatabaseObject: Codable, Equatable {
    public static func == (lhs: DatabaseObject, rhs: DatabaseObject) -> Bool {
        return lhs.identifier == rhs.identifier && lhs.properties == rhs.properties
    }
    
    public let identifier: String
    public let creationDate: Date
    public let properties: [String : JSONValue]
    
    public init(identifier: String,
                creationDate: Date,
                properties: [String : JSONValue]) {
        self.identifier = identifier
        self.creationDate = creationDate
        self.properties = properties
    }
}
