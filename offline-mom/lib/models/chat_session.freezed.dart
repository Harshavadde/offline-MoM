// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChatSession {

 int? get id; String get title; ChatScope get scope; DateTime get createdAt; DateTime get updatedAt;/// Set only when [scope] is [ChatScope.document] - per
/// docs/v2/12-database-design.md's `chat_sessions.document_id`.
 int? get documentId;/// Set only when [scope] is [ChatScope.meeting] - added in Phase 2A
/// alongside [ChatScope.meeting] itself (ADR-025).
 int? get meetingId;/// Added in migration v10 (V2 Phase 2B, ADR-028) - pinned conversations
/// sort first in [ChatHistoryScreen], same convention as
/// [Meeting.isFavorite].
 bool get isPinned;
/// Create a copy of ChatSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatSessionCopyWith<ChatSession> get copyWith => _$ChatSessionCopyWithImpl<ChatSession>(this as ChatSession, _$identity);

  /// Serializes this ChatSession to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatSession&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.meetingId, meetingId) || other.meetingId == meetingId)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,scope,createdAt,updatedAt,documentId,meetingId,isPinned);

@override
String toString() {
  return 'ChatSession(id: $id, title: $title, scope: $scope, createdAt: $createdAt, updatedAt: $updatedAt, documentId: $documentId, meetingId: $meetingId, isPinned: $isPinned)';
}


}

/// @nodoc
abstract mixin class $ChatSessionCopyWith<$Res>  {
  factory $ChatSessionCopyWith(ChatSession value, $Res Function(ChatSession) _then) = _$ChatSessionCopyWithImpl;
@useResult
$Res call({
 int? id, String title, ChatScope scope, DateTime createdAt, DateTime updatedAt, int? documentId, int? meetingId, bool isPinned
});




}
/// @nodoc
class _$ChatSessionCopyWithImpl<$Res>
    implements $ChatSessionCopyWith<$Res> {
  _$ChatSessionCopyWithImpl(this._self, this._then);

  final ChatSession _self;
  final $Res Function(ChatSession) _then;

/// Create a copy of ChatSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? title = null,Object? scope = null,Object? createdAt = null,Object? updatedAt = null,Object? documentId = freezed,Object? meetingId = freezed,Object? isPinned = null,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ChatScope,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,documentId: freezed == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as int?,meetingId: freezed == meetingId ? _self.meetingId : meetingId // ignore: cast_nullable_to_non_nullable
as int?,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatSession].
extension ChatSessionPatterns on ChatSession {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatSession() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatSession value)  $default,){
final _that = this;
switch (_that) {
case _ChatSession():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatSession value)?  $default,){
final _that = this;
switch (_that) {
case _ChatSession() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  String title,  ChatScope scope,  DateTime createdAt,  DateTime updatedAt,  int? documentId,  int? meetingId,  bool isPinned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatSession() when $default != null:
return $default(_that.id,_that.title,_that.scope,_that.createdAt,_that.updatedAt,_that.documentId,_that.meetingId,_that.isPinned);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  String title,  ChatScope scope,  DateTime createdAt,  DateTime updatedAt,  int? documentId,  int? meetingId,  bool isPinned)  $default,) {final _that = this;
switch (_that) {
case _ChatSession():
return $default(_that.id,_that.title,_that.scope,_that.createdAt,_that.updatedAt,_that.documentId,_that.meetingId,_that.isPinned);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  String title,  ChatScope scope,  DateTime createdAt,  DateTime updatedAt,  int? documentId,  int? meetingId,  bool isPinned)?  $default,) {final _that = this;
switch (_that) {
case _ChatSession() when $default != null:
return $default(_that.id,_that.title,_that.scope,_that.createdAt,_that.updatedAt,_that.documentId,_that.meetingId,_that.isPinned);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatSession extends ChatSession {
  const _ChatSession({required this.id, required this.title, required this.scope, required this.createdAt, required this.updatedAt, this.documentId, this.meetingId, this.isPinned = false}): super._();
  factory _ChatSession.fromJson(Map<String, dynamic> json) => _$ChatSessionFromJson(json);

@override final  int? id;
@override final  String title;
@override final  ChatScope scope;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
/// Set only when [scope] is [ChatScope.document] - per
/// docs/v2/12-database-design.md's `chat_sessions.document_id`.
@override final  int? documentId;
/// Set only when [scope] is [ChatScope.meeting] - added in Phase 2A
/// alongside [ChatScope.meeting] itself (ADR-025).
@override final  int? meetingId;
/// Added in migration v10 (V2 Phase 2B, ADR-028) - pinned conversations
/// sort first in [ChatHistoryScreen], same convention as
/// [Meeting.isFavorite].
@override@JsonKey() final  bool isPinned;

/// Create a copy of ChatSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatSessionCopyWith<_ChatSession> get copyWith => __$ChatSessionCopyWithImpl<_ChatSession>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatSessionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatSession&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.meetingId, meetingId) || other.meetingId == meetingId)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,scope,createdAt,updatedAt,documentId,meetingId,isPinned);

@override
String toString() {
  return 'ChatSession(id: $id, title: $title, scope: $scope, createdAt: $createdAt, updatedAt: $updatedAt, documentId: $documentId, meetingId: $meetingId, isPinned: $isPinned)';
}


}

/// @nodoc
abstract mixin class _$ChatSessionCopyWith<$Res> implements $ChatSessionCopyWith<$Res> {
  factory _$ChatSessionCopyWith(_ChatSession value, $Res Function(_ChatSession) _then) = __$ChatSessionCopyWithImpl;
@override @useResult
$Res call({
 int? id, String title, ChatScope scope, DateTime createdAt, DateTime updatedAt, int? documentId, int? meetingId, bool isPinned
});




}
/// @nodoc
class __$ChatSessionCopyWithImpl<$Res>
    implements _$ChatSessionCopyWith<$Res> {
  __$ChatSessionCopyWithImpl(this._self, this._then);

  final _ChatSession _self;
  final $Res Function(_ChatSession) _then;

/// Create a copy of ChatSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? title = null,Object? scope = null,Object? createdAt = null,Object? updatedAt = null,Object? documentId = freezed,Object? meetingId = freezed,Object? isPinned = null,}) {
  return _then(_ChatSession(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ChatScope,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,documentId: freezed == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as int?,meetingId: freezed == meetingId ? _self.meetingId : meetingId // ignore: cast_nullable_to_non_nullable
as int?,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
