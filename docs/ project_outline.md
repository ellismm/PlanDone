PlanDone — Technical Project Specification
Project Overview

PlanDone is a Flutter-based, offline-first, collaborative Kanban productivity application.

It supports:

Multiple boards

Real-time collaboration

Local-first data

Four-level work hierarchy

Customizable columns

AI-ready structured hierarchy

Architecture must NOT be redesigned without explicit instruction.

Core Architecture
Frontend

Flutter

Riverpod

Clean architecture

Layering:

UI → State → Domain → Repository → Data Sources

Data Architecture
Local-First Required

Local database (Drift recommended)

Outbox queue required

All operations:

Write to local DB

Queue operation

Sync engine pushes to Firestore

Firestore listeners hydrate local DB

Local DB is source of truth.

Conflict resolution:

Last Write Wins (v1)

Backend

Firebase Auth (Email/Password + Google)

Cloud Firestore

Firestore Security Rules

Realtime listeners

Work Hierarchy

Four full types:

Goal

Project

Task

Action

Rules:

Any item can have a parent

Any item can move across columns

Title is the only required field

Validation rules configurable per board

Default board filter:

Show Tasks only

WorkItem Fields

Required:

title

Optional:

type

parentId

columnId

description

assigneeIds

startAt

dueAt

completedAt

tags

archived

CompletedAt behavior:

Set when moved to Done

Cleared when moved out of Done

Due date behavior:

Visual indicator if overdue

No automatic status changes

Boards

Features:

Multiple boards per user

Users can create boards

Members with roles

Standard column customization:

Rename

Add/remove

Reorder

Firestore Structure
users/{uid}
boards/{boardId}
boards/{boardId}/members/{uid}
boards/{boardId}/columns/{columnId}
boards/{boardId}/workItems/{itemId}
Security Rules Philosophy

Must be authenticated

Must be board member

Role determines permissions

Viewers = read only

Members = modify work items

Admin/Owner = manage board & members

Offline Strategy

Local DB mirrors Firestore.

Outbox operations:

create

update

delete

move

reorder

Sync engine:

Retries on reconnect

Idempotent operations

Marks local records as synced

Future AI Integration

System must allow:

User input:
"Break this goal into structured work."

AI output:

Generate nested Goals/Projects/Tasks/Actions

Insert into local DB

Allow user review before commit

Hierarchy must remain flexible.

Milestone Plan
Phase 1

Auth

Board creation

Local DB integration

Basic Kanban UI (no sync yet)

Phase 2

Outbox queue

Firestore sync

Realtime updates

Phase 3

Member invites

Role permissions

Filtering

Validation rules

Phase 4

AI breakdown feature

Advanced views

Activity log

Non-Negotiables

Must remain offline-first

Must preserve 4-level hierarchy

Must not enforce enterprise complexity

Must remain AI-ready

Must remain SaaS-scalable