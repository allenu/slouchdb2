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

public enum PushLocalResponse {
    case success(version: String)
    case failure(reason: RemoteRequestFailureReason)
}

public struct FetchedJournalAndVersion {
    public let journal: Journal
    public let version: String
    public init(journal: Journal, version: String) {
        self.journal = journal
        self.version = version
    }
}

public enum FetchJournalsResponse {
    case success(journalsAndVersions: [FetchedJournalAndVersion])
    case failure(reason: RemoteRequestFailureReason)
}

public enum FetchRemoteJournalVersionsResponse {
    case success(versions: [String : String])
    case failure(reason: RemoteRequestFailureReason)
}

public protocol RemoteSessionStore: class {
    func fetchRemoteJournalVersions(completionHandler: @escaping (FetchRemoteJournalVersionsResponse) -> Void)

    func push(localJournal: Journal, completionHandler: @escaping (PushLocalResponse) -> Void)
    
    func fetchJournals(identifiers: [String], completionHandler: @escaping (FetchJournalsResponse) -> Void)
}
