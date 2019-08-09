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
        session.database.add(identifier: person.identifier, type: "person", properties: properties)
        
        self.updateChangeCount(.changeDone)
    }
    
    var people: [Person] {
        let objects = session.database.objects(type: "person").values.sorted(by: { $0.creationDate < $1.creationDate })
        
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
    
    func syncNew(remoteFolderUrl: URL) {
        let remoteSessionStore = FileBasedRemoteSessionStore(remoteFolderUrl: remoteFolderUrl)
        session.sync(remoteSessionStore: remoteSessionStore, completionHandler: { response in
            switch response {
            case .success:
                Swift.print("Sync successful")
                self.updateChangeCount(.changeDone)
                
            case .failure(let reason):
                Swift.print("Sync failed: \(reason)")
            }
        })
    }
}
