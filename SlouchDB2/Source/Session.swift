//
//  Session.swift
//  SlouchDB2
//
//  Created by Allen Ussher on 6/24/19.
//

import Foundation

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
        let cacheFolderWrapper = FileWrapper(directoryWithFileWrappers: [:])
        
        let documentFileWrapper = FileWrapper(directoryWithFileWrappers: ["local" : localFolderWrapper,
                                                                          "remote" : remoteFolderWrapper,
                                                                          "cache" : cacheFolderWrapper])
        
        return documentFileWrapper
    }
}
