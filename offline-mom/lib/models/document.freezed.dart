// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'document.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Document {

 int? get id;/// User-editable display name - defaults to [originalFilename] minus
/// its extension on import, same convention as `ImportController`
/// titling an imported meeting from its picked filename.
 String get title;/// The literal filename as picked at import time - immutable
/// historical record, distinct from [title] (which the user can
/// rename freely via [DocumentStatus]-independent rename support).
 String get originalFilename; DocumentSourceType get sourceType; String get mimeType; int get fileSizeBytes; String get filePath; DocumentStatus get status; DateTime get createdAt; DateTime get updatedAt; String? get extractedText;/// Set when [status] is [DocumentStatus.error] - mirrors
/// [Meeting.errorMessage]'s diagnosability rationale.
 String? get errorMessage;
/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DocumentCopyWith<Document> get copyWith => _$DocumentCopyWithImpl<Document>(this as Document, _$identity);

  /// Serializes this Document to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Document&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.originalFilename, originalFilename) || other.originalFilename == originalFilename)&&(identical(other.sourceType, sourceType) || other.sourceType == sourceType)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileSizeBytes, fileSizeBytes) || other.fileSizeBytes == fileSizeBytes)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.extractedText, extractedText) || other.extractedText == extractedText)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,originalFilename,sourceType,mimeType,fileSizeBytes,filePath,status,createdAt,updatedAt,extractedText,errorMessage);

@override
String toString() {
  return 'Document(id: $id, title: $title, originalFilename: $originalFilename, sourceType: $sourceType, mimeType: $mimeType, fileSizeBytes: $fileSizeBytes, filePath: $filePath, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, extractedText: $extractedText, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $DocumentCopyWith<$Res>  {
  factory $DocumentCopyWith(Document value, $Res Function(Document) _then) = _$DocumentCopyWithImpl;
@useResult
$Res call({
 int? id, String title, String originalFilename, DocumentSourceType sourceType, String mimeType, int fileSizeBytes, String filePath, DocumentStatus status, DateTime createdAt, DateTime updatedAt, String? extractedText, String? errorMessage
});




}
/// @nodoc
class _$DocumentCopyWithImpl<$Res>
    implements $DocumentCopyWith<$Res> {
  _$DocumentCopyWithImpl(this._self, this._then);

  final Document _self;
  final $Res Function(Document) _then;

/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? title = null,Object? originalFilename = null,Object? sourceType = null,Object? mimeType = null,Object? fileSizeBytes = null,Object? filePath = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? extractedText = freezed,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,originalFilename: null == originalFilename ? _self.originalFilename : originalFilename // ignore: cast_nullable_to_non_nullable
as String,sourceType: null == sourceType ? _self.sourceType : sourceType // ignore: cast_nullable_to_non_nullable
as DocumentSourceType,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,fileSizeBytes: null == fileSizeBytes ? _self.fileSizeBytes : fileSizeBytes // ignore: cast_nullable_to_non_nullable
as int,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DocumentStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,extractedText: freezed == extractedText ? _self.extractedText : extractedText // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Document].
extension DocumentPatterns on Document {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Document value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Document() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Document value)  $default,){
final _that = this;
switch (_that) {
case _Document():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Document value)?  $default,){
final _that = this;
switch (_that) {
case _Document() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  String title,  String originalFilename,  DocumentSourceType sourceType,  String mimeType,  int fileSizeBytes,  String filePath,  DocumentStatus status,  DateTime createdAt,  DateTime updatedAt,  String? extractedText,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Document() when $default != null:
return $default(_that.id,_that.title,_that.originalFilename,_that.sourceType,_that.mimeType,_that.fileSizeBytes,_that.filePath,_that.status,_that.createdAt,_that.updatedAt,_that.extractedText,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  String title,  String originalFilename,  DocumentSourceType sourceType,  String mimeType,  int fileSizeBytes,  String filePath,  DocumentStatus status,  DateTime createdAt,  DateTime updatedAt,  String? extractedText,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _Document():
return $default(_that.id,_that.title,_that.originalFilename,_that.sourceType,_that.mimeType,_that.fileSizeBytes,_that.filePath,_that.status,_that.createdAt,_that.updatedAt,_that.extractedText,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  String title,  String originalFilename,  DocumentSourceType sourceType,  String mimeType,  int fileSizeBytes,  String filePath,  DocumentStatus status,  DateTime createdAt,  DateTime updatedAt,  String? extractedText,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _Document() when $default != null:
return $default(_that.id,_that.title,_that.originalFilename,_that.sourceType,_that.mimeType,_that.fileSizeBytes,_that.filePath,_that.status,_that.createdAt,_that.updatedAt,_that.extractedText,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Document extends Document {
  const _Document({required this.id, required this.title, required this.originalFilename, required this.sourceType, required this.mimeType, required this.fileSizeBytes, required this.filePath, required this.status, required this.createdAt, required this.updatedAt, this.extractedText, this.errorMessage}): super._();
  factory _Document.fromJson(Map<String, dynamic> json) => _$DocumentFromJson(json);

@override final  int? id;
/// User-editable display name - defaults to [originalFilename] minus
/// its extension on import, same convention as `ImportController`
/// titling an imported meeting from its picked filename.
@override final  String title;
/// The literal filename as picked at import time - immutable
/// historical record, distinct from [title] (which the user can
/// rename freely via [DocumentStatus]-independent rename support).
@override final  String originalFilename;
@override final  DocumentSourceType sourceType;
@override final  String mimeType;
@override final  int fileSizeBytes;
@override final  String filePath;
@override final  DocumentStatus status;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  String? extractedText;
/// Set when [status] is [DocumentStatus.error] - mirrors
/// [Meeting.errorMessage]'s diagnosability rationale.
@override final  String? errorMessage;

/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DocumentCopyWith<_Document> get copyWith => __$DocumentCopyWithImpl<_Document>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DocumentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Document&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.originalFilename, originalFilename) || other.originalFilename == originalFilename)&&(identical(other.sourceType, sourceType) || other.sourceType == sourceType)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.fileSizeBytes, fileSizeBytes) || other.fileSizeBytes == fileSizeBytes)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.extractedText, extractedText) || other.extractedText == extractedText)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,originalFilename,sourceType,mimeType,fileSizeBytes,filePath,status,createdAt,updatedAt,extractedText,errorMessage);

@override
String toString() {
  return 'Document(id: $id, title: $title, originalFilename: $originalFilename, sourceType: $sourceType, mimeType: $mimeType, fileSizeBytes: $fileSizeBytes, filePath: $filePath, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, extractedText: $extractedText, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$DocumentCopyWith<$Res> implements $DocumentCopyWith<$Res> {
  factory _$DocumentCopyWith(_Document value, $Res Function(_Document) _then) = __$DocumentCopyWithImpl;
@override @useResult
$Res call({
 int? id, String title, String originalFilename, DocumentSourceType sourceType, String mimeType, int fileSizeBytes, String filePath, DocumentStatus status, DateTime createdAt, DateTime updatedAt, String? extractedText, String? errorMessage
});




}
/// @nodoc
class __$DocumentCopyWithImpl<$Res>
    implements _$DocumentCopyWith<$Res> {
  __$DocumentCopyWithImpl(this._self, this._then);

  final _Document _self;
  final $Res Function(_Document) _then;

/// Create a copy of Document
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? title = null,Object? originalFilename = null,Object? sourceType = null,Object? mimeType = null,Object? fileSizeBytes = null,Object? filePath = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? extractedText = freezed,Object? errorMessage = freezed,}) {
  return _then(_Document(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,originalFilename: null == originalFilename ? _self.originalFilename : originalFilename // ignore: cast_nullable_to_non_nullable
as String,sourceType: null == sourceType ? _self.sourceType : sourceType // ignore: cast_nullable_to_non_nullable
as DocumentSourceType,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,fileSizeBytes: null == fileSizeBytes ? _self.fileSizeBytes : fileSizeBytes // ignore: cast_nullable_to_non_nullable
as int,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DocumentStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,extractedText: freezed == extractedText ? _self.extractedText : extractedText // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
