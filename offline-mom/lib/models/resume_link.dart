import 'dart:convert';

/// One user-added link on a [Resume]'s Profile (portfolio, LinkedIn, GitHub,
/// etc.) - a label plus a URL. A plain class (not `@freezed`), mirroring
/// [ChatSourceRef]'s exact reasoning: a small value type serialized as one
/// JSON array into a single TEXT column ([Resume.links], via
/// [Resume.linksJson]), with `encodeList`/`decodeList` doing the round trip.
class ResumeLink {
  const ResumeLink({required this.label, required this.url});

  final String label;
  final String url;

  ResumeLink copyWith({String? label, String? url}) {
    return ResumeLink(label: label ?? this.label, url: url ?? this.url);
  }

  Map<String, Object?> toMap() {
    return {'label': label, 'url': url};
  }

  factory ResumeLink.fromMap(Map<String, Object?> map) {
    return ResumeLink(
      label: map['label'] as String,
      url: map['url'] as String,
    );
  }

  /// Serializes a list of links into the string stored in
  /// [Resume.linksJson]. Returns null for an empty list rather than `'[]'`,
  /// matching [ChatSourceRef.encodeList]'s "null for none" convention.
  static String? encodeList(List<ResumeLink> links) {
    if (links.isEmpty) return null;
    return jsonEncode(links.map((l) => l.toMap()).toList());
  }

  /// Inverse of [encodeList]. Null/empty input decodes to an empty list.
  static List<ResumeLink> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    final decoded = jsonDecode(json) as List;
    return decoded.cast<Map<String, Object?>>().map(ResumeLink.fromMap).toList();
  }
}
