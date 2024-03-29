# SlouchDB2

** WARNING: This is still very much a work in progress. **

This is a rewrite of SlouchDB https://github.com/allenu/slouchdb

SlouchDB2 is a journal-based NoSQL-like, distributed single-user database for
Apple-based projects (Mac and iOS).

* It's journal-based in that all changes to objects (adding, removing, modifying
  properties) are stored as diff commands. A snapshot of the database can be
  generated by playing back a journal.

* It's NoSQL-like in that it stores arbitrary documents, each which is a set of
  key-value pairs. The keys are strings and the values are JSON-supported types.

* It's distributed in that each device that contributes to modifications to the 
  database writes to its own journal file. Each device is responsible for 
  maintaining a snapshot of the current state of the database. This database state
  is not shared; only the journals are shared.

* It's single-user in that because of how the journals are stored and sync'ed, it
  is not appropriate for multiple users who are able to modify entries simultaneously
  from different devices. The assumption of this database that only a single user
  with multiple devices is making modifications to the database. Therefore, there
  is a low likelihood of conflicts when two devices make a modification to the same
  object.

The goals of rewriting SlouchDB as SlouchDB2 are as follows:

* Simplify the original implementation. The original was written in a more complex,
  imperative style in places. Since then, I've moved to writing in a more functional,
  declarative style, which I find leads to easier to reason about code that is more
  concise and has fewer bugs.

* Make it easier to use by applications. This generally means targeting the mot
  common scenarios. The original implementation was more open-ended where it may not
  have been needed. This contributed to its complexity and also made it necessary to
  understand the model more than needed by clients. 

* Design for performance. The original implementation made use of some caching, but
  it didn't target common scenarios which would arise out of normal sync scenarios.
  That is, it did not fully consider that syncing across devices may not be done on 
  a regular schedule, and that snapshots of the database may not have been optimized
  for this irregular schedule.

* Better documentation overall.

