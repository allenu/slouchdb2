//
//  RemoteSessionStore.swift
//  Pods-PeopleApp
//
//  Created by Allen Ussher on 7/24/19.
//

import Foundation

public enum RemoteRequestFailureReason {
    case networkError
    case unauthorized
    case serverError
    case timeout
}

public enum FetchNewMetadataResponse {
    case success(metadata: [String : JournalMetadata])
    case failure(reason: RemoteRequestFailureReason)
}

public enum PushLocalResponse {
    case success
    case failure(reason: RemoteRequestFailureReason)
}

public enum FetchJournalsResponse {
    case success(journals: [Journal])
    case failure(reason: RemoteRequestFailureReason)
}

public protocol RemoteSessionStore: class {
    // Get metadata that is newer than what we have already
    func fetchNewMetadata(existingMetadata: [String : JournalMetadata], completionHandler: @escaping (FetchNewMetadataResponse) -> Void)
    
    func push(localJournal: Journal, localMetadata: JournalMetadata, completionHandler: @escaping (PushLocalResponse) -> Void)
    
    func fetchJournals(identifiers: [String], completionHandler: @escaping (FetchJournalsResponse) -> Void)
}
