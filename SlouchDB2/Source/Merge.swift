//
//  Merge.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/24/19.
//

import Foundation

public struct MergeResult {
    // Database is nil if there was nothing to merge
    public let database: Database?
    
    public let tailSnapshots: [String : DatabaseSnapshot]
}

// Merge the journals, producing a new database. The tail snapshots are used as caches to speed up the
// process. If no suitable starting snapshot is found, starts from t0 and builds up the entire
// thing from scratch.
public func Merge(database: Database,
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
            // TODO: - remove assert? Seems like this could happen in cases where we failed to upload?
            
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
    
    let playResult = Play(journals: journals,
                          onto: startingSnapshot,
                          startingAt: startingSnapshot.lastTimestamp)
    let newDatabase = Database(localJournal: database.localJournal, snapshot: playResult.snapshot)
    
    return MergeResult(database: newDatabase, tailSnapshots: playResult.tailSnapshots)
}
