TODOs

- [x] Add support for housing multiple types in a single database
    - [x] Add should specify type
    - [x] Diff should supply optional type
    - [x] objects() should take type property

- [ ] Improve object reading
    - [ ] in a Snapshot, group objects by type for easy fetching of all objects of a type (no filtering required)
          - make it so that Database.object(type:) uses an in-mem grouping of objects by type

- [ ] Add object deletion
    - [ ] Add diff command to un-delete an entry

- [x] Move merging into Session
    - [x] Delete remoteJournalMetadata, remoteJournals, and tailSnapshots from Document and use Session's instead
    - [x] Should have a RemoteSlouchDBSource protocol
        - func fetchRemoteMetadata(completionHandler: @escaping (FetchMetadataResponse))
            - return a list of metadata files
        - func pushLocal(metadata:, journal:, completionHandler: )
        - func fetchRemoteJournals(journalIdentifiers:, completionHandler: @escaping (FetchRemoteJournalsResponse))
    - [x] Be sure to save "cache" folder
    - [x] Be sure to save "remote" folder

    - as a policy, always do save() on a Session before starting sync

- [x] Add basic database controller logic
    - [x] Convert files to in-mem representation
    - [x] Convert in-mem representation to files

- [ ] Should "modify" mean "if entry doesn't exist, create it"? We could still have "add" commands, but we can loosen
      what "modify" means so it means update if already there and add if not already there...

- [ ] Adding an object with existing id should be a no-op
    - this will allow having pre-generated content to be added by multiple nodes and not have to worry about multiple copies

- [ ] Add dictionary and array types to JSONValue

- [ ] Handle case where we "cycle" our journal to save on pushing large files
    - [ ] Should we consider any local journals not yet pushed to the cloud?
        - We may need a list of ALL local journals and not just the current one
        - Go through all local journals when determining what to push and push all those that aren't in the cloud yet

- [x] Gracefully handle case where remote updates an entry that some other database already deleted in the past
    - Do not update if object doesn't exist

- [x] merge() should produce intermediate snapshots
- [ ] Add tests for tailSnapshots generated

- [ ] BUG/DESIGN ISSUE: What happens if we remove contents remotely and do a sync and our local Doc has a lot
    of metadata that has since been deleted remotely.... We end up keeping all the previous metadata that
    doesn't exist remotely

    - [ ] Just delete local data if it's no longer in remote ??

- [ ] Should add ability to "replay" the entire database from scratch

- [ ] How do we deal with a list of all database objects?
    - i.e. for showing in a table
    - How we reduce work to resync everything?

    - One solution: sort all database objects by time/SourceIdentifier/ObjectIdentifier
        - i.e. sort by creation date first
        - if same date, sort by source database next
        - if same database, sort by UUID of object

        - when syncing, keep track of the following
            - insert object at index of existing snapshot of objects
            - remove object at index

        - this way, we can play back the modifications onto a table

