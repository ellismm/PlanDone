const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const projectId = 'plandone-rules-test';
const firestoreEmulatorPort = 8085;

let testEnv;

function boardRef(db, boardId) {
  return db.collection('boards').doc(boardId);
}

function memberRef(db, boardId, uid) {
  return boardRef(db, boardId).collection('members').doc(uid);
}

function columnRef(db, boardId, columnId) {
  return boardRef(db, boardId).collection('columns').doc(columnId);
}

function workItemRef(db, boardId, itemId) {
  return boardRef(db, boardId).collection('workItems').doc(itemId);
}

function userDeviceRef(db, uid, deviceId) {
  return db.collection('users').doc(uid).collection('devices').doc(deviceId);
}

async function seedBoard({
  boardId,
  ownerId = 'owner-1',
  extraMembers = [],
  includeDefaultColumn = true,
}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('boards').doc(boardId).set({
      boardId,
      name: `Board ${boardId}`,
      ownerId,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
      updatedAtMicros: 100,
      validationSettings: {
        requireParentForProjects: false,
        requireParentForTasks: false,
        requireParentForActions: false,
        enforceParentTypeOrder: false,
      },
    });

    await db
      .collection('boards')
      .doc(boardId)
      .collection('members')
      .doc(ownerId)
      .set({
        boardId,
        userId: ownerId,
        role: 'owner',
        joinedAt: '2026-01-01T00:00:00.000Z',
        joinedAtEpochMillis: 1735689600000,
      });

    for (const member of extraMembers) {
      await db
        .collection('boards')
        .doc(boardId)
        .collection('members')
        .doc(member.userId)
        .set({
          boardId,
          userId: member.userId,
          role: member.role,
          joinedAt: member.joinedAt ?? '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis:
            member.joinedAtEpochMillis ?? 1735689600000,
        });
    }

    if (includeDefaultColumn) {
      await db
        .collection('boards')
        .doc(boardId)
        .collection('columns')
        .doc('c-todo')
        .set({
          boardId,
          columnId: 'c-todo',
          name: 'To Do',
          orderIndex: 0,
        });
    }
  });
}

function expect(name, fn) {
  return { name, fn };
}

async function run() {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: firestoreEmulatorPort,
      rules: fs.readFileSync(path.join(process.cwd(), 'firestore.rules'), 'utf8'),
    },
  });

  const tests = [
    expect('owner can rediscover owned boards with an ownerId query', async () => {
      await seedBoard({ boardId: 'b-owned-a', ownerId: 'owner-discovery' });
      await seedBoard({ boardId: 'b-owned-b', ownerId: 'owner-discovery' });
      await seedBoard({ boardId: 'b-not-owned', ownerId: 'other-owner' });

      const owner = testEnv.authenticatedContext('owner-discovery');
      const snapshot = await assertSucceeds(
        owner
          .firestore()
          .collection('boards')
          .where('ownerId', '==', 'owner-discovery')
          .get(),
      );

      const ids = snapshot.docs.map((doc) => doc.id).sort();
      if (JSON.stringify(ids) !== JSON.stringify(['b-owned-a', 'b-owned-b'])) {
        throw new Error(`Unexpected discovered board ids: ${ids.join(', ')}`);
      }
    }),

    expect('owner cannot broadly list boards across owners', async () => {
      await seedBoard({ boardId: 'b-list-owned', ownerId: 'owner-list' });
      await seedBoard({ boardId: 'b-list-other', ownerId: 'other-list-owner' });

      const owner = testEnv.authenticatedContext('owner-list');
      await assertFails(owner.firestore().collection('boards').get());
    }),

    expect('user can rediscover only own memberships with a collection-group query', async () => {
      await seedBoard({
        boardId: 'b-membership-owned',
        ownerId: 'membership-user',
      });
      await seedBoard({
        boardId: 'b-membership-shared',
        ownerId: 'other-membership-owner',
        extraMembers: [{ userId: 'membership-user', role: 'member' }],
      });

      const user = testEnv.authenticatedContext('membership-user');
      const snapshot = await assertSucceeds(
        user
          .firestore()
          .collectionGroup('members')
          .where('userId', '==', 'membership-user')
          .get(),
      );

      const boardIds = snapshot.docs
        .map((doc) => doc.ref.parent.parent.id)
        .sort();
      if (
        JSON.stringify(boardIds) !==
        JSON.stringify(['b-membership-owned', 'b-membership-shared'])
      ) {
        throw new Error(`Unexpected membership board ids: ${boardIds.join(', ')}`);
      }
    }),

    expect('user cannot query another user or broadly list memberships', async () => {
      await seedBoard({
        boardId: 'b-membership-private',
        extraMembers: [{ userId: 'membership-private-user', role: 'member' }],
      });

      const outsider = testEnv.authenticatedContext('membership-outsider');
      const memberships = outsider.firestore().collectionGroup('members');
      await assertFails(
        memberships
          .where('userId', '==', 'membership-private-user')
          .get(),
      );
      await assertFails(memberships.get());
    }),

    expect('viewer cannot write workItems', async () => {
      await seedBoard({
        boardId: 'b-viewer',
        extraMembers: [{ userId: 'viewer-1', role: 'viewer' }],
      });

      const viewer = testEnv.authenticatedContext('viewer-1');
      const db = viewer.firestore();
      await assertFails(
        workItemRef(db, 'b-viewer', 'w-1').set({
          boardId: 'b-viewer',
          itemId: 'w-1',
          title: 'Should fail',
          type: 'task',
          columnId: 'c-todo',
        }),
      );
    }),

    expect('member can write workItems but cannot update board doc', async () => {
      await seedBoard({
        boardId: 'b-member',
        extraMembers: [{ userId: 'member-1', role: 'member' }],
      });

      const member = testEnv.authenticatedContext('member-1');
      const db = member.firestore();
      await assertSucceeds(
        workItemRef(db, 'b-member', 'w-1').set({
          boardId: 'b-member',
          itemId: 'w-1',
          title: 'Allowed item',
          type: 'task',
          columnId: 'c-todo',
        }),
      );

      await assertFails(
        boardRef(db, 'b-member').update({
          name: 'Member should not rename board',
          boardId: 'b-member',
          ownerId: 'owner-1',
        }),
      );
    }),

    expect('admin can manage members', async () => {
      await seedBoard({
        boardId: 'b-admin',
        extraMembers: [{ userId: 'admin-1', role: 'admin' }],
      });

      const admin = testEnv.authenticatedContext('admin-1');
      const db = admin.firestore();
      await assertSucceeds(
        memberRef(db, 'b-admin', 'user-new').set({
          boardId: 'b-admin',
          userId: 'user-new',
          role: 'viewer',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );

      await assertSucceeds(
        memberRef(db, 'b-admin', 'user-new').update({
          boardId: 'b-admin',
          userId: 'user-new',
          role: 'member',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );
    }),

    expect('admin cannot create a second owner membership', async () => {
      await seedBoard({
        boardId: 'b-admin-owner-create',
        extraMembers: [{ userId: 'admin-owner-create', role: 'admin' }],
      });

      const admin = testEnv.authenticatedContext('admin-owner-create');
      const db = admin.firestore();
      await assertFails(
        memberRef(db, 'b-admin-owner-create', 'user-new-owner').set({
          boardId: 'b-admin-owner-create',
          userId: 'user-new-owner',
          role: 'owner',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );
    }),

    expect('admin cannot promote an existing member to owner', async () => {
      await seedBoard({
        boardId: 'b-admin-owner-promote',
        extraMembers: [
          { userId: 'admin-owner-promote', role: 'admin' },
          { userId: 'member-owner-target', role: 'member' },
        ],
      });

      const admin = testEnv.authenticatedContext('admin-owner-promote');
      const db = admin.firestore();
      await assertFails(
        memberRef(db, 'b-admin-owner-promote', 'member-owner-target').update({
          boardId: 'b-admin-owner-promote',
          userId: 'member-owner-target',
          role: 'owner',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );
    }),

    expect('board owner cannot grant owner role to another member', async () => {
      await seedBoard({
        boardId: 'b-owner-grant',
        extraMembers: [{ userId: 'member-owner-grant', role: 'member' }],
      });

      const owner = testEnv.authenticatedContext('owner-1');
      const db = owner.firestore();
      await assertFails(
        memberRef(db, 'b-owner-grant', 'member-owner-grant').update({
          boardId: 'b-owner-grant',
          userId: 'member-owner-grant',
          role: 'owner',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );
    }),

    expect('admin cannot delete board (owner-only action)', async () => {
      await seedBoard({
        boardId: 'b-admin-delete',
        extraMembers: [{ userId: 'admin-3', role: 'admin' }],
      });

      const admin = testEnv.authenticatedContext('admin-3');
      const db = admin.firestore();
      await assertFails(boardRef(db, 'b-admin-delete').delete());
    }),

    expect('non-owner uid with legacy owner role cannot delete board', async () => {
      await seedBoard({
        boardId: 'b-legacy-extra-owner',
        extraMembers: [{ userId: 'legacy-extra-owner', role: 'owner' }],
      });

      const extraOwner = testEnv.authenticatedContext('legacy-extra-owner');
      const db = extraOwner.firestore();
      await assertFails(boardRef(db, 'b-legacy-extra-owner').delete());
    }),

    expect('board owner uid can delete board', async () => {
      await seedBoard({ boardId: 'b-owner-delete' });

      const owner = testEnv.authenticatedContext('owner-1');
      const db = owner.firestore();
      await assertSucceeds(boardRef(db, 'b-owner-delete').delete());
    }),

    expect('member can remove own membership from a shared board', async () => {
      await seedBoard({
        boardId: 'b-member-leave',
        extraMembers: [{ userId: 'member-leave', role: 'member' }],
      });

      const member = testEnv.authenticatedContext('member-leave');
      const db = member.firestore();
      await assertSucceeds(
        memberRef(db, 'b-member-leave', 'member-leave').delete(),
      );
    }),

    expect('owner cannot remove owner membership without deleting board', async () => {
      await seedBoard({ boardId: 'b-owner-member-only-delete' });

      const owner = testEnv.authenticatedContext('owner-1');
      const db = owner.firestore();
      await assertFails(
        memberRef(db, 'b-owner-member-only-delete', 'owner-1').delete(),
      );
    }),

    expect('owner can atomically delete owner membership with board', async () => {
      await seedBoard({ boardId: 'b-owner-final-delete' });

      const owner = testEnv.authenticatedContext('owner-1');
      const db = owner.firestore();
      const batch = db.batch();
      batch.delete(
        memberRef(db, 'b-owner-final-delete', 'owner-1'),
      );
      batch.delete(boardRef(db, 'b-owner-final-delete'));
      await assertSucceeds(batch.commit());
    }),

    expect('non-member cannot read board', async () => {
      await seedBoard({ boardId: 'b-private' });
      const outsider = testEnv.authenticatedContext('outsider-1');
      const db = outsider.firestore();
      await assertFails(boardRef(db, 'b-private').get());
    }),

    expect('pending invite cannot modify items until accepted', async () => {
      await seedBoard({
        boardId: 'b-pending',
        extraMembers: [
          {
            userId: 'pending-1',
            role: 'member',
            joinedAt: '1970-01-01T00:00:00.000Z',
            joinedAtEpochMillis: 0,
          },
        ],
      });

      const pendingUser = testEnv.authenticatedContext('pending-1');
      const db = pendingUser.firestore();
      await assertFails(
        workItemRef(db, 'b-pending', 'w-1').set({
          boardId: 'b-pending',
          itemId: 'w-1',
          title: 'Blocked until invite accepted',
          type: 'task',
          columnId: 'c-todo',
        }),
      );

      await assertSucceeds(
        memberRef(db, 'b-pending', 'pending-1').update({
          boardId: 'b-pending',
          userId: 'pending-1',
          role: 'member',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );

      await assertSucceeds(
        workItemRef(db, 'b-pending', 'w-2').set({
          boardId: 'b-pending',
          itemId: 'w-2',
          title: 'Allowed after invite accepted',
          type: 'task',
          columnId: 'c-todo',
        }),
      );
    }),

    expect('pending invite cannot escalate own role while accepting invite', async () => {
      await seedBoard({
        boardId: 'b-pending-role',
        extraMembers: [
          {
            userId: 'pending-role-1',
            role: 'viewer',
            joinedAt: '1970-01-01T00:00:00.000Z',
            joinedAtEpochMillis: 0,
          },
        ],
      });

      const pendingUser = testEnv.authenticatedContext('pending-role-1');
      const db = pendingUser.firestore();
      await assertFails(
        memberRef(db, 'b-pending-role', 'pending-role-1').update({
          boardId: 'b-pending-role',
          userId: 'pending-role-1',
          role: 'admin',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );
    }),

    expect('owner role cannot be downgraded or removed', async () => {
      await seedBoard({
        boardId: 'b-owner-lock',
        extraMembers: [{ userId: 'admin-2', role: 'admin' }],
      });

      const admin = testEnv.authenticatedContext('admin-2');
      const db = admin.firestore();
      await assertFails(
        memberRef(db, 'b-owner-lock', 'owner-1').update({
          boardId: 'b-owner-lock',
          userId: 'owner-1',
          role: 'admin',
          joinedAt: '2026-01-01T00:00:00.000Z',
          joinedAtEpochMillis: 1735689600000,
        }),
      );
      await assertFails(memberRef(db, 'b-owner-lock', 'owner-1').delete());
    }),

    expect('board owner can create board + owner member in same request batch', async () => {
      const owner = testEnv.authenticatedContext('owner-bootstrap');
      const db = owner.firestore();
      const batch = db.batch();
      const board = db.collection('boards').doc('b-bootstrap');
      const ownerMember = board.collection('members').doc('owner-bootstrap');
      const operationMarker = board.collection('_appliedOps').doc('op-bootstrap');

      batch.set(board, {
        boardId: 'b-bootstrap',
        name: 'Bootstrap board',
        ownerId: 'owner-bootstrap',
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
        updatedAtMicros: 100,
        validationSettings: {
          requireParentForProjects: false,
          requireParentForTasks: false,
          requireParentForActions: false,
          enforceParentTypeOrder: false,
        },
      });

      batch.set(ownerMember, {
        boardId: 'b-bootstrap',
        userId: 'owner-bootstrap',
        role: 'owner',
        joinedAt: '2026-01-01T00:00:00.000Z',
        joinedAtEpochMillis: 1735689600000,
      });

      batch.set(operationMarker, {
        operationId: 'op-bootstrap',
        entity: 'board',
        entityId: 'b-bootstrap',
        type: 'create',
        appliedAt: '2026-01-01T00:00:00.000Z',
      });

      await assertSucceeds(batch.commit());
    }),

    expect('board member can create _appliedOps marker', async () => {
      await seedBoard({
        boardId: 'b-op',
        extraMembers: [{ userId: 'member-op', role: 'member' }],
      });

      const member = testEnv.authenticatedContext('member-op');
      const db = member.firestore();
      await assertSucceeds(
        boardRef(db, 'b-op').collection('_appliedOps').doc('op-1').set({
          operationId: 'op-1',
          entity: 'workItem',
          entityId: 'w-1',
          type: 'create',
          appliedAt: '2026-01-01T00:00:00.000Z',
        }),
      );
    }),

    expect('board owner can delete _appliedOps during account cleanup', async () => {
      await seedBoard({ boardId: 'b-op-owner-cleanup' });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await boardRef(ctx.firestore(), 'b-op-owner-cleanup')
          .collection('_appliedOps')
          .doc('op-cleanup')
          .set({
            operationId: 'op-cleanup',
            entity: 'workItem',
            entityId: 'w-cleanup',
            type: 'create',
          });
      });

      const owner = testEnv.authenticatedContext('owner-1');
      const db = owner.firestore();
      await assertSucceeds(
        boardRef(db, 'b-op-owner-cleanup')
          .collection('_appliedOps')
          .doc('op-cleanup')
          .delete(),
      );
    }),

    expect('non-member cannot create _appliedOps marker', async () => {
      await seedBoard({ boardId: 'b-op-outsider' });

      const outsider = testEnv.authenticatedContext('outsider-op');
      const db = outsider.firestore();
      await assertFails(
        boardRef(db, 'b-op-outsider').collection('_appliedOps').doc('op-x').set({
          operationId: 'op-x',
          entity: 'workItem',
          entityId: 'w-1',
          type: 'create',
          appliedAt: '2026-01-01T00:00:00.000Z',
        }),
      );
    }),

    expect('member cannot manage board columns', async () => {
      await seedBoard({
        boardId: 'b-member-columns',
        extraMembers: [{ userId: 'member-col', role: 'member' }],
      });

      const member = testEnv.authenticatedContext('member-col');
      const db = member.firestore();
      await assertFails(
        columnRef(db, 'b-member-columns', 'c-new').set({
          boardId: 'b-member-columns',
          columnId: 'c-new',
          name: 'Blocked',
          orderIndex: 9,
        }),
      );
      await assertFails(
        columnRef(db, 'b-member-columns', 'c-todo').update({
          boardId: 'b-member-columns',
          columnId: 'c-todo',
          name: 'Renamed',
          orderIndex: 0,
        }),
      );
      await assertFails(columnRef(db, 'b-member-columns', 'c-todo').delete());
    }),

    expect('unauthenticated user cannot create board', async () => {
      const anon = testEnv.unauthenticatedContext();
      const db = anon.firestore();
      await assertFails(
        boardRef(db, 'b-anon').set({
          boardId: 'b-anon',
          name: 'Nope',
          ownerId: 'anon',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        }),
      );
    }),

    expect('admin can configure board validation settings', async () => {
      await seedBoard({
        boardId: 'b-validation',
        extraMembers: [{ userId: 'admin-validation', role: 'admin' }],
      });

      const admin = testEnv.authenticatedContext('admin-validation');
      const db = admin.firestore();
      await assertSucceeds(
        boardRef(db, 'b-validation').update({
          boardId: 'b-validation',
          name: 'Board b-validation',
          ownerId: 'owner-1',
          validationSettings: {
            requireParentForProjects: true,
            requireParentForTasks: true,
            requireParentForActions: true,
            enforceParentTypeOrder: true,
          },
        }),
      );
    }),

    expect('user can write own device token doc', async () => {
      const user = testEnv.authenticatedContext('user-device-1');
      const db = user.firestore();
      await assertSucceeds(
        userDeviceRef(db, 'user-device-1', 'device-1').set({
          token: 'fcm-token-1',
          platform: 'android',
          updatedAt: '2026-02-28T00:00:00.000Z',
        }),
      );
    }),

    expect('user cannot write another user device token doc', async () => {
      const user = testEnv.authenticatedContext('user-device-2');
      const db = user.firestore();
      await assertFails(
        userDeviceRef(db, 'user-device-owner', 'device-x').set({
          token: 'fcm-token-2',
          platform: 'android',
        }),
      );
    }),
  ];

  const failures = [];
  for (const test of tests) {
    try {
      await testEnv.clearFirestore();
      await test.fn();
      process.stdout.write(`✓ ${test.name}\n`);
    } catch (error) {
      failures.push({ name: test.name, error });
      process.stderr.write(`✗ ${test.name}\n${error}\n`);
    }
  }

  await testEnv.cleanup();

  if (failures.length > 0) {
    process.stderr.write(
      `\n${failures.length} Firestore rule test(s) failed.\n`,
    );
    process.exit(1);
  }

  process.stdout.write(`\n${tests.length} Firestore rule tests passed.\n`);
}

run().catch(async (error) => {
  process.stderr.write(`Unhandled error in firestore rules tests:\n${error}\n`);
  if (testEnv) {
    await testEnv.cleanup();
  }
  process.exit(1);
});
