/// Serializes a calendar date without allowing a timezone offset to move it
/// to the previous or following day. Noon UTC is deliberately used because it
/// stays on the same civil date in every supported European timezone.
String dateOnlyForApi(DateTime value) => DateTime.utc(
      value.year,
      value.month,
      value.day,
      12,
    ).toIso8601String();

DateTime? dateOnlyFromApi(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  return DateTime(local.year, local.month, local.day);
}
