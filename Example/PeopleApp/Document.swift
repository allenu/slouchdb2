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
    var session: Session
    
    // The state of the remote cache -- this will include a copy of whatever our local journal and metadata are
    var remoteJournalMetadata: [String : JournalMetadata] = [:]
    var remoteJournals: [String : Journal] = [:]
    var tailSnapshots: [String : DatabaseSnapshot] = [:]

    override init() {
        // Add your subclass-specific initialization here.
        let localIdentifier = UUID().uuidString
        session = Session(localIdentifier: localIdentifier)

        super.init()
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
        return session.save()
    }

    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        if let newSession = Session.from(fileWrapper: fileWrapper) {
            self.session = newSession
        } else {
            assertionFailure("Couldn't load")
        }
    }

    func add(person: Person) {
        let properties: [String : JSONValue] = [
            Person.namePropertyKey : .string(person.name),
            Person.agePropertyKey : .int(person.age),
            Person.weightPropertyKey : .int(person.weight)
        ]
        session.database.add(identifier: person.identifier, properties: properties)
        
        self.updateChangeCount(.changeDone)
    }
    
    var people: [Person] {
        let objects = session.database.objects().values.sorted(by: { $0.creationDate < $1.creationDate })
        
        return objects.map { object in
            let name: String
            let age: Int
            let weight: Int
            
            if let nameProperty = object.properties[Person.namePropertyKey],
                case let JSONValue.string(value) = nameProperty {
                name = value
            } else {
                name = "Unnamed"
            }
            
            if let ageProperty = object.properties[Person.agePropertyKey],
                case let JSONValue.int(value) = ageProperty {
                age = value
            } else {
                age = 0
            }
            
            if let weightProperty = object.properties[Person.weightPropertyKey],
                case let JSONValue.int(value) = weightProperty {
                weight = value
            } else {
                weight = 0
            }
            
            return Person(identifier: object.identifier,
                          name: name,
                          weight: weight,
                          age: age)
        }
    }

    func modifyPerson(identifier: String, properties: [String : JSONValue]) {
        session.database.modify(identifier: identifier, properties: properties)
        
        self.updateChangeCount(.changeDone)
    }

    func sync(remoteFolderURL: URL) {
        // Update our tailSnapshot of our local database snapshot
        tailSnapshots[session.database.localJournal.identifier] = session.database.snapshot
        
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
        
        let localIdentifier = session.localIdentifier

        // 1. Decide if we should "push" local file to remote
        // - if fetchedRemoteJournalMetadata[localIdentifier] doesn't exist
        // - or if its diffCount is not same as ours
        let shouldPushLocalJournal: Bool
        if let fetchedLocalMetadata = fetchedRemoteJournalMetadata[localIdentifier] {
            if fetchedLocalMetadata.diffCount != session.database.localJournal.diffs.count {
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
            
            let metadataData = try! encoder.encode(session.database.metadata)
            let journalData = try! encoder.encode(session.database.localJournal)

            let localMetadataFilename = "\(localIdentifier).metadata"
            let remoteLocalMetadataURL: URL = remoteFolderURL.appendingPathComponent(localMetadataFilename)
            try! metadataData.write(to: remoteLocalMetadataURL, options: [])

            let localJournalFilename = "\(localIdentifier).journal"
            let remoteLocalJournalURL: URL = remoteFolderURL.appendingPathComponent(localJournalFilename)
            try! journalData.write(to: remoteLocalJournalURL, options: [])

            remoteJournalMetadata[localIdentifier] = session.database.metadata
            remoteJournals[localIdentifier] = session.database.localJournal
            
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
            
            let mergeResult = Merge(database: session.database,
                                    journals: Array(remoteJournals.values),
                                    tailSnapshots: workingTailSnapshots)
            
            if let newDatabase = mergeResult.database {
                session.database = newDatabase
            }
            
            // Merge with new tail snapshots generated, taking the new one, if available
            tailSnapshots = tailSnapshots.merging(mergeResult.tailSnapshots, uniquingKeysWith: { $1 })
            
            self.updateChangeCount(.changeDone)
        }
    }
}
