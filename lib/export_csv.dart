import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'intent_store.dart';

/// Exact CSV header order from docs/DATA_MODEL.md §9.
const List<String> exportCsvColumns = [
  'unlocked_at',
  'prompt_shown',
  'skip_reason',
  'intent_text',
  'intent_kind',
  'intent_source',
  'preset_label',
  'preset_id',
  'declared_at',
  'completed_at',
  'duration_seconds',
  'status',
];

/// Formats [rows] as a lossless CSV string (header + body). Timestamps are
/// ISO-8601 **local** (not epoch ms); empty cells stay empty rather than
/// inventing placeholders. RFC4180 escaping for commas/quotes/newlines.
String formatExportCsv(List<ExportRow> rows) {
  final buffer = StringBuffer();
  buffer.writeln(exportCsvColumns.join(','));
  for (final row in rows) {
    buffer.writeln([
      _csvField(_formatIsoLocal(row.unlockedAt)),
      _csvField(row.promptShown == null ? null : (row.promptShown! ? '1' : '0')),
      _csvField(row.skipReason),
      _csvField(row.intentText),
      _csvField(row.intentKind),
      _csvField(row.intentSource),
      _csvField(row.presetLabel),
      _csvField(row.presetId?.toString()),
      _csvField(_formatIsoLocal(row.declaredAt)),
      _csvField(_formatIsoLocal(row.completedAt)),
      _csvField(row.durationSeconds?.toString()),
      _csvField(row.status),
    ].join(','));
  }
  return buffer.toString();
}

String? _formatIsoLocal(DateTime? utcInstant) {
  if (utcInstant == null) return null;
  return utcInstant.toLocal().toIso8601String();
}

String _csvField(String? value) {
  if (value == null || value.isEmpty) return '';
  final needsQuotes = value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Injectable share hook — defaults to [Share.shareXFiles]. Widget tests
/// inject a no-op / recorder so they never touch a platform channel.
typedef CsvSharer = Future<void> Function(String filePath);

Future<void> _defaultShare(String filePath) async {
  await Share.shareXFiles(
    [XFile(filePath, mimeType: 'text/csv')],
    subject: 'Why Did I Unlock export',
  );
}

/// Opens a UI-engine store (`ownConnection: true`), builds the CSV, writes a
/// temp file, and hands it to the system share sheet. Failures propagate to
/// the caller (Settings shows a SnackBar).
Future<void> exportAndShareCsv({
  Future<IntentStore> Function()? openStore,
  CsvSharer? share,
  Directory? tempDirectory,
}) async {
  final store = await (openStore?.call() ?? IntentStore.open(ownConnection: true));
  try {
    final rows = await store.exportRows();
    final csv = formatExportCsv(rows);
    final dir = tempDirectory ?? Directory.systemTemp;
    final stamp = DateTime.now().toLocal().toIso8601String().replaceAll(':', '').replaceAll('.', '');
    final file = File(p.join(dir.path, 'why_did_i_unlock_export_$stamp.csv'));
    await file.writeAsString(csv);
    await (share ?? _defaultShare)(file.path);
  } finally {
    await store.close();
  }
}
