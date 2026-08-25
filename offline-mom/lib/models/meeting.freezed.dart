// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'meeting.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Meeting {

 int? get id; String get title; MeetingSource get source; MeetingStatus get status; DateTime get createdAt; DateTime get updatedAt; int get durationSeconds; String? get audioFilePath; bool get isFavorite;/// Set when [status] is [MeetingStatus.error]; the exception message
/// from whichever pipeline stage (transcription or AI summary) failed,
/// so a failure is diagnosable instead of a dead end.
 String? get errorMessage;
/// Create a copy of Meeting
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MeetingCopyWith<Meeting> get copyWith => _$MeetingCopyWithImpl<Meeting>(this as Meeting, _$identity);

  /// Serializes this Meeting to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Meeting&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.source, source) || other.source == source)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.audioFilePath, audioFilePath) || other.audioFilePath == audioFilePath)&&(identical(other.isFavorite, isFavorite) || other.isFavorite == isFavorite)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,source,status,createdAt,updatedAt,durationSeconds,audioFilePath,isFavorite,errorMessage);

@override
String toString() {
  return 'Meeting(id: $id, title: $title, source: $source, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, durationSeconds: $durationSeconds, audioFilePath: $audioFilePath, isFavorite: $isFavorite, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $MeetingCopyWith<$Res>  {
  factory $MeetingCopyWith(Meeting value, $Res Function(Meeting) _then) = _$MeetingCopyWithImpl;
@useResult
$Res call({
 int? id, String title, MeetingSource source, MeetingStatus status, DateTime createdAt, DateTime updatedAt, int durationSeconds, String? audioFilePath, bool isFavorite, String? errorMessage
});




}
/// @nodoc
class _$MeetingCopyWithImpl<$Res>
    implements $MeetingCopyWith<$Res> {
  _$MeetingCopyWithImpl(this._self, this._then);

  final Meeting _self;
  final $Res Function(Meeting) _then;

/// Create a copy of Meeting
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? title = null,Object? source = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? durationSeconds = null,Object? audioFilePath = freezed,Object? isFavorite = null,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as MeetingSource,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as MeetingStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,durationSeconds: null == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int,audioFilePath: freezed == audioFilePath ? _self.audioFilePath : audioFilePath // ignore: cast_nullable_to_non_nullable
as String?,isFavorite: null == isFavorite ? _self.isFavorite : isFavorite // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Meeting].
extension MeetingPatterns on Meeting {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Meeting value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Meeting() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Meeting value)  $default,){
final _that = this;
switch (_that) {
case _Meeting():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Meeting value)?  $default,){
final _that = this;
switch (_that) {
case _Meeting() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  String title,  MeetingSource source,  MeetingStatus status,  DateTime createdAt,  DateTime updatedAt,  int durationSeconds,  String? audioFilePath,  bool isFavorite,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Meeting() when $default != null:
return $default(_that.id,_that.title,_that.source,_that.status,_that.createdAt,_that.updatedAt,_that.durationSeconds,_that.audioFilePath,_that.isFavorite,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  String title,  MeetingSource source,  MeetingStatus status,  DateTime createdAt,  DateTime updatedAt,  int durationSeconds,  String? audioFilePath,  bool isFavorite,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _Meeting():
return $default(_that.id,_that.title,_that.source,_that.status,_that.createdAt,_that.updatedAt,_that.durationSeconds,_that.audioFilePath,_that.isFavorite,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  String title,  MeetingSource source,  MeetingStatus status,  DateTime createdAt,  DateTime updatedAt,  int durationSeconds,  String? audioFilePath,  bool isFavorite,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _Meeting() when $default != null:
return $default(_that.id,_that.title,_that.source,_that.status,_that.createdAt,_that.updatedAt,_that.durationSeconds,_that.audioFilePath,_that.isFavorite,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Meeting extends Meeting {
  const _Meeting({required this.id, required this.title, required this.source, required this.status, required this.createdAt, required this.updatedAt, this.durationSeconds = 0, this.audioFilePath, this.isFavorite = false, this.errorMessage}): super._();
  factory _Meeting.fromJson(Map<String, dynamic> json) => _$MeetingFromJson(json);

@override final  int? id;
@override final  String title;
@override final  MeetingSource source;
@override final  MeetingStatus status;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override@JsonKey() final  int durationSeconds;
@override final  String? audioFilePath;
@override@JsonKey() final  bool isFavorite;
/// Set when [status] is [MeetingStatus.error]; the exception message
/// from whichever pipeline stage (transcription or AI summary) failed,
/// so a failure is diagnosable instead of a dead end.
@override final  String? errorMessage;

/// Create a copy of Meeting
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MeetingCopyWith<_Meeting> get copyWith => __$MeetingCopyWithImpl<_Meeting>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MeetingToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Meeting&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.source, source) || other.source == source)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&(identical(other.audioFilePath, audioFilePath) || other.audioFilePath == audioFilePath)&&(identical(other.isFavorite, isFavorite) || other.isFavorite == isFavorite)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,source,status,createdAt,updatedAt,durationSeconds,audioFilePath,isFavorite,errorMessage);

@override
String toString() {
  return 'Meeting(id: $id, title: $title, source: $source, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, durationSeconds: $durationSeconds, audioFilePath: $audioFilePath, isFavorite: $isFavorite, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$MeetingCopyWith<$Res> implements $MeetingCopyWith<$Res> {
  factory _$MeetingCopyWith(_Meeting value, $Res Function(_Meeting) _then) = __$MeetingCopyWithImpl;
@override @useResult
$Res call({
 int? id, String title, MeetingSource source, MeetingStatus status, DateTime createdAt, DateTime updatedAt, int durationSeconds, String? audioFilePath, bool isFavorite, String? errorMessage
});




}
/// @nodoc
class __$MeetingCopyWithImpl<$Res>
    implements _$MeetingCopyWith<$Res> {
  __$MeetingCopyWithImpl(this._self, this._then);

  final _Meeting _self;
  final $Res Function(_Meeting) _then;

/// Create a copy of Meeting
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? title = null,Object? source = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? durationSeconds = null,Object? audioFilePath = freezed,Object? isFavorite = null,Object? errorMessage = freezed,}) {
  return _then(_Meeting(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as MeetingSource,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as MeetingStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,durationSeconds: null == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int,audioFilePath: freezed == audioFilePath ? _self.audioFilePath : audioFilePath // ignore: cast_nullable_to_non_nullable
as String?,isFavorite: null == isFavorite ? _self.isFavorite : isFavorite // ignore: cast_nullable_to_non_nullable
as bool,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
