// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChatMessage {

 int? get id; int get sessionId; ChatMessageRole get role; String get content; DateTime get createdAt;/// Which meeting(s)/document(s) an assistant answer cited (FR-30,
/// docs/v2/08-functional-requirements.md) - JSON-encoded list of
/// [ChatSourceRef]s, built from the [KnowledgeChunk]s actually
/// retrieved and included in the prompt's context, never parsed from
/// the model's own text (ADR-026, docs/v2/implementation/03-decisions.md).
/// Null for [ChatMessageRole.user] messages.
 String? get sourcesJson;/// See [AnswerProvenance]. Null for [ChatMessageRole.user] messages
/// and for any row written before migration v14.
 AnswerProvenance? get answerProvenance;
/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ChatMessageCopyWith<ChatMessage> get copyWith => _$ChatMessageCopyWithImpl<ChatMessage>(this as ChatMessage, _$identity);

  /// Serializes this ChatMessage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.role, role) || other.role == role)&&(identical(other.content, content) || other.content == content)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.sourcesJson, sourcesJson) || other.sourcesJson == sourcesJson)&&(identical(other.answerProvenance, answerProvenance) || other.answerProvenance == answerProvenance));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,sessionId,role,content,createdAt,sourcesJson,answerProvenance);

@override
String toString() {
  return 'ChatMessage(id: $id, sessionId: $sessionId, role: $role, content: $content, createdAt: $createdAt, sourcesJson: $sourcesJson, answerProvenance: $answerProvenance)';
}


}

/// @nodoc
abstract mixin class $ChatMessageCopyWith<$Res>  {
  factory $ChatMessageCopyWith(ChatMessage value, $Res Function(ChatMessage) _then) = _$ChatMessageCopyWithImpl;
@useResult
$Res call({
 int? id, int sessionId, ChatMessageRole role, String content, DateTime createdAt, String? sourcesJson, AnswerProvenance? answerProvenance
});




}
/// @nodoc
class _$ChatMessageCopyWithImpl<$Res>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._self, this._then);

  final ChatMessage _self;
  final $Res Function(ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? sessionId = null,Object? role = null,Object? content = null,Object? createdAt = null,Object? sourcesJson = freezed,Object? answerProvenance = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ChatMessageRole,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,sourcesJson: freezed == sourcesJson ? _self.sourcesJson : sourcesJson // ignore: cast_nullable_to_non_nullable
as String?,answerProvenance: freezed == answerProvenance ? _self.answerProvenance : answerProvenance // ignore: cast_nullable_to_non_nullable
as AnswerProvenance?,
  ));
}

}


/// Adds pattern-matching-related methods to [ChatMessage].
extension ChatMessagePatterns on ChatMessage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ChatMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ChatMessage value)  $default,){
final _that = this;
switch (_that) {
case _ChatMessage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ChatMessage value)?  $default,){
final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  int sessionId,  ChatMessageRole role,  String content,  DateTime createdAt,  String? sourcesJson,  AnswerProvenance? answerProvenance)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.sessionId,_that.role,_that.content,_that.createdAt,_that.sourcesJson,_that.answerProvenance);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  int sessionId,  ChatMessageRole role,  String content,  DateTime createdAt,  String? sourcesJson,  AnswerProvenance? answerProvenance)  $default,) {final _that = this;
switch (_that) {
case _ChatMessage():
return $default(_that.id,_that.sessionId,_that.role,_that.content,_that.createdAt,_that.sourcesJson,_that.answerProvenance);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  int sessionId,  ChatMessageRole role,  String content,  DateTime createdAt,  String? sourcesJson,  AnswerProvenance? answerProvenance)?  $default,) {final _that = this;
switch (_that) {
case _ChatMessage() when $default != null:
return $default(_that.id,_that.sessionId,_that.role,_that.content,_that.createdAt,_that.sourcesJson,_that.answerProvenance);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ChatMessage extends ChatMessage {
  const _ChatMessage({required this.id, required this.sessionId, required this.role, required this.content, required this.createdAt, this.sourcesJson, this.answerProvenance}): super._();
  factory _ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);

@override final  int? id;
@override final  int sessionId;
@override final  ChatMessageRole role;
@override final  String content;
@override final  DateTime createdAt;
/// Which meeting(s)/document(s) an assistant answer cited (FR-30,
/// docs/v2/08-functional-requirements.md) - JSON-encoded list of
/// [ChatSourceRef]s, built from the [KnowledgeChunk]s actually
/// retrieved and included in the prompt's context, never parsed from
/// the model's own text (ADR-026, docs/v2/implementation/03-decisions.md).
/// Null for [ChatMessageRole.user] messages.
@override final  String? sourcesJson;
/// See [AnswerProvenance]. Null for [ChatMessageRole.user] messages
/// and for any row written before migration v14.
@override final  AnswerProvenance? answerProvenance;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ChatMessageCopyWith<_ChatMessage> get copyWith => __$ChatMessageCopyWithImpl<_ChatMessage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ChatMessageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ChatMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.role, role) || other.role == role)&&(identical(other.content, content) || other.content == content)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.sourcesJson, sourcesJson) || other.sourcesJson == sourcesJson)&&(identical(other.answerProvenance, answerProvenance) || other.answerProvenance == answerProvenance));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,sessionId,role,content,createdAt,sourcesJson,answerProvenance);

@override
String toString() {
  return 'ChatMessage(id: $id, sessionId: $sessionId, role: $role, content: $content, createdAt: $createdAt, sourcesJson: $sourcesJson, answerProvenance: $answerProvenance)';
}


}

/// @nodoc
abstract mixin class _$ChatMessageCopyWith<$Res> implements $ChatMessageCopyWith<$Res> {
  factory _$ChatMessageCopyWith(_ChatMessage value, $Res Function(_ChatMessage) _then) = __$ChatMessageCopyWithImpl;
@override @useResult
$Res call({
 int? id, int sessionId, ChatMessageRole role, String content, DateTime createdAt, String? sourcesJson, AnswerProvenance? answerProvenance
});




}
/// @nodoc
class __$ChatMessageCopyWithImpl<$Res>
    implements _$ChatMessageCopyWith<$Res> {
  __$ChatMessageCopyWithImpl(this._self, this._then);

  final _ChatMessage _self;
  final $Res Function(_ChatMessage) _then;

/// Create a copy of ChatMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? sessionId = null,Object? role = null,Object? content = null,Object? createdAt = null,Object? sourcesJson = freezed,Object? answerProvenance = freezed,}) {
  return _then(_ChatMessage(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as int,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as ChatMessageRole,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,sourcesJson: freezed == sourcesJson ? _self.sourcesJson : sourcesJson // ignore: cast_nullable_to_non_nullable
as String?,answerProvenance: freezed == answerProvenance ? _self.answerProvenance : answerProvenance // ignore: cast_nullable_to_non_nullable
as AnswerProvenance?,
  ));
}


}

// dart format on
