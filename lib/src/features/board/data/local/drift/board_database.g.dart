// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'board_database.dart';

// ignore_for_file: type=lint
class $BoardsTable extends Boards with TableInfo<$BoardsTable, Board> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _boardIdMeta =
      const VerificationMeta('boardId');
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
      'board_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [boardId, name, ownerId, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'boards';
  @override
  VerificationContext validateIntegrity(Insertable<Board> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('board_id')) {
      context.handle(_boardIdMeta,
          boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta));
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {boardId};
  @override
  Board map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Board(
      boardId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}board_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $BoardsTable createAlias(String alias) {
    return $BoardsTable(attachedDatabase, alias);
  }
}

class Board extends DataClass implements Insertable<Board> {
  final String boardId;
  final String name;
  final String ownerId;
  final int createdAt;
  final int updatedAt;
  const Board(
      {required this.boardId,
      required this.name,
      required this.ownerId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['board_id'] = Variable<String>(boardId);
    map['name'] = Variable<String>(name);
    map['owner_id'] = Variable<String>(ownerId);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  BoardsCompanion toCompanion(bool nullToAbsent) {
    return BoardsCompanion(
      boardId: Value(boardId),
      name: Value(name),
      ownerId: Value(ownerId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Board.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Board(
      boardId: serializer.fromJson<String>(json['boardId']),
      name: serializer.fromJson<String>(json['name']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'boardId': serializer.toJson<String>(boardId),
      'name': serializer.toJson<String>(name),
      'ownerId': serializer.toJson<String>(ownerId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Board copyWith(
          {String? boardId,
          String? name,
          String? ownerId,
          int? createdAt,
          int? updatedAt}) =>
      Board(
        boardId: boardId ?? this.boardId,
        name: name ?? this.name,
        ownerId: ownerId ?? this.ownerId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Board copyWithCompanion(BoardsCompanion data) {
    return Board(
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      name: data.name.present ? data.name.value : this.name,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Board(')
          ..write('boardId: $boardId, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(boardId, name, ownerId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Board &&
          other.boardId == this.boardId &&
          other.name == this.name &&
          other.ownerId == this.ownerId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BoardsCompanion extends UpdateCompanion<Board> {
  final Value<String> boardId;
  final Value<String> name;
  final Value<String> ownerId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const BoardsCompanion({
    this.boardId = const Value.absent(),
    this.name = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoardsCompanion.insert({
    required String boardId,
    required String name,
    required String ownerId,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : boardId = Value(boardId),
        name = Value(name),
        ownerId = Value(ownerId),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Board> custom({
    Expression<String>? boardId,
    Expression<String>? name,
    Expression<String>? ownerId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (boardId != null) 'board_id': boardId,
      if (name != null) 'name': name,
      if (ownerId != null) 'owner_id': ownerId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoardsCompanion copyWith(
      {Value<String>? boardId,
      Value<String>? name,
      Value<String>? ownerId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return BoardsCompanion(
      boardId: boardId ?? this.boardId,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardsCompanion(')
          ..write('boardId: $boardId, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BoardColumnsTable extends BoardColumns
    with TableInfo<$BoardColumnsTable, BoardColumn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardColumnsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _columnIdMeta =
      const VerificationMeta('columnId');
  @override
  late final GeneratedColumn<String> columnId = GeneratedColumn<String>(
      'column_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _boardIdMeta =
      const VerificationMeta('boardId');
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
      'board_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _orderIndexMeta =
      const VerificationMeta('orderIndex');
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
      'order_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [columnId, boardId, name, orderIndex];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'board_columns';
  @override
  VerificationContext validateIntegrity(Insertable<BoardColumn> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('column_id')) {
      context.handle(_columnIdMeta,
          columnId.isAcceptableOrUnknown(data['column_id']!, _columnIdMeta));
    } else if (isInserting) {
      context.missing(_columnIdMeta);
    }
    if (data.containsKey('board_id')) {
      context.handle(_boardIdMeta,
          boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta));
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
          _orderIndexMeta,
          orderIndex.isAcceptableOrUnknown(
              data['order_index']!, _orderIndexMeta));
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {columnId};
  @override
  BoardColumn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BoardColumn(
      columnId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}column_id'])!,
      boardId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}board_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      orderIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order_index'])!,
    );
  }

  @override
  $BoardColumnsTable createAlias(String alias) {
    return $BoardColumnsTable(attachedDatabase, alias);
  }
}

class BoardColumn extends DataClass implements Insertable<BoardColumn> {
  final String columnId;
  final String boardId;
  final String name;
  final int orderIndex;
  const BoardColumn(
      {required this.columnId,
      required this.boardId,
      required this.name,
      required this.orderIndex});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['column_id'] = Variable<String>(columnId);
    map['board_id'] = Variable<String>(boardId);
    map['name'] = Variable<String>(name);
    map['order_index'] = Variable<int>(orderIndex);
    return map;
  }

  BoardColumnsCompanion toCompanion(bool nullToAbsent) {
    return BoardColumnsCompanion(
      columnId: Value(columnId),
      boardId: Value(boardId),
      name: Value(name),
      orderIndex: Value(orderIndex),
    );
  }

  factory BoardColumn.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BoardColumn(
      columnId: serializer.fromJson<String>(json['columnId']),
      boardId: serializer.fromJson<String>(json['boardId']),
      name: serializer.fromJson<String>(json['name']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'columnId': serializer.toJson<String>(columnId),
      'boardId': serializer.toJson<String>(boardId),
      'name': serializer.toJson<String>(name),
      'orderIndex': serializer.toJson<int>(orderIndex),
    };
  }

  BoardColumn copyWith(
          {String? columnId, String? boardId, String? name, int? orderIndex}) =>
      BoardColumn(
        columnId: columnId ?? this.columnId,
        boardId: boardId ?? this.boardId,
        name: name ?? this.name,
        orderIndex: orderIndex ?? this.orderIndex,
      );
  BoardColumn copyWithCompanion(BoardColumnsCompanion data) {
    return BoardColumn(
      columnId: data.columnId.present ? data.columnId.value : this.columnId,
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      name: data.name.present ? data.name.value : this.name,
      orderIndex:
          data.orderIndex.present ? data.orderIndex.value : this.orderIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BoardColumn(')
          ..write('columnId: $columnId, ')
          ..write('boardId: $boardId, ')
          ..write('name: $name, ')
          ..write('orderIndex: $orderIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(columnId, boardId, name, orderIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardColumn &&
          other.columnId == this.columnId &&
          other.boardId == this.boardId &&
          other.name == this.name &&
          other.orderIndex == this.orderIndex);
}

class BoardColumnsCompanion extends UpdateCompanion<BoardColumn> {
  final Value<String> columnId;
  final Value<String> boardId;
  final Value<String> name;
  final Value<int> orderIndex;
  final Value<int> rowid;
  const BoardColumnsCompanion({
    this.columnId = const Value.absent(),
    this.boardId = const Value.absent(),
    this.name = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoardColumnsCompanion.insert({
    required String columnId,
    required String boardId,
    required String name,
    required int orderIndex,
    this.rowid = const Value.absent(),
  })  : columnId = Value(columnId),
        boardId = Value(boardId),
        name = Value(name),
        orderIndex = Value(orderIndex);
  static Insertable<BoardColumn> custom({
    Expression<String>? columnId,
    Expression<String>? boardId,
    Expression<String>? name,
    Expression<int>? orderIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (columnId != null) 'column_id': columnId,
      if (boardId != null) 'board_id': boardId,
      if (name != null) 'name': name,
      if (orderIndex != null) 'order_index': orderIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoardColumnsCompanion copyWith(
      {Value<String>? columnId,
      Value<String>? boardId,
      Value<String>? name,
      Value<int>? orderIndex,
      Value<int>? rowid}) {
    return BoardColumnsCompanion(
      columnId: columnId ?? this.columnId,
      boardId: boardId ?? this.boardId,
      name: name ?? this.name,
      orderIndex: orderIndex ?? this.orderIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (columnId.present) {
      map['column_id'] = Variable<String>(columnId.value);
    }
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardColumnsCompanion(')
          ..write('columnId: $columnId, ')
          ..write('boardId: $boardId, ')
          ..write('name: $name, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BoardMembersTable extends BoardMembers
    with TableInfo<$BoardMembersTable, BoardMember> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BoardMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _boardIdMeta =
      const VerificationMeta('boardId');
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
      'board_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _joinedAtMeta =
      const VerificationMeta('joinedAt');
  @override
  late final GeneratedColumn<int> joinedAt = GeneratedColumn<int>(
      'joined_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [boardId, userId, role, joinedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'board_members';
  @override
  VerificationContext validateIntegrity(Insertable<BoardMember> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('board_id')) {
      context.handle(_boardIdMeta,
          boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta));
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('joined_at')) {
      context.handle(_joinedAtMeta,
          joinedAt.isAcceptableOrUnknown(data['joined_at']!, _joinedAtMeta));
    } else if (isInserting) {
      context.missing(_joinedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {boardId, userId};
  @override
  BoardMember map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BoardMember(
      boardId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}board_id'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      joinedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}joined_at'])!,
    );
  }

  @override
  $BoardMembersTable createAlias(String alias) {
    return $BoardMembersTable(attachedDatabase, alias);
  }
}

class BoardMember extends DataClass implements Insertable<BoardMember> {
  final String boardId;
  final String userId;
  final String role;
  final int joinedAt;
  const BoardMember(
      {required this.boardId,
      required this.userId,
      required this.role,
      required this.joinedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['board_id'] = Variable<String>(boardId);
    map['user_id'] = Variable<String>(userId);
    map['role'] = Variable<String>(role);
    map['joined_at'] = Variable<int>(joinedAt);
    return map;
  }

  BoardMembersCompanion toCompanion(bool nullToAbsent) {
    return BoardMembersCompanion(
      boardId: Value(boardId),
      userId: Value(userId),
      role: Value(role),
      joinedAt: Value(joinedAt),
    );
  }

  factory BoardMember.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BoardMember(
      boardId: serializer.fromJson<String>(json['boardId']),
      userId: serializer.fromJson<String>(json['userId']),
      role: serializer.fromJson<String>(json['role']),
      joinedAt: serializer.fromJson<int>(json['joinedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'boardId': serializer.toJson<String>(boardId),
      'userId': serializer.toJson<String>(userId),
      'role': serializer.toJson<String>(role),
      'joinedAt': serializer.toJson<int>(joinedAt),
    };
  }

  BoardMember copyWith(
          {String? boardId, String? userId, String? role, int? joinedAt}) =>
      BoardMember(
        boardId: boardId ?? this.boardId,
        userId: userId ?? this.userId,
        role: role ?? this.role,
        joinedAt: joinedAt ?? this.joinedAt,
      );
  BoardMember copyWithCompanion(BoardMembersCompanion data) {
    return BoardMember(
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      userId: data.userId.present ? data.userId.value : this.userId,
      role: data.role.present ? data.role.value : this.role,
      joinedAt: data.joinedAt.present ? data.joinedAt.value : this.joinedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BoardMember(')
          ..write('boardId: $boardId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(boardId, userId, role, joinedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardMember &&
          other.boardId == this.boardId &&
          other.userId == this.userId &&
          other.role == this.role &&
          other.joinedAt == this.joinedAt);
}

class BoardMembersCompanion extends UpdateCompanion<BoardMember> {
  final Value<String> boardId;
  final Value<String> userId;
  final Value<String> role;
  final Value<int> joinedAt;
  final Value<int> rowid;
  const BoardMembersCompanion({
    this.boardId = const Value.absent(),
    this.userId = const Value.absent(),
    this.role = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BoardMembersCompanion.insert({
    required String boardId,
    required String userId,
    required String role,
    required int joinedAt,
    this.rowid = const Value.absent(),
  })  : boardId = Value(boardId),
        userId = Value(userId),
        role = Value(role),
        joinedAt = Value(joinedAt);
  static Insertable<BoardMember> custom({
    Expression<String>? boardId,
    Expression<String>? userId,
    Expression<String>? role,
    Expression<int>? joinedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (boardId != null) 'board_id': boardId,
      if (userId != null) 'user_id': userId,
      if (role != null) 'role': role,
      if (joinedAt != null) 'joined_at': joinedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BoardMembersCompanion copyWith(
      {Value<String>? boardId,
      Value<String>? userId,
      Value<String>? role,
      Value<int>? joinedAt,
      Value<int>? rowid}) {
    return BoardMembersCompanion(
      boardId: boardId ?? this.boardId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (joinedAt.present) {
      map['joined_at'] = Variable<int>(joinedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BoardMembersCompanion(')
          ..write('boardId: $boardId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkItemsTable extends WorkItems
    with TableInfo<$WorkItemsTable, WorkItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _boardIdMeta =
      const VerificationMeta('boardId');
  @override
  late final GeneratedColumn<String> boardId = GeneratedColumn<String>(
      'board_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _columnIdMeta =
      const VerificationMeta('columnId');
  @override
  late final GeneratedColumn<String> columnId = GeneratedColumn<String>(
      'column_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _assigneeIdsJsonMeta =
      const VerificationMeta('assigneeIdsJson');
  @override
  late final GeneratedColumn<String> assigneeIdsJson = GeneratedColumn<String>(
      'assignee_ids_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _startAtMeta =
      const VerificationMeta('startAt');
  @override
  late final GeneratedColumn<int> startAt = GeneratedColumn<int>(
      'start_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
      'due_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _tagsJsonMeta =
      const VerificationMeta('tagsJson');
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
      'tags_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _archivedMeta =
      const VerificationMeta('archived');
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
      'archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        itemId,
        boardId,
        title,
        type,
        parentId,
        columnId,
        description,
        assigneeIdsJson,
        startAt,
        dueAt,
        completedAt,
        tagsJson,
        archived,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_items';
  @override
  VerificationContext validateIntegrity(Insertable<WorkItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('board_id')) {
      context.handle(_boardIdMeta,
          boardId.isAcceptableOrUnknown(data['board_id']!, _boardIdMeta));
    } else if (isInserting) {
      context.missing(_boardIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('column_id')) {
      context.handle(_columnIdMeta,
          columnId.isAcceptableOrUnknown(data['column_id']!, _columnIdMeta));
    } else if (isInserting) {
      context.missing(_columnIdMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('assignee_ids_json')) {
      context.handle(
          _assigneeIdsJsonMeta,
          assigneeIdsJson.isAcceptableOrUnknown(
              data['assignee_ids_json']!, _assigneeIdsJsonMeta));
    }
    if (data.containsKey('start_at')) {
      context.handle(_startAtMeta,
          startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta));
    }
    if (data.containsKey('due_at')) {
      context.handle(
          _dueAtMeta, dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('tags_json')) {
      context.handle(_tagsJsonMeta,
          tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta));
    }
    if (data.containsKey('archived')) {
      context.handle(_archivedMeta,
          archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId};
  @override
  WorkItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkItem(
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      boardId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}board_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      columnId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}column_id'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      assigneeIdsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}assignee_ids_json'])!,
      startAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_at']),
      dueAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}due_at']),
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_at']),
      tagsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags_json'])!,
      archived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}archived'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $WorkItemsTable createAlias(String alias) {
    return $WorkItemsTable(attachedDatabase, alias);
  }
}

class WorkItem extends DataClass implements Insertable<WorkItem> {
  final String itemId;
  final String boardId;
  final String title;
  final String type;
  final String? parentId;
  final String columnId;
  final String? description;
  final String assigneeIdsJson;
  final int? startAt;
  final int? dueAt;
  final int? completedAt;
  final String tagsJson;
  final bool archived;
  final int createdAt;
  final int updatedAt;
  const WorkItem(
      {required this.itemId,
      required this.boardId,
      required this.title,
      required this.type,
      this.parentId,
      required this.columnId,
      this.description,
      required this.assigneeIdsJson,
      this.startAt,
      this.dueAt,
      this.completedAt,
      required this.tagsJson,
      required this.archived,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['board_id'] = Variable<String>(boardId);
    map['title'] = Variable<String>(title);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['column_id'] = Variable<String>(columnId);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['assignee_ids_json'] = Variable<String>(assigneeIdsJson);
    if (!nullToAbsent || startAt != null) {
      map['start_at'] = Variable<int>(startAt);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<int>(dueAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    map['tags_json'] = Variable<String>(tagsJson);
    map['archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  WorkItemsCompanion toCompanion(bool nullToAbsent) {
    return WorkItemsCompanion(
      itemId: Value(itemId),
      boardId: Value(boardId),
      title: Value(title),
      type: Value(type),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      columnId: Value(columnId),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      assigneeIdsJson: Value(assigneeIdsJson),
      startAt: startAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startAt),
      dueAt:
          dueAt == null && nullToAbsent ? const Value.absent() : Value(dueAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      tagsJson: Value(tagsJson),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WorkItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkItem(
      itemId: serializer.fromJson<String>(json['itemId']),
      boardId: serializer.fromJson<String>(json['boardId']),
      title: serializer.fromJson<String>(json['title']),
      type: serializer.fromJson<String>(json['type']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      columnId: serializer.fromJson<String>(json['columnId']),
      description: serializer.fromJson<String?>(json['description']),
      assigneeIdsJson: serializer.fromJson<String>(json['assigneeIdsJson']),
      startAt: serializer.fromJson<int?>(json['startAt']),
      dueAt: serializer.fromJson<int?>(json['dueAt']),
      completedAt: serializer.fromJson<int?>(json['completedAt']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'boardId': serializer.toJson<String>(boardId),
      'title': serializer.toJson<String>(title),
      'type': serializer.toJson<String>(type),
      'parentId': serializer.toJson<String?>(parentId),
      'columnId': serializer.toJson<String>(columnId),
      'description': serializer.toJson<String?>(description),
      'assigneeIdsJson': serializer.toJson<String>(assigneeIdsJson),
      'startAt': serializer.toJson<int?>(startAt),
      'dueAt': serializer.toJson<int?>(dueAt),
      'completedAt': serializer.toJson<int?>(completedAt),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  WorkItem copyWith(
          {String? itemId,
          String? boardId,
          String? title,
          String? type,
          Value<String?> parentId = const Value.absent(),
          String? columnId,
          Value<String?> description = const Value.absent(),
          String? assigneeIdsJson,
          Value<int?> startAt = const Value.absent(),
          Value<int?> dueAt = const Value.absent(),
          Value<int?> completedAt = const Value.absent(),
          String? tagsJson,
          bool? archived,
          int? createdAt,
          int? updatedAt}) =>
      WorkItem(
        itemId: itemId ?? this.itemId,
        boardId: boardId ?? this.boardId,
        title: title ?? this.title,
        type: type ?? this.type,
        parentId: parentId.present ? parentId.value : this.parentId,
        columnId: columnId ?? this.columnId,
        description: description.present ? description.value : this.description,
        assigneeIdsJson: assigneeIdsJson ?? this.assigneeIdsJson,
        startAt: startAt.present ? startAt.value : this.startAt,
        dueAt: dueAt.present ? dueAt.value : this.dueAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        tagsJson: tagsJson ?? this.tagsJson,
        archived: archived ?? this.archived,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  WorkItem copyWithCompanion(WorkItemsCompanion data) {
    return WorkItem(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      boardId: data.boardId.present ? data.boardId.value : this.boardId,
      title: data.title.present ? data.title.value : this.title,
      type: data.type.present ? data.type.value : this.type,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      columnId: data.columnId.present ? data.columnId.value : this.columnId,
      description:
          data.description.present ? data.description.value : this.description,
      assigneeIdsJson: data.assigneeIdsJson.present
          ? data.assigneeIdsJson.value
          : this.assigneeIdsJson,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkItem(')
          ..write('itemId: $itemId, ')
          ..write('boardId: $boardId, ')
          ..write('title: $title, ')
          ..write('type: $type, ')
          ..write('parentId: $parentId, ')
          ..write('columnId: $columnId, ')
          ..write('description: $description, ')
          ..write('assigneeIdsJson: $assigneeIdsJson, ')
          ..write('startAt: $startAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      itemId,
      boardId,
      title,
      type,
      parentId,
      columnId,
      description,
      assigneeIdsJson,
      startAt,
      dueAt,
      completedAt,
      tagsJson,
      archived,
      createdAt,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkItem &&
          other.itemId == this.itemId &&
          other.boardId == this.boardId &&
          other.title == this.title &&
          other.type == this.type &&
          other.parentId == this.parentId &&
          other.columnId == this.columnId &&
          other.description == this.description &&
          other.assigneeIdsJson == this.assigneeIdsJson &&
          other.startAt == this.startAt &&
          other.dueAt == this.dueAt &&
          other.completedAt == this.completedAt &&
          other.tagsJson == this.tagsJson &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WorkItemsCompanion extends UpdateCompanion<WorkItem> {
  final Value<String> itemId;
  final Value<String> boardId;
  final Value<String> title;
  final Value<String> type;
  final Value<String?> parentId;
  final Value<String> columnId;
  final Value<String?> description;
  final Value<String> assigneeIdsJson;
  final Value<int?> startAt;
  final Value<int?> dueAt;
  final Value<int?> completedAt;
  final Value<String> tagsJson;
  final Value<bool> archived;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const WorkItemsCompanion({
    this.itemId = const Value.absent(),
    this.boardId = const Value.absent(),
    this.title = const Value.absent(),
    this.type = const Value.absent(),
    this.parentId = const Value.absent(),
    this.columnId = const Value.absent(),
    this.description = const Value.absent(),
    this.assigneeIdsJson = const Value.absent(),
    this.startAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkItemsCompanion.insert({
    required String itemId,
    required String boardId,
    required String title,
    required String type,
    this.parentId = const Value.absent(),
    required String columnId,
    this.description = const Value.absent(),
    this.assigneeIdsJson = const Value.absent(),
    this.startAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.archived = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : itemId = Value(itemId),
        boardId = Value(boardId),
        title = Value(title),
        type = Value(type),
        columnId = Value(columnId),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<WorkItem> custom({
    Expression<String>? itemId,
    Expression<String>? boardId,
    Expression<String>? title,
    Expression<String>? type,
    Expression<String>? parentId,
    Expression<String>? columnId,
    Expression<String>? description,
    Expression<String>? assigneeIdsJson,
    Expression<int>? startAt,
    Expression<int>? dueAt,
    Expression<int>? completedAt,
    Expression<String>? tagsJson,
    Expression<bool>? archived,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (boardId != null) 'board_id': boardId,
      if (title != null) 'title': title,
      if (type != null) 'type': type,
      if (parentId != null) 'parent_id': parentId,
      if (columnId != null) 'column_id': columnId,
      if (description != null) 'description': description,
      if (assigneeIdsJson != null) 'assignee_ids_json': assigneeIdsJson,
      if (startAt != null) 'start_at': startAt,
      if (dueAt != null) 'due_at': dueAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (archived != null) 'archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkItemsCompanion copyWith(
      {Value<String>? itemId,
      Value<String>? boardId,
      Value<String>? title,
      Value<String>? type,
      Value<String?>? parentId,
      Value<String>? columnId,
      Value<String?>? description,
      Value<String>? assigneeIdsJson,
      Value<int?>? startAt,
      Value<int?>? dueAt,
      Value<int?>? completedAt,
      Value<String>? tagsJson,
      Value<bool>? archived,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return WorkItemsCompanion(
      itemId: itemId ?? this.itemId,
      boardId: boardId ?? this.boardId,
      title: title ?? this.title,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      columnId: columnId ?? this.columnId,
      description: description ?? this.description,
      assigneeIdsJson: assigneeIdsJson ?? this.assigneeIdsJson,
      startAt: startAt ?? this.startAt,
      dueAt: dueAt ?? this.dueAt,
      completedAt: completedAt ?? this.completedAt,
      tagsJson: tagsJson ?? this.tagsJson,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (boardId.present) {
      map['board_id'] = Variable<String>(boardId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (columnId.present) {
      map['column_id'] = Variable<String>(columnId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (assigneeIdsJson.present) {
      map['assignee_ids_json'] = Variable<String>(assigneeIdsJson.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<int>(startAt.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkItemsCompanion(')
          ..write('itemId: $itemId, ')
          ..write('boardId: $boardId, ')
          ..write('title: $title, ')
          ..write('type: $type, ')
          ..write('parentId: $parentId, ')
          ..write('columnId: $columnId, ')
          ..write('description: $description, ')
          ..write('assigneeIdsJson: $assigneeIdsJson, ')
          ..write('startAt: $startAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BoardDatabase extends GeneratedDatabase {
  _$BoardDatabase(QueryExecutor e) : super(e);
  $BoardDatabaseManager get managers => $BoardDatabaseManager(this);
  late final $BoardsTable boards = $BoardsTable(this);
  late final $BoardColumnsTable boardColumns = $BoardColumnsTable(this);
  late final $BoardMembersTable boardMembers = $BoardMembersTable(this);
  late final $WorkItemsTable workItems = $WorkItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [boards, boardColumns, boardMembers, workItems];
}

typedef $$BoardsTableCreateCompanionBuilder = BoardsCompanion Function({
  required String boardId,
  required String name,
  required String ownerId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$BoardsTableUpdateCompanionBuilder = BoardsCompanion Function({
  Value<String> boardId,
  Value<String> name,
  Value<String> ownerId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$BoardsTableFilterComposer
    extends Composer<_$BoardDatabase, $BoardsTable> {
  $$BoardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$BoardsTableOrderingComposer
    extends Composer<_$BoardDatabase, $BoardsTable> {
  $$BoardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ownerId => $composableBuilder(
      column: $table.ownerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$BoardsTableAnnotationComposer
    extends Composer<_$BoardDatabase, $BoardsTable> {
  $$BoardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get boardId =>
      $composableBuilder(column: $table.boardId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$BoardsTableTableManager extends RootTableManager<
    _$BoardDatabase,
    $BoardsTable,
    Board,
    $$BoardsTableFilterComposer,
    $$BoardsTableOrderingComposer,
    $$BoardsTableAnnotationComposer,
    $$BoardsTableCreateCompanionBuilder,
    $$BoardsTableUpdateCompanionBuilder,
    (Board, BaseReferences<_$BoardDatabase, $BoardsTable, Board>),
    Board,
    PrefetchHooks Function()> {
  $$BoardsTableTableManager(_$BoardDatabase db, $BoardsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> boardId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> ownerId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BoardsCompanion(
            boardId: boardId,
            name: name,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String boardId,
            required String name,
            required String ownerId,
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              BoardsCompanion.insert(
            boardId: boardId,
            name: name,
            ownerId: ownerId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BoardsTableProcessedTableManager = ProcessedTableManager<
    _$BoardDatabase,
    $BoardsTable,
    Board,
    $$BoardsTableFilterComposer,
    $$BoardsTableOrderingComposer,
    $$BoardsTableAnnotationComposer,
    $$BoardsTableCreateCompanionBuilder,
    $$BoardsTableUpdateCompanionBuilder,
    (Board, BaseReferences<_$BoardDatabase, $BoardsTable, Board>),
    Board,
    PrefetchHooks Function()>;
typedef $$BoardColumnsTableCreateCompanionBuilder = BoardColumnsCompanion
    Function({
  required String columnId,
  required String boardId,
  required String name,
  required int orderIndex,
  Value<int> rowid,
});
typedef $$BoardColumnsTableUpdateCompanionBuilder = BoardColumnsCompanion
    Function({
  Value<String> columnId,
  Value<String> boardId,
  Value<String> name,
  Value<int> orderIndex,
  Value<int> rowid,
});

class $$BoardColumnsTableFilterComposer
    extends Composer<_$BoardDatabase, $BoardColumnsTable> {
  $$BoardColumnsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get columnId => $composableBuilder(
      column: $table.columnId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnFilters(column));
}

class $$BoardColumnsTableOrderingComposer
    extends Composer<_$BoardDatabase, $BoardColumnsTable> {
  $$BoardColumnsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get columnId => $composableBuilder(
      column: $table.columnId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnOrderings(column));
}

class $$BoardColumnsTableAnnotationComposer
    extends Composer<_$BoardDatabase, $BoardColumnsTable> {
  $$BoardColumnsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get columnId =>
      $composableBuilder(column: $table.columnId, builder: (column) => column);

  GeneratedColumn<String> get boardId =>
      $composableBuilder(column: $table.boardId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => column);
}

class $$BoardColumnsTableTableManager extends RootTableManager<
    _$BoardDatabase,
    $BoardColumnsTable,
    BoardColumn,
    $$BoardColumnsTableFilterComposer,
    $$BoardColumnsTableOrderingComposer,
    $$BoardColumnsTableAnnotationComposer,
    $$BoardColumnsTableCreateCompanionBuilder,
    $$BoardColumnsTableUpdateCompanionBuilder,
    (
      BoardColumn,
      BaseReferences<_$BoardDatabase, $BoardColumnsTable, BoardColumn>
    ),
    BoardColumn,
    PrefetchHooks Function()> {
  $$BoardColumnsTableTableManager(_$BoardDatabase db, $BoardColumnsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardColumnsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardColumnsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardColumnsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> columnId = const Value.absent(),
            Value<String> boardId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> orderIndex = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BoardColumnsCompanion(
            columnId: columnId,
            boardId: boardId,
            name: name,
            orderIndex: orderIndex,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String columnId,
            required String boardId,
            required String name,
            required int orderIndex,
            Value<int> rowid = const Value.absent(),
          }) =>
              BoardColumnsCompanion.insert(
            columnId: columnId,
            boardId: boardId,
            name: name,
            orderIndex: orderIndex,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BoardColumnsTableProcessedTableManager = ProcessedTableManager<
    _$BoardDatabase,
    $BoardColumnsTable,
    BoardColumn,
    $$BoardColumnsTableFilterComposer,
    $$BoardColumnsTableOrderingComposer,
    $$BoardColumnsTableAnnotationComposer,
    $$BoardColumnsTableCreateCompanionBuilder,
    $$BoardColumnsTableUpdateCompanionBuilder,
    (
      BoardColumn,
      BaseReferences<_$BoardDatabase, $BoardColumnsTable, BoardColumn>
    ),
    BoardColumn,
    PrefetchHooks Function()>;
typedef $$BoardMembersTableCreateCompanionBuilder = BoardMembersCompanion
    Function({
  required String boardId,
  required String userId,
  required String role,
  required int joinedAt,
  Value<int> rowid,
});
typedef $$BoardMembersTableUpdateCompanionBuilder = BoardMembersCompanion
    Function({
  Value<String> boardId,
  Value<String> userId,
  Value<String> role,
  Value<int> joinedAt,
  Value<int> rowid,
});

class $$BoardMembersTableFilterComposer
    extends Composer<_$BoardDatabase, $BoardMembersTable> {
  $$BoardMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get joinedAt => $composableBuilder(
      column: $table.joinedAt, builder: (column) => ColumnFilters(column));
}

class $$BoardMembersTableOrderingComposer
    extends Composer<_$BoardDatabase, $BoardMembersTable> {
  $$BoardMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get joinedAt => $composableBuilder(
      column: $table.joinedAt, builder: (column) => ColumnOrderings(column));
}

class $$BoardMembersTableAnnotationComposer
    extends Composer<_$BoardDatabase, $BoardMembersTable> {
  $$BoardMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get boardId =>
      $composableBuilder(column: $table.boardId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get joinedAt =>
      $composableBuilder(column: $table.joinedAt, builder: (column) => column);
}

class $$BoardMembersTableTableManager extends RootTableManager<
    _$BoardDatabase,
    $BoardMembersTable,
    BoardMember,
    $$BoardMembersTableFilterComposer,
    $$BoardMembersTableOrderingComposer,
    $$BoardMembersTableAnnotationComposer,
    $$BoardMembersTableCreateCompanionBuilder,
    $$BoardMembersTableUpdateCompanionBuilder,
    (
      BoardMember,
      BaseReferences<_$BoardDatabase, $BoardMembersTable, BoardMember>
    ),
    BoardMember,
    PrefetchHooks Function()> {
  $$BoardMembersTableTableManager(_$BoardDatabase db, $BoardMembersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BoardMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BoardMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BoardMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> boardId = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<int> joinedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BoardMembersCompanion(
            boardId: boardId,
            userId: userId,
            role: role,
            joinedAt: joinedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String boardId,
            required String userId,
            required String role,
            required int joinedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              BoardMembersCompanion.insert(
            boardId: boardId,
            userId: userId,
            role: role,
            joinedAt: joinedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BoardMembersTableProcessedTableManager = ProcessedTableManager<
    _$BoardDatabase,
    $BoardMembersTable,
    BoardMember,
    $$BoardMembersTableFilterComposer,
    $$BoardMembersTableOrderingComposer,
    $$BoardMembersTableAnnotationComposer,
    $$BoardMembersTableCreateCompanionBuilder,
    $$BoardMembersTableUpdateCompanionBuilder,
    (
      BoardMember,
      BaseReferences<_$BoardDatabase, $BoardMembersTable, BoardMember>
    ),
    BoardMember,
    PrefetchHooks Function()>;
typedef $$WorkItemsTableCreateCompanionBuilder = WorkItemsCompanion Function({
  required String itemId,
  required String boardId,
  required String title,
  required String type,
  Value<String?> parentId,
  required String columnId,
  Value<String?> description,
  Value<String> assigneeIdsJson,
  Value<int?> startAt,
  Value<int?> dueAt,
  Value<int?> completedAt,
  Value<String> tagsJson,
  Value<bool> archived,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$WorkItemsTableUpdateCompanionBuilder = WorkItemsCompanion Function({
  Value<String> itemId,
  Value<String> boardId,
  Value<String> title,
  Value<String> type,
  Value<String?> parentId,
  Value<String> columnId,
  Value<String?> description,
  Value<String> assigneeIdsJson,
  Value<int?> startAt,
  Value<int?> dueAt,
  Value<int?> completedAt,
  Value<String> tagsJson,
  Value<bool> archived,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$WorkItemsTableFilterComposer
    extends Composer<_$BoardDatabase, $WorkItemsTable> {
  $$WorkItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
      column: $table.itemId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get columnId => $composableBuilder(
      column: $table.columnId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get assigneeIdsJson => $composableBuilder(
      column: $table.assigneeIdsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startAt => $composableBuilder(
      column: $table.startAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get archived => $composableBuilder(
      column: $table.archived, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$WorkItemsTableOrderingComposer
    extends Composer<_$BoardDatabase, $WorkItemsTable> {
  $$WorkItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
      column: $table.itemId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get boardId => $composableBuilder(
      column: $table.boardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentId => $composableBuilder(
      column: $table.parentId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get columnId => $composableBuilder(
      column: $table.columnId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get assigneeIdsJson => $composableBuilder(
      column: $table.assigneeIdsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startAt => $composableBuilder(
      column: $table.startAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get dueAt => $composableBuilder(
      column: $table.dueAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tagsJson => $composableBuilder(
      column: $table.tagsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get archived => $composableBuilder(
      column: $table.archived, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$WorkItemsTableAnnotationComposer
    extends Composer<_$BoardDatabase, $WorkItemsTable> {
  $$WorkItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get boardId =>
      $composableBuilder(column: $table.boardId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get columnId =>
      $composableBuilder(column: $table.columnId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get assigneeIdsJson => $composableBuilder(
      column: $table.assigneeIdsJson, builder: (column) => column);

  GeneratedColumn<int> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WorkItemsTableTableManager extends RootTableManager<
    _$BoardDatabase,
    $WorkItemsTable,
    WorkItem,
    $$WorkItemsTableFilterComposer,
    $$WorkItemsTableOrderingComposer,
    $$WorkItemsTableAnnotationComposer,
    $$WorkItemsTableCreateCompanionBuilder,
    $$WorkItemsTableUpdateCompanionBuilder,
    (WorkItem, BaseReferences<_$BoardDatabase, $WorkItemsTable, WorkItem>),
    WorkItem,
    PrefetchHooks Function()> {
  $$WorkItemsTableTableManager(_$BoardDatabase db, $WorkItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> itemId = const Value.absent(),
            Value<String> boardId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String> columnId = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> assigneeIdsJson = const Value.absent(),
            Value<int?> startAt = const Value.absent(),
            Value<int?> dueAt = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<bool> archived = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WorkItemsCompanion(
            itemId: itemId,
            boardId: boardId,
            title: title,
            type: type,
            parentId: parentId,
            columnId: columnId,
            description: description,
            assigneeIdsJson: assigneeIdsJson,
            startAt: startAt,
            dueAt: dueAt,
            completedAt: completedAt,
            tagsJson: tagsJson,
            archived: archived,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String itemId,
            required String boardId,
            required String title,
            required String type,
            Value<String?> parentId = const Value.absent(),
            required String columnId,
            Value<String?> description = const Value.absent(),
            Value<String> assigneeIdsJson = const Value.absent(),
            Value<int?> startAt = const Value.absent(),
            Value<int?> dueAt = const Value.absent(),
            Value<int?> completedAt = const Value.absent(),
            Value<String> tagsJson = const Value.absent(),
            Value<bool> archived = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              WorkItemsCompanion.insert(
            itemId: itemId,
            boardId: boardId,
            title: title,
            type: type,
            parentId: parentId,
            columnId: columnId,
            description: description,
            assigneeIdsJson: assigneeIdsJson,
            startAt: startAt,
            dueAt: dueAt,
            completedAt: completedAt,
            tagsJson: tagsJson,
            archived: archived,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WorkItemsTableProcessedTableManager = ProcessedTableManager<
    _$BoardDatabase,
    $WorkItemsTable,
    WorkItem,
    $$WorkItemsTableFilterComposer,
    $$WorkItemsTableOrderingComposer,
    $$WorkItemsTableAnnotationComposer,
    $$WorkItemsTableCreateCompanionBuilder,
    $$WorkItemsTableUpdateCompanionBuilder,
    (WorkItem, BaseReferences<_$BoardDatabase, $WorkItemsTable, WorkItem>),
    WorkItem,
    PrefetchHooks Function()>;

class $BoardDatabaseManager {
  final _$BoardDatabase _db;
  $BoardDatabaseManager(this._db);
  $$BoardsTableTableManager get boards =>
      $$BoardsTableTableManager(_db, _db.boards);
  $$BoardColumnsTableTableManager get boardColumns =>
      $$BoardColumnsTableTableManager(_db, _db.boardColumns);
  $$BoardMembersTableTableManager get boardMembers =>
      $$BoardMembersTableTableManager(_db, _db.boardMembers);
  $$WorkItemsTableTableManager get workItems =>
      $$WorkItemsTableTableManager(_db, _db.workItems);
}
