//
//  Document.swift
//  PeopleApp
//
//  Created by Allen Ussher on 6/22/19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import Cocoa
import SlouchDB2

class Document: NSDocument {
    var databaseController: DatabaseController?
    
    // The state of the remote cache -- this will include a copy of whatever our local journal and metadata are
    var remoteJournalMetadata: [String : JournalMetadata] = [:]
    var remoteJournals: [String : Journal] = [:]
    var tailSnapshots: [String : DatabaseSnapshot] = [:]

    override init() {
        super.init()
        // Add your subclass-specific initialization here.
        databaseController = DatabaseController(localIdentifier: UUID().uuidString)
    }

    override class var autosavesInPlace: Bool {
        return true
    }

    override func makeWindowControllers() {
        // Returns the Storyboard that contains your Document window.
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Document Window Controller")) as! NSWindowController
        self.addWindowController(windowController)
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
            
        let localSnapshotData = try! encoder.encode(databaseController!.database.snapshot)
        let localSnapshotFileWrapper = FileWrapper(regularFileWithContents: localSnapshotData)
        
        let localJournalData = try! encoder.encode(databaseController!.database.localJournal)
        let journalFileWrapper = FileWrapper(regularFileWithContents: localJournalData)

        let localMetadata = try! encoder.encode(databaseController!.database.metadata)
        let localMetadataFileWrapper = FileWrapper(regularFileWithContents: localMetadata)
        
        let localFolderWrapper = FileWrapper(directoryWithFileWrappers: ["local.snapshot" : localSnapshotFileWrapper,
                                                                             "local.journal" : journalFileWrapper,
                                                                             "local.metadata" : localMetadataFileWrapper ])

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

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
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
        
        var snapshot: DatabaseSnapshot?
        var localJournal: Journal?
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
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

        // TODO:
        if let snapshot = snapshot, let localJournal = localJournal {
            databaseController = DatabaseController(localIdentifier: localJournal.identifier)
            databaseController?.database = Database(localJournal: localJournal, snapshot: snapshot)
        } else {
            Swift.print("Couldn't load snapshot or journal")
        }
    }

    func add(person: Person) {
        databaseController?.add(person: person)
        
        self.updateChangeCount(.changeDone)
    }
    
    var people: [Person] {
        let people = databaseController?.people ?? []
        return people
    }
    
    func modifyPerson(identifier: String, properties: [String : JSONValue]) {
        databaseController?.modify(identifier: identifier, properties: properties)
        
        self.updateChangeCount(.changeDone)
    }

    func sync(remoteFolderURL: URL) {
        guard let databaseController = databaseController else { return }
        
        // Update our tailSnapshot of our local database snapshot
        tailSnapshots[databaseController.database.localJournal.identifier] = databaseController.database.snapshot
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var fetchedRemoteJournalMetadata: [String : JournalMetadata] = [:]
        
        let fileEnumerator = FileManager.default.enumerator(at: remoteFolderURL, includingPropertiesForKeys: nil)
        while let element = fileEnumerator?.nextObject() {
            if let fileURL = element as? URL {
                if fileURL.isFileURL && fileURL.lastPathComponent.hasSuffix(".metadata" ) {
                    //
                    Swift.print(fileURL.lastPathComponent)
                    
                    let data = try! Data(contentsOf: fileURL)
                    let metadata = try! decoder.decode(JournalMetadata.self, from: data)
                    fetchedRemoteJournalMetadata[metadata.identifier] = metadata
                }
            }
        }
        
        let localIdentifier = databaseController.database.localJournal.identifier

        // 1. Decide if we should "push" local file to remote
        // - if fetchedRemoteJournalMetadata[localIdentifier] doesn't exist
        // - or if its diffCount is not same as ours
        let shouldPushLocalJournal: Bool
        if let fetchedLocalMetadata = fetchedRemoteJournalMetadata[localIdentifier] {
            if fetchedLocalMetadata.diffCount != databaseController.database.localJournal.diffs.count {
                shouldPushLocalJournal = true
            } else {
                shouldPushLocalJournal = false
            }
        } else {
            // No remote copy, so do push
            shouldPushLocalJournal = true
        }
        
        if shouldPushLocalJournal {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let metadataData = try! encoder.encode(databaseController.database.metadata)
            let journalData = try! encoder.encode(databaseController.database.localJournal)

            let localMetadataFilename = "\(localIdentifier).metadata"
            let remoteLocalMetadataURL: URL = remoteFolderURL.appendingPathComponent(localMetadataFilename)
            try! metadataData.write(to: remoteLocalMetadataURL, options: [])

            let localJournalFilename = "\(localIdentifier).journal"
            let remoteLocalJournalURL: URL = remoteFolderURL.appendingPathComponent(localJournalFilename)
            try! journalData.write(to: remoteLocalJournalURL, options: [])

            remoteJournalMetadata[localIdentifier] = databaseController.database.metadata
            remoteJournals[localIdentifier] = databaseController.database.localJournal
            
            self.updateChangeCount(.changeDone)
        }
        
        // 2. Fetch all those journals that changed
        // - for each fetchedRemoteJournalMetadata entry that isn't localIdentifier,
        //   - see if remote diffCount differ from ours
        //   - if so, add to list
        // - from list above, do a copy to local cache
        var updatedJournals: [Journal] = []
        fetchedRemoteJournalMetadata.forEach { keyValue in
            let fetchedRemoteJournalMetadata = keyValue.value
            
            let shouldPullJournal: Bool
            if fetchedRemoteJournalMetadata.identifier == localIdentifier {
                // Never pull a local journal
                shouldPullJournal = false
            } else if let localJournalMetadata = remoteJournalMetadata[fetchedRemoteJournalMetadata.identifier] {
                if localJournalMetadata.diffCount != fetchedRemoteJournalMetadata.diffCount {
                    shouldPullJournal = true
                } else {
                    shouldPullJournal = false
                }
            } else {
                shouldPullJournal = true
            }
            
            if shouldPullJournal {
                // First try to get that file...
                let fetchedRemoteJournalURL = remoteFolderURL.appendingPathComponent("\(fetchedRemoteJournalMetadata.identifier).journal")
                if let fetchedRemoteJournalData = try? Data(contentsOf: fetchedRemoteJournalURL) {
                    let fetchedRemoteJournal = try! decoder.decode(Journal.self, from: fetchedRemoteJournalData)
                    
                    remoteJournalMetadata[fetchedRemoteJournalMetadata.identifier] = fetchedRemoteJournalMetadata
                    remoteJournals[fetchedRemoteJournalMetadata.identifier] = fetchedRemoteJournal
                    
                    self.updateChangeCount(.changeDone)
                    
                    updatedJournals.append(fetchedRemoteJournal)
                }
            }
        }
        
        // 3. Do sync
        if updatedJournals.count > 0 {
            let workingTailSnapshots = Array(tailSnapshots.values)
            
            let mergeResult = Database.merge(database: databaseController.database,
                                             journals: Array(remoteJournals.values),
                                             tailSnapshots: workingTailSnapshots)
            
            if let newDatabase = mergeResult.database {
                databaseController.database = newDatabase
            }
            
            // Merge with new tail snapshots generated, taking the new one, if available
            tailSnapshots = tailSnapshots.merging(mergeResult.tailSnapshots, uniquingKeysWith: { $1 })
            
            self.updateChangeCount(.changeDone)
        }
        
        DispatchQueue.global().async {
            databaseController.sync(remoteFolderURL: remoteFolderURL)
        }
    }
}
