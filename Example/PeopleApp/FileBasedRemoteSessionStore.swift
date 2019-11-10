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
    
    func push(localJournal: Journal, completionHandler: @escaping (PushLocalResponse) -> Void) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let journalData = try! encoder.encode(localJournal)
        
        let localIdentifier = localJournal.identifier
        
        let localJournalFilename = "\(localIdentifier).journal"
        let remoteLocalJournalURL: URL = remoteFolderUrl.appendingPathComponent(localJournalFilename)
        try! journalData.write(to: remoteLocalJournalURL, options: [])
        
        // Get remote file version
        var newVersion: String = ""
        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: remoteLocalJournalURL.path) as [FileAttributeKey : Any] {
            if let lastModifiedDate = fileAttributes[FileAttributeKey.modificationDate] as? Date {
                print("lastModifiedDate: \(lastModifiedDate)")
                let dateFormatter = ISO8601DateFormatter()
                newVersion = dateFormatter.string(from: lastModifiedDate)
            } else {
                assertionFailure()
            }
        } else {
            assertionFailure()
        }

        completionHandler(.success(version: newVersion))
    }
    
    func fetchRemoteJournalVersions(completionHandler: @escaping (FetchRemoteJournalVersionsResponse) -> Void) {
        // Enumerate folder and get file version
        
        var newVendorVersion: [String : String] = [:]
        
        let fileEnumerator = FileManager.default.enumerator(at: remoteFolderUrl, includingPropertiesForKeys: nil)
        while let element = fileEnumerator?.nextObject() {
            if let fileURL = element as? URL {
                if fileURL.isFileURL && fileURL.lastPathComponent.hasSuffix(".journal" ) {
                    let journalIdentifier = fileURL.lastPathComponent.replacingOccurrences(of: ".journal", with: "")

                    if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) as [FileAttributeKey : Any] {
                        if let lastModifiedDate = fileAttributes[FileAttributeKey.modificationDate] as? Date {
                            print("lastModifiedDate: \(lastModifiedDate)")
                            let dateFormatter = ISO8601DateFormatter()
                            let version = dateFormatter.string(from: lastModifiedDate)
                            
                            newVendorVersion[journalIdentifier] = version
                        } else {
                            assertionFailure()
                        }
                    } else {
                        assertionFailure()
                    }
                }
            }
        }
        
        let response = FetchRemoteJournalVersionsResponse.success(versions: newVendorVersion)
        completionHandler(response)
    }
    
    func fetchJournals(identifiers: [String], completionHandler: @escaping (FetchJournalsResponse) -> Void) {
        
        var fetchedJournalsAndVersions: [FetchedJournalAndVersion] = []
        var succeeded = true
        
        identifiers.forEach { identifier in
            guard succeeded else { return }
            
            let fetchedRemoteJournalURL = remoteFolderUrl.appendingPathComponent("\(identifier).journal")
            if let fetchedRemoteJournalData = try? Data(contentsOf: fetchedRemoteJournalURL) {
                let fetchedRemoteJournal = try! decoder.decode(Journal.self, from: fetchedRemoteJournalData)
                
                
                // TODO: Use date of file here as version
                let version: String
                if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: fetchedRemoteJournalURL.path) as [FileAttributeKey : Any] {
                    if let lastModifiedDate = fileAttributes[FileAttributeKey.modificationDate] as? Date {
                        print("lastModifiedDate: \(lastModifiedDate)")
                        let dateFormatter = ISO8601DateFormatter()
                        version = dateFormatter.string(from: lastModifiedDate)
                    } else {
                        print("Could not load lastModifiedDate")
                        version = "not-found"
                    }
                } else {
                    version = "not-found"
                }
                
                let fetchedJournalAndVersion = FetchedJournalAndVersion(journal: fetchedRemoteJournal,
                                                                        version: version)
                
                fetchedJournalsAndVersions.append(fetchedJournalAndVersion)
            } else {
                // Failed. Inconsistency in files. Should we fail or just assume it was deleted and act
                // like nothing happened?
                succeeded = false
            }
        }

        if succeeded {
            completionHandler(.success(journalsAndVersions: fetchedJournalsAndVersions))
        } else {
            completionHandler(.failure(reason: .serverError))
        }
    }
}
