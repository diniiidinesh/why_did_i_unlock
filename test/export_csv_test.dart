import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/export_csv.dart';
import 'package:why_did_i_unlock/intent_store.dart';

void main() {
  test('header matches DATA_MODEL §9 column order exactly', () {
    final csv = formatExportCsv(const []);
    expect(
      csv.trimRight(),
      'unlocked_at,prompt_shown,skip_reason,intent_text,intent_kind,'
      'intent_source,preset_label,preset_id,declared_at,completed_at,'
      'duration_seconds,status',
    );
  });

  test('unlock-only row leaves outcome columns blank', () {
    final unlocked = DateTime.utc(2026, 7, 24, 10, 0, 0);
    final csv = formatExportCsv([
      ExportRow(
        unlockedAt: unlocked,
        promptShown: false,
        skipReason: 'cooldown',
      ),
    ]);
    final body = csv.trimRight().split('\n').last;
    final cells = _splitCsvLine(body);
    expect(cells[0], unlocked.toLocal().toIso8601String());
    expect(cells[1], '0');
    expect(cells[2], 'cooldown');
    expect(cells[3], '');
    expect(cells[4], '');
    expect(cells[10], '');
    expect(cells[11], '');
  });

  test('unlock+intent fills outcome columns and precomputes duration_seconds', () {
    final unlocked = DateTime.utc(2026, 7, 24, 10, 0, 0);
    final declared = DateTime.utc(2026, 7, 24, 10, 0, 5);
    final completed = DateTime.utc(2026, 7, 24, 10, 1, 5);
    final csv = formatExportCsv([
      ExportRow(
        unlockedAt: unlocked,
        promptShown: true,
        intentText: 'Payments',
        intentKind: 'intent',
        intentSource: 'preset',
        presetLabel: 'Payments',
        presetId: 1,
        declaredAt: declared,
        completedAt: completed,
        durationSeconds: 60,
        status: 'done',
      ),
    ]);
    final cells = _splitCsvLine(csv.trimRight().split('\n').last);
    expect(cells[3], 'Payments');
    expect(cells[4], 'intent');
    expect(cells[6], 'Payments');
    expect(cells[7], '1');
    expect(cells[10], '60');
    expect(cells[11], 'done');
  });

  test('orphan intent has blank unlock columns', () {
    final declared = DateTime.utc(2026, 7, 24, 11, 0, 0);
    final csv = formatExportCsv([
      ExportRow(
        intentText: 'Just Like That',
        intentKind: 'no_intent',
        declaredAt: declared,
        completedAt: declared,
        durationSeconds: 0,
        status: 'done',
      ),
    ]);
    final cells = _splitCsvLine(csv.trimRight().split('\n').last);
    expect(cells[0], '');
    expect(cells[1], '');
    expect(cells[3], 'Just Like That');
    expect(cells[4], 'no_intent');
    expect(cells[10], '0');
  });

  test('fields with commas and quotes are RFC4180-escaped', () {
    final csv = formatExportCsv([
      ExportRow(
        unlockedAt: DateTime.utc(2026, 1, 1),
        promptShown: true,
        intentText: 'Hello, "world"',
      ),
    ]);
    final cells = _splitCsvLine(csv.trimRight().split('\n').last);
    expect(cells[3], 'Hello, "world"');
  });
}

/// Minimal CSV line splitter that understands RFC4180 quotes — enough for
/// assertions without pulling in a CSV package.
List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}
