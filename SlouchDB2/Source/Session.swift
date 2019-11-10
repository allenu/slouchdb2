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
    
    // The state of the remote cache -- this will include a copy of whatever our local journal
    public var remoteJournalVersion: [String : String] = [:]
    public var remoteJournals: [String : Journal] = [:]
    public var tailSnapshots: [String : DatabaseSnapshot] = [:]
    public var lastLocalJournalChangePushed: String = "no-data" // Cannot store empty string to Data
    
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
                remoteJournalVersion: [String : String],
                lastLocalJournalChangePushed: String,
                remoteJournals: [String : Journal],
                tailSnapshots: [String : DatabaseSnapshot]) {
        self.localIdentifier = localIdentifier
        self.database = Database(localJournal: localJournal, snapshot: snapshot)
        self.remoteJournalVersion = remoteJournalVersion
        self.lastLocalJournalChangePushed = lastLocalJournalChangePushed
        self.remoteJournals = remoteJournals
        self.tailSnapshots = tailSnapshots
    }

    public static func from(fileWrapper: FileWrapper) -> Session? {
        var snapshot: DatabaseSnapshot?
        var localJournal: Journal?
    
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    
        var remoteJournalVersion: [String : String] = [:]
        var remoteJournals: [String : Journal] = [:]
        var lastLocalJournalChangePushed: String = "no-data"
        var tailSnapshots: [String : DatabaseSnapshot] = [:]
        
        // In this bundle folder will be the following
        // local/
        //   - local.snapshot
        //   - local.journal
        // remote
        //   - uuid1.journal
        //   - uuid2.journal
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
                        if filename.hasSuffix(".journal") {
                            if let remoteJournal = try? decoder.decode(Journal.self, from: data) {
                                remoteJournals[remoteJournal.identifier] = remoteJournal
                            } else {
                                assertionFailure()
                            }
                        } else if filename == "info.last-push" {
                            if let decodedLastLocalJournalChangePushed: String = try? String(data: data, encoding: .utf8) {
                                lastLocalJournalChangePushed = decodedLastLocalJournalChangePushed
                            } else {
                                assertionFailure()
                            }
                        } else if filename == "info.remote-version" {
                            if let decodedRemoteJournalVersion = try? decoder.decode([String : String].self, from: data) {
                                remoteJournalVersion = decodedRemoteJournalVersion
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
                           remoteJournalVersion: remoteJournalVersion,
                           lastLocalJournalChangePushed: lastLocalJournalChangePushed,
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
        remoteJournals.forEach { keyValue in
            let identifier = keyValue.key
            let journal = keyValue.value
            
            let journalData = try! encoder.encode(journal)
            remoteFolderFileWrappers["\(identifier).journal"] = FileWrapper(regularFileWithContents: journalData)
        }
        
        let remoteJournalVersionData = try! encoder.encode(remoteJournalVersion)
        remoteFolderFileWrappers["info.remote-version"] = FileWrapper(regularFileWithContents: remoteJournalVersionData)
        let lastLocalJournalChangePushedData = lastLocalJournalChangePushed.data(using: .utf8)!
        remoteFolderFileWrappers["info.last-push"] = FileWrapper(regularFileWithContents: lastLocalJournalChangePushedData)

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
    
    // New version of sync.
    
    public func sync(remoteSessionStore: RemoteSessionStore, completionHandler: @escaping (SessionSyncResult) -> Void) {
        // Update our tailSnapshot of our local database snapshot
        tailSnapshots[database.localJournal.identifier] = database.snapshot
        
        // Make a copy of the local journal in case it changes while we're syncing
        let localJournal = database.localJournal
        let localIdentifier = self.localIdentifier
        
        // Here's the basic algorithm:
        // 1. Fetch a list of files in the remote path and their versions
        // 2. If local journal is different from remote version or has not been uploaded yet,
        //    upload it. On completion, save remote version number.
        //    => execution goes into a dispatch group
        // 3. For each local journal, see if local version is older than what's in the remote
        //    or does not yet exist locally. If so, download it. On success, save remote
        //    version number local version ledger.
        //    => all downloads are put in a local dispatch group. Do not execute 4 until
        //       we are done downloading.
        // 4. Once all remote journals are downloaded, merge everything.
        //    => execution goes into a dispatch group
        // 5. Call completionHandler()
        
        // TODO: Make this result fail entire sync even if downloads succeed?
        var pushResult: SessionSyncResult?
        
        let doFetchRemoteJournals: ([String : String]) -> Void = { [weak self] fetchedVersions in
            // 3. Fetch all those journals that differ from local version
            
            let journalsToFetch: [String] = fetchedVersions.filter( { keyValue in
                let fetchedVersion = keyValue.value
                let localKnownVersion = self?.remoteJournalVersion[keyValue.key] ?? "not-found"
                
                let shouldFetchJournal: Bool
                if keyValue.key == localIdentifier {
                    // Never pull a local journal
                    shouldFetchJournal = false
                } else {
                    shouldFetchJournal = localKnownVersion != fetchedVersion
                }

                return shouldFetchJournal
            }).map { $0.key }
            
            if journalsToFetch.count > 0 {
                remoteSessionStore.fetchJournals(identifiers: journalsToFetch) { [weak self] response in
                    guard let strongSelf = self else { return }
                    
                    switch response {
                    case .success(let journalAndVersion):
                        
                        journalAndVersion.forEach { journalAndVersion in
                            strongSelf.remoteJournals[journalAndVersion.journal.identifier] = journalAndVersion.journal
                            strongSelf.remoteJournalVersion[journalAndVersion.journal.identifier] = journalAndVersion.version
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
        
        // 1. Fetch file versions
        remoteSessionStore.fetchRemoteJournalVersions() { fetchedRemoteJournalVersionsResponse in
            
            switch fetchedRemoteJournalVersionsResponse {
            case .success(let fetchedVersions):
                // 2. Decide if we should "push" local file to remote
                // - if fetchedRemoteJournalVersions[localIdentifier] doesn't exist or is different
                //   from local one
                let shouldPushLocalJournal: Bool
                if let lastDiff = self.database.localJournal.diffs.last {
                    let dateFormatter = ISO8601DateFormatter()
                    let lastDiffDate = dateFormatter.string(from: lastDiff.timestamp)
                    shouldPushLocalJournal = self.lastLocalJournalChangePushed != lastDiffDate
                } else {
                    // No diffs to push yet
                    shouldPushLocalJournal = false
                }

                if shouldPushLocalJournal {
                    remoteSessionStore.push(localJournal: localJournal) { pushResponse in
                        switch pushResponse {
                        case .success(let version):
                            // Push succeeded.
                            pushResult = .success
                            
                            if let lastDiff = self.database.localJournal.diffs.last {
                                let dateFormatter = ISO8601DateFormatter()
                                let lastDiffDate = dateFormatter.string(from: lastDiff.timestamp)
                                self.lastLocalJournalChangePushed = lastDiffDate
                            } else {
                                assertionFailure()
                            }

                            self.remoteJournalVersion[localIdentifier] = version
                            
                        case .failure(let reason):
                            pushResult = .failure(reason: reason)
                        }
                    }
                } else {
                    pushResult = .success
                }
                doFetchRemoteJournals(fetchedVersions)
                
            case .failure(let reason):
                completionHandler(.failure(reason: reason))
            }
        }
    }

}
