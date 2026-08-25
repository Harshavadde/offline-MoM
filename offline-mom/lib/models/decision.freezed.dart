// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'decision.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Decision {

 int? get id; int get meetingId; String get description; DateTime get createdAt;
/// Create a copy of Decision
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DecisionCopyWith<Decision> get copyWith => _$DecisionCopyWithImpl<Decision>(this as Decision, _$identity);

  /// Serializes this Decision to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Decision&&(identical(other.id, id) || other.id == id)&&(identical(other.meetingId, meetingId) || other.meetingId == meetingId)&&(identical(other.description, description) || other.description == description)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,meetingId,description,createdAt);

@override
String toString() {
  return 'Decision(id: $id, meetingId: $meetingId, description: $description, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $DecisionCopyWith<$Res>  {
  factory $DecisionCopyWith(Decision value, $Res Function(Decision) _then) = _$DecisionCopyWithImpl;
@useResult
$Res call({
 int? id, int meetingId, String description, DateTime createdAt
});




}
/// @nodoc
class _$DecisionCopyWithImpl<$Res>
    implements $DecisionCopyWith<$Res> {
  _$DecisionCopyWithImpl(this._self, this._then);

  final Decision _self;
  final $Res Function(Decision) _then;

/// Create a copy of Decision
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? meetingId = null,Object? description = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,meetingId: null == meetingId ? _self.meetingId : meetingId // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Decision].
extension DecisionPatterns on Decision {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Decision value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Decision() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Decision value)  $default,){
final _that = this;
switch (_that) {
case _Decision():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Decision value)?  $default,){
final _that = this;
switch (_that) {
case _Decision() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  int meetingId,  String description,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Decision() when $default != null:
return $default(_that.id,_that.meetingId,_that.description,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  int meetingId,  String description,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _Decision():
return $default(_that.id,_that.meetingId,_that.description,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  int meetingId,  String description,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _Decision() when $default != null:
return $default(_that.id,_that.meetingId,_that.description,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Decision extends Decision {
  const _Decision({required this.id, required this.meetingId, required this.description, required this.createdAt}): super._();
  factory _Decision.fromJson(Map<String, dynamic> json) => _$DecisionFromJson(json);

@override final  int? id;
@override final  int meetingId;
@override final  String description;
@override final  DateTime createdAt;

/// Create a copy of Decision
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DecisionCopyWith<_Decision> get copyWith => __$DecisionCopyWithImpl<_Decision>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DecisionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Decision&&(identical(other.id, id) || other.id == id)&&(identical(other.meetingId, meetingId) || other.meetingId == meetingId)&&(identical(other.description, description) || other.description == description)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,meetingId,description,createdAt);

@override
String toString() {
  return 'Decision(id: $id, meetingId: $meetingId, description: $description, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$DecisionCopyWith<$Res> implements $DecisionCopyWith<$Res> {
  factory _$DecisionCopyWith(_Decision value, $Res Function(_Decision) _then) = __$DecisionCopyWithImpl;
@override @useResult
$Res call({
 int? id, int meetingId, String description, DateTime createdAt
});




}
/// @nodoc
class __$DecisionCopyWithImpl<$Res>
    implements _$DecisionCopyWith<$Res> {
  __$DecisionCopyWithImpl(this._self, this._then);

  final _Decision _self;
  final $Res Function(_Decision) _then;

/// Create a copy of Decision
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? meetingId = null,Object? description = null,Object? createdAt = null,}) {
  return _then(_Decision(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,meetingId: null == meetingId ? _self.meetingId : meetingId // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
