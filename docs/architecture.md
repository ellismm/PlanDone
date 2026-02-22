flowchart LR

  UI[Flutter UI] --> STATE[State Layer]
  STATE --> DOMAIN[Domain Layer]
  DOMAIN --> REPO[Repository]

  REPO --> LOCALDB[Local Database]
  REPO --> OUTBOX[Outbox Queue]

  OUTBOX --> PUSH[Push to Firestore]
  PUSH --> FIRESTORE[Cloud Firestore]

  FIRESTORE --> LISTEN[Realtime Listener]
  LISTEN --> LOCALDB

  REPO --> AUTH[Firebase Auth]