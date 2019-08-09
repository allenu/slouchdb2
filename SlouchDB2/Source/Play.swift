//
//  Play.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/24/19.
//

import Foundation

public struct PlayResult {
    let snapshot: DatabaseSnapshot
    let tailSnapshots: [String : DatabaseSnapshot]
}

public func Play(journals: [Journal],
                 onto startingSnapshot: DatabaseSnapshot,
                 startingAt timestamp: Date) -> PlayResult {
    
    // Find the first diff that is newer than the timestamp in each database
    // Filter out journals that don't have any entries newer than timestamp
    let filteredJournals = journals.filter({ journal in
        if journal.diffs.first(where: { $0.timestamp > timestamp }) != nil {
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
                if snapshotObjects[currentPickedDiff.identifier] == nil {
                    snapshotObjects[currentPickedDiff.identifier] = DatabaseObject(identifier: currentPickedDiff.identifier,
                                                                                   type: currentPickedDiff.type ?? "",
                                                                                   creationDate: currentPickedDiff.timestamp,
                                                                                   properties: currentPickedDiff.properties)
                } else {
                    // Intentionally do not replace an item if it already exists.
                    // This is so that multiple nodes can add the same static content when
                    // their journal is created and not fear having it be overwritten.
                }
                
            case .update:
                
                if let oldObject = snapshotObjects[currentPickedDiff.identifier] {
                    let newObjectProperties = oldObject.properties.merging(currentPickedDiff.properties,
                                                                           uniquingKeysWith: { $1 })
                    snapshotObjects[currentPickedDiff.identifier] = DatabaseObject(identifier: currentPickedDiff.identifier,
                                                                                   type: currentPickedDiff.type ?? "",
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
