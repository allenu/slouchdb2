//
//  FileBasedRemoteSessionStore.swift
//  PeopleApp
//
//  Created by Allen Ussher on 7/24/19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import Foundation
import SlouchDB2

class FileBasedRemoteSessionStore: RemoteSessionStore {
    
    let remoteFolderUrl: URL
    let decoder: JSONDecoder
    
    init(remoteFolderUrl: URL) {
        self.remoteFolderUrl = remoteFolderUrl
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func fetchNewMetadata(existingMetadata: [String : JournalMetadata], completionHandler: @escaping (FetchNewMetadataResponse) -> Void) {
        
        var newMetadata: [String : JournalMetadata] = [:]
        
        let fileEnumerator = FileManager.default.enumerator(at: remoteFolderUrl, includingPropertiesForKeys: nil)
        while let element = fileEnumerator?.nextObject() {
            if let fileURL = element as? URL {
                if fileURL.isFileURL && fileURL.lastPathComponent.hasSuffix(".metadata" ) {
                    let data = try! Data(contentsOf: fileURL)
                    let metadata: JournalMetadata = try! decoder.decode(JournalMetadata.self, from: data)
                    
                    if let localCopyOfRemoteMetadata = existingMetadata[metadata.identifier] {
                        if localCopyOfRemoteMetadata.diffCount != metadata.diffCount {
                            newMetadata[metadata.identifier] = metadata
                        }
                    } else {
                        newMetadata[metadata.identifier] = metadata
                    }
                }
            }
        }
        
        let response = FetchNewMetadataResponse.success(metadata: newMetadata)
        completionHandler(response)
    }
    
    func push(localJournal: Journal, localMetadata: JournalMetadata, completionHandler: @escaping (PushLocalResponse) -> Void) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let metadataData = try! encoder.encode(localMetadata)
        let journalData = try! encoder.encode(localJournal)
        
        let localIdentifier = localJournal.identifier
        
        let localMetadataFilename = "\(localIdentifier).metadata"
        let remoteLocalMetadataURL: URL = remoteFolderUrl.appendingPathComponent(localMetadataFilename)
        try! metadataData.write(to: remoteLocalMetadataURL, options: [])
        
        let localJournalFilename = "\(localIdentifier).journal"
        let remoteLocalJournalURL: URL = remoteFolderUrl.appendingPathComponent(localJournalFilename)
        try! journalData.write(to: remoteLocalJournalURL, options: [])
        
        completionHandler(.success)
    }
    
    func fetchJournals(identifiers: [String], completionHandler: @escaping (FetchJournalsResponse) -> Void) {
        
        var fetchedJournals: [Journal] = []
        var succeeded = true
        
        identifiers.forEach { identifier in
            guard succeeded else { return }
            
            let fetchedRemoteJournalURL = remoteFolderUrl.appendingPathComponent("\(identifier).journal")
            if let fetchedRemoteJournalData = try? Data(contentsOf: fetchedRemoteJournalURL) {
                let fetchedRemoteJournal = try! decoder.decode(Journal.self, from: fetchedRemoteJournalData)
                
                fetchedJournals.append(fetchedRemoteJournal)
            } else {
                // Failed. Inconsistency in files. Should we fail or just assume it was deleted and act
                // like nothing happened?
                succeeded = false
            }
        }

        if succeeded {
            completionHandler(.success(journals: fetchedJournals))
        } else {
            completionHandler(.failure(reason: .serverError))
        }
    }
}
