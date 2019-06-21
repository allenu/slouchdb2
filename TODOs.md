TODOs

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

