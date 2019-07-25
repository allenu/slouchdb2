//
//  Session.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/24/19.
//

import Foundation

public enum SessionSyncResult {
    case success
    case failure(reason: RemoteRequestFailureReason)
}

public class Session {
    public let localIdentifier: String
    public var database: Database
    
    // The state of the remote cache -- this will include a copy of whatever our local journal and metadata are
    public var remoteJournalMetadata: [String : JournalMetadata] = [:]
    public var remoteJournals: [String : Journal] = [:]
    public var tailSnapshots: [String : DatabaseSnapshot] = [:]
    
    public init(localIdentifier: String) {
        self.localIdentifier = localIdentifier
        let snapshot = DatabaseSnapshot(localIdentifier: localIdentifier,
                                         objects: [:],
                                         journalSnapshots: [:])
        let localJournal = Journal(identifier: localIdentifier)
        database = Database(localJournal: localJournal, snapshot: snapshot)
    }
    
    public init(localIdentifier: String,
                snapshot: DatabaseSnapshot,
                localJournal: Journal,
                remoteJournalMetadata: [String : JournalMetadata],
                remoteJournals: [String : Journal],
                tailSnapshots: [String : DatabaseSnapshot]) {
        self.localIdentifier = localIdentifier
        self.database = Database(localJournal: localJournal, snapshot: snapshot)
        self.remoteJournalMetadata = remoteJournalMetadata
        self.remoteJournals = remoteJournals
        self.tailSnapshots = tailSnapshots
    }

    public static func from(fileWrapper: FileWrapper) -> Session? {
        var snapshot: DatabaseSnapshot?
        var localJournal: Journal?
    
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    
        var remoteJournalMetadata: [String : JournalMetadata] = [:]
        var remoteJournals: [String : Journal] = [:]
        var tailSnapshots: [String : DatabaseSnapshot] = [:]
    
        // In this bundle folder will be the following
        // local/
        //   - local.snapshot
        //   - local.journal
        //   - local.metadata
        // remote
        //   - uuid1.journal
        //   - uuid1.metadata
        //   - uuid2.journal
        //   - uuid2.metadata
        // cache
        //   - uuid1.snapshot
        //   - uuid2.snapshot
        if let subFileWrappers = fileWrapper.fileWrappers {
            if let localSubfolderWrapper = subFileWrappers.values.filter({ $0.filename! == "local" }).first {
                localSubfolderWrapper.fileWrappers?.forEach { keyValue in
                    let filename = keyValue.key
                    let fileWrapper = keyValue.value
    
                    switch filename {
                    case "local.snapshot":
                        if let localSnapshotData = fileWrapper.regularFileContents {
                            snapshot = try? decoder.decode(DatabaseSnapshot.self, from: localSnapshotData)
                        }
    
                    case "local.journal":
                        if let localJournalData = fileWrapper.regularFileContents {
                            localJournal = try? decoder.decode(Journal.self, from: localJournalData)
                        }
    
                    default:
                        Swift.print("Unknown file: \(filename)")
                    }
                }
            }
            if let remoteSubfolderWrapper = subFileWrappers.values.filter({ $0.filename! == "remote" }).first {
                remoteSubfolderWrapper.fileWrappers?.forEach { keyValue in
                    let filename = keyValue.key
                    let fileWrapper = keyValue.value
    
                    if let data = fileWrapper.regularFileContents {
                        if filename.hasSuffix(".metadata") {
                            if let metadata = try? decoder.decode(JournalMetadata.self, from: data) {
                                remoteJournalMetadata[metadata.identifier] = metadata
                            } else {
                                assertionFailure()
                            }
                        } else if filename.hasSuffix(".journal") {
                            if let remoteJournal = try? decoder.decode(Journal.self, from: data) {
                                remoteJournals[remoteJournal.identifier] = remoteJournal
                            } else {
                                assertionFailure()
                            }
                        } else {
                            assertionFailure()
                        }
                    }
                }
            }
            if let cacheSubfolderWrapper = subFileWrappers.values.filter({ $0.filename! == "cache" }).first {
                cacheSubfolderWrapper.fileWrappers?.forEach { keyValue in
                    let filename = keyValue.key
                    let fileWrapper = keyValue.value
                    if let data = fileWrapper.regularFileContents {
                        if filename.hasSuffix(".snapshot") {
                            if let snapshot = try? decoder.decode(DatabaseSnapshot.self, from: data) {
                                tailSnapshots[snapshot.localIdentifier] = snapshot
                            } else {
                                assertionFailure()
                            }
                        }
                    }
                }
            }
        }
    
        if let snapshot = snapshot, let localJournal = localJournal {
            return Session(localIdentifier: localJournal.identifier,
                           snapshot: snapshot,
                           localJournal: localJournal,
                           remoteJournalMetadata: remoteJournalMetadata,
                           remoteJournals: remoteJournals,
                           tailSnapshots: tailSnapshots)
        } else {
            Swift.print("Couldn't load snapshot or journal")
            return nil
        }
    }

    public func save() -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let localSnapshotData = try! encoder.encode(database.snapshot)
        let localSnapshotFileWrapper = FileWrapper(regularFileWithContents: localSnapshotData)
        
        let localJournalData = try! encoder.encode(database.localJournal)
        let journalFileWrapper = FileWrapper(regularFileWithContents: localJournalData)
        
        let localFolderWrapper = FileWrapper(directoryWithFileWrappers: ["local.snapshot" : localSnapshotFileWrapper,
                                                                         "local.journal" : journalFileWrapper])
        
        var remoteFolderFileWrappers: [String : FileWrapper] = [:]
        remoteJournalMetadata.forEach { keyValue in
            let identifier = keyValue.key
            let metadata = keyValue.value
            
            let metadataData = try! encoder.encode(metadata)
            remoteFolderFileWrappers["\(identifier).metadata"] = FileWrapper(regularFileWithContents: metadataData)
        }
        remoteJournals.forEach { keyValue in
            let identifier = keyValue.key
            let journal = keyValue.value
            
            let journalData = try! encoder.encode(journal)
            remoteFolderFileWrappers["\(identifier).journal"] = FileWrapper(regularFileWithContents: journalData)
        }
        
        let remoteFolderWrapper = FileWrapper(directoryWithFileWrappers: remoteFolderFileWrappers)
        
        var cacheFolderFileWrappers: [String : FileWrapper] = [:]
        tailSnapshots.forEach { keyValue in
            let identifier = keyValue.key
            let snapshot = keyValue.value
            
            let snapshotData = try! encoder.encode(snapshot)
            cacheFolderFileWrappers["\(identifier).snapshot"] = FileWrapper(regularFileWithContents: snapshotData)
        }
        let cacheFolderWrapper = FileWrapper(directoryWithFileWrappers: cacheFolderFileWrappers)
        
        let documentFileWrapper = FileWrapper(directoryWithFileWrappers: ["local" : localFolderWrapper,
                                                                          "remote" : remoteFolderWrapper,
                                                                          "cache" : cacheFolderWrapper])
        
        return documentFileWrapper
    }
    
    public func sync(remoteSessionStore: RemoteSessionStore, completionHandler: @escaping (SessionSyncResult) -> Void) {
        // Update our tailSnapshot of our local database snapshot
        tailSnapshots[database.localJournal.identifier] = database.snapshot
        
        // Make a copy of the local journal in case it changes while we're syncing
        let localJournal = database.localJournal
        let localMetadata = database.metadata
        let localIdentifier = self.localIdentifier
        let remoteJournalMetadata = self.remoteJournalMetadata
        
        // The following code is broken up into blocks since they're asynchronous and must
        // execute after each other. Essentially we do three things:
        // 1. Get remote metadata that is newer than what we have
        // 2. Push local journal and metadata if the remote doesn't have the latest
        // 3. Fetch all remote journals newer than what we have
        // 4. Merge everything, keeping in mind the date of oldest "new" diff
        
        let doFetchRemoteJournals: ([String : JournalMetadata]) -> Void = { [weak self] fetchedMetadata in
            // 3. Fetch all those journals that changed
            // - for each fetchedRemoteJournalMetadata entry that isn't localIdentifier,
            //   - see if remote diffCount differ from ours
            //   - if so, add to list
            // - from list above, do a copy to local cache
            
            let journalsToFetch: [String] = fetchedMetadata.filter( { keyValue in
                let fetchedRemoteJournalMetadata = keyValue.value
                
                let shouldFetchJournal: Bool
                if fetchedRemoteJournalMetadata.identifier == localIdentifier {
                    // Never pull a local journal
                    shouldFetchJournal = false
                } else if let localJournalMetadata = remoteJournalMetadata[fetchedRemoteJournalMetadata.identifier] {
                    if localJournalMetadata.diffCount != fetchedRemoteJournalMetadata.diffCount {
                        shouldFetchJournal = true
                    } else {
                        shouldFetchJournal = false
                    }
                } else {
                    shouldFetchJournal = true
                }

                return shouldFetchJournal
            }).map { $0.key }
            
            if journalsToFetch.count > 0 {
                remoteSessionStore.fetchJournals(identifiers: journalsToFetch) { [weak self] response in
                    guard let strongSelf = self else { return }
                    
                    switch response {
                    case .success(let journals):
                        
                        journals.forEach { journal in
                            strongSelf.remoteJournalMetadata[journal.identifier] = fetchedMetadata[journal.identifier]
                            strongSelf.remoteJournals[journal.identifier] = journal
                        }
                        
                        // 4. Finally, do a merge
                        let workingTailSnapshots = Array(strongSelf.tailSnapshots.values)
                        
                        let mergeResult = Merge(database: strongSelf.database,
                                                journals: Array(strongSelf.remoteJournals.values),
                                                tailSnapshots: workingTailSnapshots)
                        
                        if let newDatabase = mergeResult.database {
                            strongSelf.database = newDatabase
                        }
                        
                        // Merge with new tail snapshots generated, taking the new one, if available
                        strongSelf.tailSnapshots = strongSelf.tailSnapshots.merging(mergeResult.tailSnapshots, uniquingKeysWith: { $1 })
                        
                        completionHandler(.success)
                        
                    case .failure(let reason):
                        completionHandler(.failure(reason: reason))
                    }
                }
            } else {
                // No journals to sync!
                completionHandler(.success)
            }
        }
        
        // 1. Fetch metadata newer than what we have locally
        remoteSessionStore.fetchNewMetadata(existingMetadata: remoteJournalMetadata) { fetchMetadataResponse in
            switch fetchMetadataResponse {
            case .success(let fetchedMetadata):
                // 2. Decide if we should "push" local file to remote
                // - if fetchedMetadata[localIdentifier] doesn't exist
                // - or if its diffCount is not same as ours (ours is newer)
                let shouldPushLocalJournal: Bool
                if let fetchedLocalMetadata = fetchedMetadata[localIdentifier] {
                    if fetchedLocalMetadata.diffCount != localJournal.diffs.count {
                        shouldPushLocalJournal = true
                    } else {
                        shouldPushLocalJournal = false
                    }
                } else {
                    // No remote copy, so do push
                    shouldPushLocalJournal = true
                }
                
                if shouldPushLocalJournal {
                    remoteSessionStore.push(localJournal: localJournal,
                                            localMetadata: localMetadata) { pushResponse in
                        switch pushResponse {
                        case .success:
                            // Push succeeded.
                            doFetchRemoteJournals(fetchedMetadata)
                            
                        case .failure(let reason):
                            completionHandler(.failure(reason: reason))
                        }
                    }
                } else {
                    doFetchRemoteJournals(fetchedMetadata)
                }

            case .failure(let reason):
                completionHandler(.failure(reason: reason))
            }
        }
    }
}
