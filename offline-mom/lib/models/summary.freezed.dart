// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'summary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Summary {

 int? get id; int? get meetingId; int? get documentId; String get summaryText; String get minutesOfMeeting; List<String> get keyTopics; String get modelUsed; DateTime get generatedAt;
/// Create a copy of Summary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SummaryCopyWith<Summary> get copyWith => _$SummaryCopyWithImpl<Summary>(this as Summary, _$identity);

  /// Serializes this Summary to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Summary&&(identical(other.id, id) || other.id == id)&&(identical(other.meetingId, meetingId) || other.meetingId == meetingId)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.summaryText, summaryText) || other.summaryText == summaryText)&&(identical(other.minutesOfMeeting, minutesOfMeeting) || other.minutesOfMeeting == minutesOfMeeting)&&const DeepCollectionEquality().equals(other.keyTopics, keyTopics)&&(identical(other.modelUsed, modelUsed) || other.modelUsed == modelUsed)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,meetingId,documentId,summaryText,minutesOfMeeting,const DeepCollectionEquality().hash(keyTopics),modelUsed,generatedAt);

@override
String toString() {
  return 'Summary(id: $id, meetingId: $meetingId, documentId: $documentId, summaryText: $summaryText, minutesOfMeeting: $minutesOfMeeting, keyTopics: $keyTopics, modelUsed: $modelUsed, generatedAt: $generatedAt)';
}


}

/// @nodoc
abstract mixin class $SummaryCopyWith<$Res>  {
  factory $SummaryCopyWith(Summary value, $Res Function(Summary) _then) = _$SummaryCopyWithImpl;
@useResult
$Res call({
 int? id, int? meetingId, int? documentId, String summaryText, String minutesOfMeeting, List<String> keyTopics, String modelUsed, DateTime generatedAt
});




}
/// @nodoc
class _$SummaryCopyWithImpl<$Res>
    implements $SummaryCopyWith<$Res> {
  _$SummaryCopyWithImpl(this._self, this._then);

  final Summary _self;
  final $Res Function(Summary) _then;

/// Create a copy of Summary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? meetingId = freezed,Object? documentId = freezed,Object? summaryText = null,Object? minutesOfMeeting = null,Object? keyTopics = null,Object? modelUsed = null,Object? generatedAt = null,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,meetingId: freezed == meetingId ? _self.meetingId : meetingId // ignore: cast_nullable_to_non_nullable
as int?,documentId: freezed == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as int?,summaryText: null == summaryText ? _self.summaryText : summaryText // ignore: cast_nullable_to_non_nullable
as String,minutesOfMeeting: null == minutesOfMeeting ? _self.minutesOfMeeting : minutesOfMeeting // ignore: cast_nullable_to_non_nullable
as String,keyTopics: null == keyTopics ? _self.keyTopics : keyTopics // ignore: cast_nullable_to_non_nullable
as List<String>,modelUsed: null == modelUsed ? _self.modelUsed : modelUsed // ignore: cast_nullable_to_non_nullable
as String,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Summary].
extension SummaryPatterns on Summary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Summary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Summary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Summary value)  $default,){
final _that = this;
switch (_that) {
case _Summary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Summary value)?  $default,){
final _that = this;
switch (_that) {
case _Summary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  int? meetingId,  int? documentId,  String summaryText,  String minutesOfMeeting,  List<String> keyTopics,  String modelUsed,  DateTime generatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Summary() when $default != null:
return $default(_that.id,_that.meetingId,_that.documentId,_that.summaryText,_that.minutesOfMeeting,_that.keyTopics,_that.modelUsed,_that.generatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  int? meetingId,  int? documentId,  String summaryText,  String minutesOfMeeting,  List<String> keyTopics,  String modelUsed,  DateTime generatedAt)  $default,) {final _that = this;
switch (_that) {
case _Summary():
return $default(_that.id,_that.meetingId,_that.documentId,_that.summaryText,_that.minutesOfMeeting,_that.keyTopics,_that.modelUsed,_that.generatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  int? meetingId,  int? documentId,  String summaryText,  String minutesOfMeeting,  List<String> keyTopics,  String modelUsed,  DateTime generatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Summary() when $default != null:
return $default(_that.id,_that.meetingId,_that.documentId,_that.summaryText,_that.minutesOfMeeting,_that.keyTopics,_that.modelUsed,_that.generatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Summary extends Summary {
  const _Summary({required this.id, this.meetingId, this.documentId, required this.summaryText, required this.minutesOfMeeting, required final  List<String> keyTopics, required this.modelUsed, required this.generatedAt}): assert((meetingId != null) != (documentId != null), 'exactly one of meetingId/documentId must be set'),_keyTopics = keyTopics,super._();
  factory _Summary.fromJson(Map<String, dynamic> json) => _$SummaryFromJson(json);

@override final  int? id;
@override final  int? meetingId;
@override final  int? documentId;
@override final  String summaryText;
@override final  String minutesOfMeeting;
 final  List<String> _keyTopics;
@override List<String> get keyTopics {
  if (_keyTopics is EqualUnmodifiableListView) return _keyTopics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_keyTopics);
}

@override final  String modelUsed;
@override final  DateTime generatedAt;

/// Create a copy of Summary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SummaryCopyWith<_Summary> get copyWith => __$SummaryCopyWithImpl<_Summary>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SummaryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Summary&&(identical(other.id, id) || other.id == id)&&(identical(other.meetingId, meetingId) || other.meetingId == meetingId)&&(identical(other.documentId, documentId) || other.documentId == documentId)&&(identical(other.summaryText, summaryText) || other.summaryText == summaryText)&&(identical(other.minutesOfMeeting, minutesOfMeeting) || other.minutesOfMeeting == minutesOfMeeting)&&const DeepCollectionEquality().equals(other._keyTopics, _keyTopics)&&(identical(other.modelUsed, modelUsed) || other.modelUsed == modelUsed)&&(identical(other.generatedAt, generatedAt) || other.generatedAt == generatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,meetingId,documentId,summaryText,minutesOfMeeting,const DeepCollectionEquality().hash(_keyTopics),modelUsed,generatedAt);

@override
String toString() {
  return 'Summary(id: $id, meetingId: $meetingId, documentId: $documentId, summaryText: $summaryText, minutesOfMeeting: $minutesOfMeeting, keyTopics: $keyTopics, modelUsed: $modelUsed, generatedAt: $generatedAt)';
}


}

/// @nodoc
abstract mixin class _$SummaryCopyWith<$Res> implements $SummaryCopyWith<$Res> {
  factory _$SummaryCopyWith(_Summary value, $Res Function(_Summary) _then) = __$SummaryCopyWithImpl;
@override @useResult
$Res call({
 int? id, int? meetingId, int? documentId, String summaryText, String minutesOfMeeting, List<String> keyTopics, String modelUsed, DateTime generatedAt
});




}
/// @nodoc
class __$SummaryCopyWithImpl<$Res>
    implements _$SummaryCopyWith<$Res> {
  __$SummaryCopyWithImpl(this._self, this._then);

  final _Summary _self;
  final $Res Function(_Summary) _then;

/// Create a copy of Summary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? meetingId = freezed,Object? documentId = freezed,Object? summaryText = null,Object? minutesOfMeeting = null,Object? keyTopics = null,Object? modelUsed = null,Object? generatedAt = null,}) {
  return _then(_Summary(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,meetingId: freezed == meetingId ? _self.meetingId : meetingId // ignore: cast_nullable_to_non_nullable
as int?,documentId: freezed == documentId ? _self.documentId : documentId // ignore: cast_nullable_to_non_nullable
as int?,summaryText: null == summaryText ? _self.summaryText : summaryText // ignore: cast_nullable_to_non_nullable
as String,minutesOfMeeting: null == minutesOfMeeting ? _self.minutesOfMeeting : minutesOfMeeting // ignore: cast_nullable_to_non_nullable
as String,keyTopics: null == keyTopics ? _self._keyTopics : keyTopics // ignore: cast_nullable_to_non_nullable
as List<String>,modelUsed: null == modelUsed ? _self.modelUsed : modelUsed // ignore: cast_nullable_to_non_nullable
as String,generatedAt: null == generatedAt ? _self.generatedAt : generatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
