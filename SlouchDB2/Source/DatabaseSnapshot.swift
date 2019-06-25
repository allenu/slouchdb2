//
//  DatabaseSnapshot.swift
//  Pods-PeopleApp
//
//  Created by Allen Ussher on 6/24/19.
//

import Foundation

public class DatabaseSnapshot: Codable {
    public let localIdentifier: String
    public var objects: [String : DatabaseObject]
    public var journalSnapshots: [String : JournalSnapshot]
    public let lastTimestamp: Date
    
    public init(localIdentifier: String, objects: [String : DatabaseObject], journalSnapshots: [String : JournalSnapshot]) {
        self.localIdentifier = localIdentifier
        self.objects = objects
        self.journalSnapshots = journalSnapshots
        
        lastTimestamp = journalSnapshots.values.reduce(Date(timeIntervalSince1970: 0), { newestSoFar, journalSnapshot in
            if newestSoFar > journalSnapshot.metadata.lastTimestamp {
                return newestSoFar
            } else {
                return journalSnapshot.metadata.lastTimestamp
            }
        })
    }
}
