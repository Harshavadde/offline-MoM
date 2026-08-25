import '../database/tables.dart';
import '../services/ai/model_lifecycle_manager.dart' show ModelKind;

/// A record of a model actually downloaded onto this device - the
/// database-backed source of truth for "installed" (distinct from
/// [AiModelSpec], the static catalog description of what *could* be
/// downloaded). Written only once a download has fully completed and
/// passed its post-download size check (see
/// `ModelDownloadController._finishInstall`) - see [ModelKind]'s Model
/// Safety requirement ("never allow ... half-installed models", ADR-036):
/// a row existing here is itself the "fully installed" guarantee, so
/// nothing else needs to re-derive that from file-existence checks the way
/// `WhisperSpeechToTextEngine.isModelDownloaded` did before Phase 6A.
class InstalledModel {
  const InstalledModel({
    this.id,
    required this.modelId,
    required this.kind,
    required this.localPath,
    required this.sizeBytes,
    required this.downloadedAt,
    this.localSha256,
    required this.isActive,
  });

  /// Row id - null for a not-yet-inserted instance.
  final int? id;

  /// The [AiModelSpec.id] this row was downloaded from.
  final String modelId;

  final ModelKind kind;
  final String localPath;

  /// The file's actual measured size at install time - the real
  /// [AiModelSpec.sizeBytesApprox] counterpart, and what the Storage Usage
  /// screen's totals are computed from (not the catalog's approximation).
  final int sizeBytes;

  final DateTime downloadedAt;

  /// SHA-256 of the downloaded file, computed once at install time and
  /// re-computed on demand by "Verify Model" to detect on-disk corruption
  /// since installation. **This is a local integrity fingerprint, not a
  /// publisher-signed checksum** - this app has no confirmed, verified
  /// hash published by the model's source to check against (see ADR-036);
  /// it can only prove "this file is byte-identical to what was downloaded
  /// then", not "this file is authentically what the publisher intended".
  /// Null only for a row written before this field existed (should not
  /// occur post-Phase 6A; defensive nullability, not an expected state).
  final String? localSha256;

  /// At most one [InstalledModel] per [kind] should have this `true` at a
  /// time - enforced by `InstalledModelRepository.setActive`, which
  /// deactivates every other row of the same [kind] in the same
  /// transaction-equivalent call (see its doc comment).
  final bool isActive;

  InstalledModel copyWith({
    int? id,
    String? modelId,
    ModelKind? kind,
    String? localPath,
    int? sizeBytes,
    DateTime? downloadedAt,
    String? localSha256,
    bool? isActive,
  }) {
    return InstalledModel(
      id: id ?? this.id,
      modelId: modelId ?? this.modelId,
      kind: kind ?? this.kind,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      localSha256: localSha256 ?? this.localSha256,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, Object?> toMap() => {
        InstalledModelsTable.id: id,
        InstalledModelsTable.modelId: modelId,
        InstalledModelsTable.kind: kind.name,
        InstalledModelsTable.localPath: localPath,
        InstalledModelsTable.sizeBytes: sizeBytes,
        InstalledModelsTable.downloadedAt: downloadedAt.toIso8601String(),
        InstalledModelsTable.localSha256: localSha256,
        InstalledModelsTable.isActive: isActive ? 1 : 0,
      };

  factory InstalledModel.fromMap(Map<String, Object?> map) {
    return InstalledModel(
      id: map[InstalledModelsTable.id] as int?,
      modelId: map[InstalledModelsTable.modelId] as String,
      kind: ModelKind.values.firstWhere(
        (k) => k.name == map[InstalledModelsTable.kind] as String,
      ),
      localPath: map[InstalledModelsTable.localPath] as String,
      sizeBytes: map[InstalledModelsTable.sizeBytes] as int,
      downloadedAt: DateTime.parse(map[InstalledModelsTable.downloadedAt] as String),
      localSha256: map[InstalledModelsTable.localSha256] as String?,
      isActive: (map[InstalledModelsTable.isActive] as int) == 1,
    );
  }
}
