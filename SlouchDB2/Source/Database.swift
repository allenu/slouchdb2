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

public struct MergeResult {
    // Database is nil if there was nothing to merge
    public let database: Database?
    
    public let tailSnapshots: [String : DatabaseSnapshot]
}

public struct PlayResult {
    let snapshot: DatabaseSnapshot
    let tailSnapshots: [String : DatabaseSnapshot]
}

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
    
    public func add(identifier: String, properties: [String : JSONValue]) {
        let now = Date()
        let object = DatabaseObject(identifier: identifier, creationDate: now, properties: properties)
        snapshot.objects[identifier] = object
        
        let diff = JournalDiff(diffType: .add,
                               identifier: identifier,
                               timestamp: now, properties: properties)
        add(localDiff: diff)
    }
    
    public func remove(identifier: String) {
        snapshot.objects.removeValue(forKey: identifier)
        
        let now = Date()
        let diff = JournalDiff(diffType: .remove, identifier: identifier, timestamp: now, properties: [:])
        add(localDiff: diff)
    }
    
    public func modify(identifier: String, properties: [String : JSONValue]) {
        let mergedProperties: [String : JSONValue]
        if let oldObject = snapshot.objects[identifier] {
            mergedProperties = oldObject.properties.merging(properties, uniquingKeysWith: { $1 })
            snapshot.objects[identifier] = DatabaseObject(identifier: identifier, creationDate: oldObject.creationDate, properties: mergedProperties)
            
        } else {
            // Object doesn't exist to modify
        }

        // Even if object doesn't exist, still create diff for it, in the off chance we just had a bad local journal
        let now = Date()
        let diff = JournalDiff(diffType: .update, identifier: identifier, timestamp: now, properties: properties)
        add(localDiff: diff)
    }
    
    public func objects() -> [String : DatabaseObject] {
        return snapshot.objects
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
    
    public static func play(journals: [Journal],
                            onto startingSnapshot: DatabaseSnapshot,
                            startingAt timestamp: Date) -> PlayResult {
        
        // Find the first diff that is newer than the timestamp in each database
        // Filter out journals that don't have any entries newer than timestamp
        let filteredJournals = journals.filter({ journal in
            if let firstDiff = journal.diffs.first(where: { $0.timestamp > timestamp }) {
                return true
            } else {
                return false
            }
        })
        
        let filteredJournalSnapshots: [String : JournalSnapshot] = filteredJournals.reduce([:], { lastResult, journal in
            let journalSnapshot = JournalSnapshot(identifier: journal.identifier,
                                                  diffCount: journal.diffs.count,
                                                  firstTimestamp: journal.diffs.first!.timestamp,
                                                  lastTimestamp: journal.diffs.last!.timestamp)
            
            var modifiedDict = lastResult
            modifiedDict[journalSnapshot.identifier] = journalSnapshot
            return modifiedDict
        })
        var snapshotObjects: [String : DatabaseObject] = startingSnapshot.objects
        let journalSnapshots = startingSnapshot.journalSnapshots.merging(filteredJournalSnapshots,
                                                                         uniquingKeysWith: { $1 })
        
        // Since all filtered journals have at least one diff, let's start with diff at index 0 for each
        var nextDiffIndexInJournals: [Int?] = filteredJournals.map { _ in 0 }
        
        var tailSnapshots: [String : DatabaseSnapshot] = [:]
        var journalSnapshotsSoFar: [String : JournalSnapshot] = [:]
        
        var done = false
        while !done {
            // Pick the journal where the next diff is the earliest out of all
            var pickedJournalIndex: Int?
            var currentPickedDiff: JournalDiff?
            for i in 0..<filteredJournals.count {
                if let nextDiffIndexInJournal = nextDiffIndexInJournals[i] {
                    let diff = filteredJournals[i].diffs[nextDiffIndexInJournal]
                    if let innerCurrentPickedDiff = currentPickedDiff {
                        if diff.timestamp < innerCurrentPickedDiff.timestamp {
                            // This diff is older than the currently picked one, so replace it
                            currentPickedDiff = diff
                            pickedJournalIndex = i
                        }
                    } else {
                        // No current diff, so use this one
                        currentPickedDiff = diff
                        pickedJournalIndex = i
                    }
                }
            }
            
            if let currentPickedDiff = currentPickedDiff {
                switch currentPickedDiff.diffType {
                case .remove:
                    snapshotObjects.removeValue(forKey: currentPickedDiff.identifier)

                case .add:
                    snapshotObjects[currentPickedDiff.identifier] = DatabaseObject(identifier: currentPickedDiff.identifier,
                                                                                   creationDate: currentPickedDiff.timestamp,
                                                                                    properties: currentPickedDiff.properties)
                    
                case .update:
                    
                    if let oldObject = snapshotObjects[currentPickedDiff.identifier] {
                        let newObjectProperties = oldObject.properties.merging(currentPickedDiff.properties,
                                                                               uniquingKeysWith: { $1 })
                        snapshotObjects[currentPickedDiff.identifier] = DatabaseObject(identifier: currentPickedDiff.identifier,
                                                                                       creationDate: oldObject.creationDate,
                                                                                       properties: newObjectProperties)
                    } else {
                        // Old object doesn't exist, so there's nothing for us to update.
                        // This assumes the object must've been deleted and not that we just
                        // don't have that info in our journal.
                    }
                }
                
                if let pickedJournalIndex = pickedJournalIndex {
                    // Update nextDiffIndexInJournals and journalSnapshotsSoFar
                    let journal = filteredJournals[pickedJournalIndex]
                    let nextDiffIndexInJournal = nextDiffIndexInJournals[pickedJournalIndex]!

                    // nextDiffIndexInJournal represents how many diffs we've played back so far from this journal
                    journalSnapshotsSoFar[journal.identifier] = JournalSnapshot(identifier: journal.identifier,
                                                                                diffCount: nextDiffIndexInJournal,
                                                                                firstTimestamp: journal.diffs.first!.timestamp,
                                                                                lastTimestamp: journal.diffs[nextDiffIndexInJournal].timestamp)

                    if nextDiffIndexInJournal + 1 < journal.diffs.count {
                        nextDiffIndexInJournals[pickedJournalIndex] = nextDiffIndexInJournal + 1
                    } else {
                        // No more diffs for this journal
                        nextDiffIndexInJournals[pickedJournalIndex] = nil
                        
                        // Save this as a tail snapshot
                        tailSnapshots[journal.identifier] = DatabaseSnapshot(localIdentifier: journal.identifier,
                                                                             objects: snapshotObjects,
                                                                             journalSnapshots: journalSnapshotsSoFar)
                    }
                } else {
                    assertionFailure("Impossible scenario")
                }
            } else {
                // No more diffs to search
                done = true
            }
        }
        
        let newSnapshot = DatabaseSnapshot(localIdentifier: startingSnapshot.localIdentifier,
                                           objects: snapshotObjects,
                                           journalSnapshots: journalSnapshots)
        
        return PlayResult(snapshot: newSnapshot, tailSnapshots: tailSnapshots)
    }
    
    // Merge the journals, producing a new database. The tail snapshots are used as caches to speed up the
    // process. If no suitable starting snapshot is found, starts from t0 and builds up the entire
    // thing from scratch.
    public static func merge(database: Database,
                             journals: [Journal],
                             tailSnapshots: [DatabaseSnapshot]) -> MergeResult {
        
        // First, journals must be filtered to just those that have *new* contents for us.
        // The easiest way to determine this is to see if the journal has more entries than our snapshot
        // version.
        let filteredJournals = journals.filter({ journal in
            if journal.identifier == database.localJournal.identifier {
                // Skip the local journal because we assume it's included in the database's snapshot
                // already.
                return false
            } else if journal.diffs.count == 0 {
                // Filter out any empty journals. Don't care.
                return false
            } else if let localJournalSnapshot = database.snapshot.journalSnapshots[journal.identifier] {
                assert(localJournalSnapshot.metadata.diffCount <= journal.diffs.count, "Our local journal snapshot of this journal is longer than remote one!")
                return localJournalSnapshot.metadata.diffCount < journal.diffs.count
            } else {
                // We don't have a local copy of it, so do include it
                return true
            }
        })
        
        // No journals to play back, so nothing merged
        if filteredJournals.count == 0 {
            return MergeResult(database: nil, tailSnapshots: [:])
        }
        
        // Step 1.
        // Figure out what the oldest new diff entry is. This will limit our choice of snapshots to use.
        let maybeOldestNewDiffTimestamp: Date? = filteredJournals.reduce(nil, { oldestSoFar, journal in
            if let localJournalSnapshot = database.snapshot.journalSnapshots[journal.identifier] {
                // Figure out the first entry that's newer than the last we have on record
                if let firstNewDiff = journal.diffs.last(where: { $0.timestamp > localJournalSnapshot.metadata.lastTimestamp }) {
                    if let oldestSoFar = oldestSoFar {
                        if firstNewDiff.timestamp < oldestSoFar {
                            return firstNewDiff.timestamp
                        } else {
                            return oldestSoFar
                        }
                    } else {
                        return firstNewDiff.timestamp
                    }
                } else {
                    fatalError("How could we have new entries in the diffs and yet nothing newer than what we have on record?")
                }
            } else {
                // We don't know about this journal yet, so it's first diff entry must be the newest in the set.
                // Use this if it's older than the one so far
                let firstDiff = journal.diffs.first!
                if let oldestSoFar = oldestSoFar {
                    if firstDiff.timestamp < oldestSoFar {
                        return firstDiff.timestamp
                    } else {
                        return oldestSoFar
                    }
                } else {
                    return firstDiff.timestamp
                }
            }
        })
        
        guard let oldestNewDiffTimestamp = maybeOldestNewDiffTimestamp else {
            fatalError("Impossible to not have one oldest diff")
        }
        
        print("oldestNewDiffTimestamp: \(oldestNewDiffTimestamp)")

        // Step 2.
        // Find the best snapshot to start from. First try our database snapshot as it has the most up to date data.
        // If this doesn't work, find the newest from the cached snapshots that is older than oldestNewDiffTimestamp.
        let startingSnapshot: DatabaseSnapshot
        if database.snapshot.lastTimestamp < oldestNewDiffTimestamp {
            print("Using previous database as snapshot")
            startingSnapshot = database.snapshot
        } else {
            // See which snapshot is the newest that's still older than the oldest diff timestamp
            let maybeStartingSnapshot: DatabaseSnapshot? = tailSnapshots.reduce(nil, { newestSnapshotSoFar, snapshot in
                if snapshot.lastTimestamp < oldestNewDiffTimestamp &&
                    (newestSnapshotSoFar == nil || snapshot.lastTimestamp > newestSnapshotSoFar!.lastTimestamp) {
                    return snapshot
                } else {
                    return newestSnapshotSoFar
                }
            })
            
            // Use the snapshot we found, or else start with an empty one if none found
            startingSnapshot = maybeStartingSnapshot ?? DatabaseSnapshot(localIdentifier: database.localJournal.identifier, objects: [:], journalSnapshots: [:])

            print("Using cached snapshot with timestamp: \(startingSnapshot.lastTimestamp)")
        }
        
        // Play back and create a database from the list of journals.
        // Note that we do NOT use the filtered journals here since we may have to go
        // back in time and play back from an earlier point if snapshot we use isn't current
        // enough.
        
        let playResult = Database.play(journals: journals,
                                       onto: startingSnapshot,
                                       startingAt: startingSnapshot.lastTimestamp)
        let newDatabase = Database(localJournal: database.localJournal, snapshot: playResult.snapshot)
        
        return MergeResult(database: newDatabase, tailSnapshots: playResult.tailSnapshots)
    }
}
