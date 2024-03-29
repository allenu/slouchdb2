//
//  ViewController.swift
//  PeopleApp
//
//  Created by Allen Ussher on 6/22/19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import Cocoa

class ViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var folderButton: NSButton!

    private var _document: Document?
    var document: Document? {
        get {
            if _document == nil {
                _document = self.view.window?.windowController?.document as? Document
            }
            return _document
        }
    }
    var remoteFolder: URL?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        tableView.dataSource = self
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        
        tableView.reloadData()
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    
    @IBAction func didTapAddPerson(sender: Any) {
        guard let document = document else { return }
        
        let randomNames = ["Alice", "Bob", "Carol", "Eve", "Frank"]
        let name = randomNames[ Int(arc4random()) % randomNames.count ]
        let weight = Int(arc4random() % 100) + 100
        let age = Int(arc4random() % 30) + 10
        
        let person = Person(identifier: UUID().uuidString, name: name, weight: weight, age: age)
        document.add(person: person)
        
        // TODO: This is super inefficient
        tableView.reloadData()
    }

    @IBAction func didTapSync(sender: Any) {
        guard let document = document else { return }
        
        if let remoteFolder = remoteFolder {
//            document.sync(remoteFolderURL: remoteFolder)
            document.syncNew(remoteFolderUrl: remoteFolder)
            
            // TODO: use Document to tell us when we should sync...
            tableView.reloadData()
        }
    }

    @IBAction func didTapSyncLocation(sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.begin(completionHandler: { result in
            if result == NSApplication.ModalResponse.OK {
                
                let remoteURL = openPanel.urls.first
                self.remoteFolder = remoteURL
                
                DispatchQueue.main.async {
                    self.folderButton.title = remoteURL?.path ?? "Select Sync Folder"
                }
            }
        })
    }

}

extension ViewController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        guard let document = document else { return 0 }
        
        return document.people.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let document = document else { return nil }
        
        let person = document.people[row]
        if tableColumn!.identifier.rawValue == Person.namePropertyKey {
            return person.name
        } else if tableColumn!.identifier.rawValue == Person.weightPropertyKey {
            return person.weight
        } else if tableColumn!.identifier.rawValue == Person.agePropertyKey {
            return person.age
        } else {
            return nil
        }
    }
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let document = document else { return }
        
        var person = document.people[row]
        if let value = object as? String {
            if tableColumn!.identifier.rawValue == Person.namePropertyKey {
                person.name = value
                
                document.modifyPerson(identifier: person.identifier, properties: [Person.namePropertyKey : .string(value)])
            } else if tableColumn!.identifier.rawValue == Person.weightPropertyKey {
                if let weight = Int(value) {
                    person.weight = weight
                    document.modifyPerson(identifier: person.identifier, properties: [Person.weightPropertyKey : .int(weight)])
                }
            } else if tableColumn!.identifier.rawValue == Person.agePropertyKey {
                if let age = Int(value) {
                    person.age = age
                    document.modifyPerson(identifier: person.identifier, properties: [Person.agePropertyKey : .int(age)])
                }
            }
        }
    }
}
