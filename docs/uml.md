classDiagram
  direction LR

  class User {
    uid
    displayName
    email
    createdAt
  }

  class Board {
    boardId
    name
    ownerId
    createdAt
    updatedAt
  }

  class BoardMember {
    boardId
    userId
    role
    joinedAt
  }

  class Column {
    columnId
    boardId
    name
    orderIndex
  }

  class WorkItem {
    itemId
    boardId
    title
    type
    parentId
    columnId
    orderKey
    startAt
    dueAt
    completedAt
    archived
    createdAt
    updatedAt
  }

  Board "1" --> "*" Column
  Board "1" --> "*" WorkItem
  Board "1" --> "*" BoardMember
  WorkItem "*" --> "0..1" WorkItem : parent