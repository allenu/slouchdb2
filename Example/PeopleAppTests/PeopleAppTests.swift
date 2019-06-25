//
//  PeopleAppTests.swift
//  PeopleAppTests
//
//  Created by Allen Ussher on 6/23/19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest
import SlouchDB2

class PeopleAppTests: XCTestCase {
    let firstObject = DatabaseObject(identifier: "first",
                                     creationDate: Date(),
                                     properties: [ "name" : .string("Karl"),
                                                   "age" : .int(31),
                                                   "weight" : .int(130) ])
    let firstObjectAge69 = DatabaseObject(identifier: "first",
                                          creationDate: Date(),
                                          properties: [ "name" : .string("Karl"),
                                                        "age" : .int(69),
                                                        "weight" : .int(130) ])
    let secondObject = DatabaseObject(identifier: "second",
                                      creationDate: Date(),
                                      properties: [ "name" : .string("Frank"),
                                                    "age" : .int(69),
                                                    "weight" : .int(100) ])
    let thirdObject = DatabaseObject(identifier: "third",
                                     creationDate: Date(),
                                     properties: [ "name" : .string("Garfield"),
                                                   "age" : .int(100),
                                                   "weight" : .int(50) ])
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testAdd() {
        let localJournal = Journal(identifier: "my-journal")
        let snapshot = DatabaseSnapshot(localIdentifier: localJournal.identifier, objects: [:], journalSnapshots: [:])
        let database = Database(localJournal: localJournal, snapshot: snapshot)
        
        database.add(identifier: firstObject.identifier, properties: firstObject.properties)
        
        let firstObjectCopy = database.read(identifier: firstObject.identifier)!
        XCTAssertEqual(firstObject, firstObjectCopy)
    }
    
    func testMissingObject() {
        let localJournal = Journal(identifier: "my-journal")
        let snapshot = DatabaseSnapshot(localIdentifier: localJournal.identifier, objects: [:], journalSnapshots: [:])
        let database = Database(localJournal: localJournal, snapshot: snapshot)
        
        let firstObjectCopy = database.read(identifier: firstObject.identifier)
        XCTAssertNil(firstObjectCopy)
    }
    
    func testRemoveObject() {
        let localJournal = Journal(identifier: "my-journal")
        let snapshot = DatabaseSnapshot(localIdentifier: localJournal.identifier, objects: [:], journalSnapshots: [:])
        let database = Database(localJournal: localJournal, snapshot: snapshot)
        
        database.add(identifier: firstObject.identifier, properties: firstObject.properties)
        let firstObjectCopy = database.read(identifier: firstObject.identifier)!
        XCTAssertEqual(firstObject, firstObjectCopy)
        
        database.remove(identifier: firstObject.identifier)
        let firstObjectNil = database.read(identifier: firstObject.identifier)
        
        XCTAssertNil(firstObjectNil)
    }
    
    func testModifyObject() {
        let localJournal = Journal(identifier: "my-journal")
        let snapshot = DatabaseSnapshot(localIdentifier: localJournal.identifier, objects: [:], journalSnapshots: [:])
        let database = Database(localJournal: localJournal, snapshot: snapshot)
        
        database.add(identifier: firstObject.identifier, properties: firstObject.properties)

        database.modify(identifier: firstObject.identifier, properties: ["age" : .int(69)])
        
        let firstObjectCopy = database.read(identifier: firstObject.identifier)!
        XCTAssertEqual(firstObjectAge69, firstObjectCopy)
        
        XCTAssertEqual(firstObjectCopy.properties["name"], JSONValue.string("Karl"))
    }
    
    func testOutputDiff() {
        let localJournal = Journal(identifier: "my-journal")
        let snapshot = DatabaseSnapshot(localIdentifier: localJournal.identifier, objects: [:], journalSnapshots: [:])
        let database = Database(localJournal: localJournal, snapshot: snapshot)
        
        database.add(identifier: firstObject.identifier, properties: firstObject.properties)
        database.add(identifier: secondObject.identifier, properties: secondObject.properties)
        database.add(identifier: thirdObject.identifier, properties: thirdObject.properties)
        
        XCTAssertEqual(database.localJournal.diffs.count, 3)
    }
    
    func testPlay() {
        
    }
    
    func testMergeFromBlankDatabase() {
        let blankJournal = Journal(identifier: "test")
        let blankSnapshot = DatabaseSnapshot(localIdentifier: "test", objects: [:], journalSnapshots: [:])
        let blankDatabase = Database(localJournal: blankJournal, snapshot: blankSnapshot)
        
        let now = Date()
        let remoteJournal = Journal(identifier: "second")
        remoteJournal.diffs.append(JournalDiff(diffType: .add, identifier: "obj1", timestamp: now, properties: ["age": .int(37)]))
        
        let mergeResult = Merge(database: blankDatabase, journals: [blankJournal, remoteJournal], tailSnapshots: [blankSnapshot])
        let newDatabase = mergeResult.database!
        
        XCTAssertEqual(newDatabase.objects()["obj1"]!.properties["age"], JSONValue.int(37))
        
        // Should not touch the old database
        XCTAssertEqual(blankDatabase.objects().count, 0)

        // If we run it again with more stuff, it should also include the new obj
        let updatedRemoteJournal = Journal(identifier: "second")
        updatedRemoteJournal.diffs.append(JournalDiff(diffType: .add, identifier: "obj1", timestamp: now, properties: ["age": .int(37)]))
        updatedRemoteJournal.diffs.append(JournalDiff(diffType: .add, identifier: "obj2", timestamp: now.addingTimeInterval(1.0), properties: ["age": .int(16)]))

        let updatedMergeResult = Merge(database: newDatabase, journals: [blankJournal, updatedRemoteJournal], tailSnapshots: [newDatabase.snapshot])
        let updatedDatabase = updatedMergeResult.database!
        XCTAssertEqual(updatedDatabase.objects().count, 2)
        XCTAssertEqual(updatedDatabase.objects()["obj1"]!.properties["age"], JSONValue.int(37))
        XCTAssertEqual(updatedDatabase.objects()["obj2"]!.properties["age"], JSONValue.int(16))

        // Should not touch the old database
        XCTAssertEqual(newDatabase.objects().count, 1)
    }
    
    func testUpdateNonexistentObjectShouldDoNothing() {
        let blankJournal = Journal(identifier: "test")
        let blankSnapshot = DatabaseSnapshot(localIdentifier: "test", objects: [:], journalSnapshots: [:])
        let blankDatabase = Database(localJournal: blankJournal, snapshot: blankSnapshot)
        
        let now = Date()
        let remoteJournal = Journal(identifier: "second")
        remoteJournal.diffs.append(JournalDiff(diffType: .update, identifier: "obj1", timestamp: now, properties: ["age": .int(37)]))

        let mergeResult = Merge(database: blankDatabase, journals: [blankJournal, remoteJournal], tailSnapshots: [blankSnapshot])
        let newDatabase = mergeResult.database!
        
        // Should remain empty
        XCTAssertEqual(newDatabase.objects().count, 0)
    }
    
    func testSave() {
        // Create Database
        
        // Call Save
    }
}
