enum CompetitionImportFormat { csv, ics }

enum CompetitionImportAction { create, update, skip, conflict, invalid }

T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final normalized = raw?.toString().toLowerCase();
  return values.where((item) => item.name == normalized).firstOrNull ??
      fallback;
}

class CompetitionImportPreview {
  const CompetitionImportPreview({
    required this.id,
    required this.totalRows,
    required this.createCount,
    required this.updateCount,
    required this.skipCount,
    required this.conflictCount,
    required this.invalidCount,
    required this.rows,
  });

  final String id;
  final int totalRows;
  final int createCount;
  final int updateCount;
  final int skipCount;
  final int conflictCount;
  final int invalidCount;
  final List<CompetitionImportRow> rows;

  factory CompetitionImportPreview.fromJson(Map<String, dynamic> json) =>
      CompetitionImportPreview(
        id: json['id'] as String,
        totalRows: json['totalRows'] as int? ?? 0,
        createCount: json['createCount'] as int? ?? 0,
        updateCount: json['updateCount'] as int? ?? 0,
        skipCount: json['skipCount'] as int? ?? 0,
        conflictCount: json['conflictCount'] as int? ?? 0,
        invalidCount: json['invalidCount'] as int? ?? 0,
        rows: (json['rows'] as List<dynamic>? ?? const [])
            .map(
              (item) => CompetitionImportRow.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class CompetitionImportRow {
  const CompetitionImportRow({
    required this.rowNumber,
    required this.action,
    required this.messages,
    this.externalId,
    this.opponent,
    this.startAt,
    this.isHome,
    this.competition,
    this.location,
    this.opponentId,
    this.opponentClubName,
    this.opponentTeamDesignation,
  });

  final int rowNumber;
  final CompetitionImportAction action;
  final String? externalId;
  final String? opponent;
  final DateTime? startAt;
  final bool? isHome;
  final String? competition;
  final String? location;
  final String? opponentId;
  final String? opponentClubName;
  final String? opponentTeamDesignation;
  final List<String> messages;

  factory CompetitionImportRow.fromJson(Map<String, dynamic> json) {
    final normalized = json['normalized'] as Map<String, dynamic>?;
    return CompetitionImportRow(
      rowNumber: json['rowNumber'] as int? ?? 0,
      action: _enum(
        CompetitionImportAction.values,
        json['action'],
        CompetitionImportAction.invalid,
      ),
      externalId: json['externalId'] as String?,
      opponent: normalized?['opponent'] as String?,
      startAt: normalized?['startAt'] == null
          ? null
          : DateTime.parse(normalized!['startAt'] as String),
      isHome: normalized?['isHome'] as bool?,
      competition: normalized?['competition'] as String?,
      location: normalized?['location'] as String?,
      opponentId: normalized?['opponentId'] as String?,
      opponentClubName: normalized?['opponentClubName'] as String?,
      opponentTeamDesignation:
          normalized?['opponentTeamDesignation'] as String?,
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}
