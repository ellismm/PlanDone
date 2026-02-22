sequenceDiagram
  actor User
  participant UI
  participant Repo
  participant LocalDB
  participant Outbox
  participant Sync
  participant Firestore

  User->>UI: Drag item
  UI->>Repo: moveItem()
  Repo->>LocalDB: Update item locally
  Repo->>Outbox: Queue operation

  Note over User: UI updates immediately (optimistic)

  Sync->>Outbox: Read queued ops
  Sync->>Firestore: Apply update
  Firestore-->>Sync: Ack
  Sync->>LocalDB: Mark synced