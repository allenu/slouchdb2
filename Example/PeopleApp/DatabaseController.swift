//
//  DatabaseController.swift
//  PeopleApp
//
//  Created by Allen Ussher on 6/23/19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import Foundation
import SlouchDB2

class DatabaseController {
    
    var database: Database
    
    var people: [Person] {
        let objects = database.objects().values.sorted(by: { $0.creationDate < $1.creationDate })
        
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
    
    init(localIdentifier: String) {
        database = Database(localJournal: Journal(identifier: localIdentifier),
                            snapshot: DatabaseSnapshot(localIdentifier: localIdentifier,
                                                       objects: [:], journalSnapshots: [:]))
    }
    
    func add(person: Person) {
        let properties: [String : JSONValue] = [
            Person.namePropertyKey : .string(person.name),
            Person.agePropertyKey : .int(person.age),
            Person.weightPropertyKey : .int(person.weight)
        ]
        database.add(identifier: person.identifier, properties: properties)
    }
    
    func modify(identifier: String, properties: [String : JSONValue]) {
        database.modify(identifier: identifier, properties: properties)
    }
    
    func sync(remoteFolderURL: URL) {
        
    }
}
