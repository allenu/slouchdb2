//
//  Database.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/16/19.
//  Copyright © 2019 Ussher Press. All rights reserved.
//

import Foundation

public struct JournalMetadata: Codable {
    public let identifier: String
    public let diffCount: Int
    public let firstTimestamp: Date
    public let lastTimestamp: Date
}

public struct JournalSnapshot: Codable {
    let identifier: String
    let metadata: JournalMetadata
    
    init(identifier: String, diffCount: Int, firstTimestamp: Date, lastTimestamp: Date) {
        self.identifier = identifier
        self.metadata = JournalMetadata(identifier: identifier,
                                        diffCount: diffCount,
                                        firstTimestamp: firstTimestamp,
                                        lastTimestamp: lastTimestamp)
    }
}

public class Database {
    public var localJournal: Journal
    public var snapshot: DatabaseSnapshot
    public var metadata: JournalMetadata {
        let date1970 = Date(timeIntervalSince1970: 0)
        return JournalMetadata(identifier: localJournal.identifier,
                               diffCount: localJournal.diffs.count,
                               firstTimestamp: localJournal.diffs.first?.timestamp ?? date1970,
                               lastTimestamp: localJournal.diffs.last?.timestamp ?? date1970)
    }
    
    public init(localJournal: Journal, snapshot: DatabaseSnapshot) {
        self.localJournal = localJournal
        self.snapshot = snapshot
    }
    
    public func read(identifier: String) -> DatabaseObject? {
        return snapshot.objects[identifier]
    }
    
    func add(localDiff: JournalDiff) {
        localJournal.diffs.append(localDiff)
        
        let newJournalSnapshot: JournalSnapshot
        if let journalSnapshot = snapshot.journalSnapshots[localJournal.identifier] {
            newJournalSnapshot = JournalSnapshot(identifier: journalSnapshot.identifier,
                                                 diffCount: journalSnapshot.metadata.diffCount,
                                                 firstTimestamp: journalSnapshot.metadata.firstTimestamp,
                                                 lastTimestamp: localDiff.timestamp)
        } else {
            newJournalSnapshot = JournalSnapshot(identifier: localJournal.identifier,
                                                 diffCount: localJournal.diffs.count,
                                                 firstTimestamp: localDiff.timestamp,
                                                 lastTimestamp: localDiff.timestamp)
        }
        snapshot.journalSnapshots[localJournal.identifier] = newJournalSnapshot
    }
    
    public func add(identifier: String, type: String, properties: [String : JSONValue]) {
        let now = Date()
        let object = DatabaseObject(identifier: identifier, type: type, creationDate: now, properties: properties)
        snapshot.objects[identifier] = object
        
        let diff = JournalDiff(diffType: .add,
                               type: type,
                               identifier: identifier,
                               timestamp: now, properties: properties)
        add(localDiff: diff)
    }
    
    public func remove(identifier: String) {
        snapshot.objects.removeValue(forKey: identifier)
        
        let now = Date()
        let diff = JournalDiff(diffType: .remove, type: nil, identifier: identifier, timestamp: now, properties: [:])
        add(localDiff: diff)
    }
    
    public func modify(identifier: String, properties: [String : JSONValue]) {
        let mergedProperties: [String : JSONValue]
        let objectType: String
        if let oldObject = snapshot.objects[identifier] {
            mergedProperties = oldObject.properties.merging(properties, uniquingKeysWith: { $1 })
            objectType = oldObject.type
            snapshot.objects[identifier] = DatabaseObject(identifier: identifier,
                                                          type: oldObject.type,
                                                          creationDate: oldObject.creationDate,
                                                          properties: mergedProperties)
        } else {
            objectType = "unknown"
            assertionFailure("Error: modifying update that doesn't exist")
        }

        // Even if object doesn't exist, still create diff for it, in the off chance we just had a bad local journal
        let now = Date()
        let diff = JournalDiff(diffType: .update,
                               type: objectType,
                               identifier: identifier,
                               timestamp: now,
                               properties: properties)
        add(localDiff: diff)
    }
    
    public func objects(type: String) -> [String : DatabaseObject] {
        // TODO: Have an in-mem grouping of object by type for easy look-up.
        return snapshot.objects.filter({ $0.value.type == type })
    }
    
    func save(directory: URL, prefix: String = "") {
        let databaseFile = directory.appendingPathComponent("\(prefix)\(localJournal.identifier)-snapshot.json")
        let localJournalFile = directory.appendingPathComponent("\(prefix)\(localJournal.identifier)-journal.json")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let snapshotData = try encoder.encode(snapshot)
            try snapshotData.write(to: databaseFile)
            
            let journalData = try encoder.encode(localJournal)
            try journalData.write(to: localJournalFile)
        } catch {
            print("Couldn't encode \(error)")
        }
    }
}
