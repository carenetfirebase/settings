// Merges per-area ARB parts into the two files gen-l10n reads, and checks
// that every English string has a French translation with the same
// placeholders.
//
//   dart run tool/merge_arb.dart          # write lib/l10n/arb/app_{en,fr}.arb
//   dart run tool/merge_arb.dart --check  # CI: fail if stale or incomplete
//
// Parts live in lib/l10n/parts/<area>_en.arb and <area>_fr.arb. Keys are
// lowerCamelCase, prefixed with the area (kitchenAddItem, commonCancel).
import 'dart:convert';
import 'dart:io';

final _placeholder = RegExp(r'\{(\w+)[,}]');

void main(List<String> args) {
  final check = args.contains('--check');
  final errors = <String>[];
  final en = <String, dynamic>{'@@locale': 'en'};
  final fr = <String, dynamic>{'@@locale': 'fr'};
  final parts = Directory('lib/l10n/parts').listSync().whereType<File>().where((f) => f.path.endsWith('_en.arb')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final owner = <String, String>{};
  for (final enFile in parts) {
    final area = enFile.uri.pathSegments.last.replaceAll('_en.arb', '');
    final frFile = File(enFile.path.replaceAll('_en.arb', '_fr.arb'));
    final e = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
    final f = frFile.existsSync() ? jsonDecode(frFile.readAsStringSync()) as Map<String, dynamic> : <String, dynamic>{};
    if (!frFile.existsSync()) errors.add('$area: missing ${frFile.path}');
    for (final entry in e.entries) {
      final k = entry.key;
      if (k.startsWith('@@')) continue;
      if (k.startsWith('@')) {
        en[k] = entry.value;
        continue;
      }
      if (owner.containsKey(k)) errors.add('$k is defined in both ${owner[k]} and $area');
      owner[k] = area;
      en[k] = entry.value;
      final t = f[k];
      if (t is! String || t.trim().isEmpty) {
        errors.add('$area: no French for $k');
        continue;
      }
      fr[k] = t;
      final pe = _placeholder.allMatches(entry.value as String).map((m) => m[1]).toSet();
      final pf = _placeholder.allMatches(t).map((m) => m[1]).toSet();
      if (!pe.containsAll(pf) || !pf.containsAll(pe.where((p) => !(entry.value as String).contains('$p, plural') && !(entry.value as String).contains('$p, select')))) {
        // Plural/select selectors may legitimately be absent from a branch.
        if (!pf.containsAll(pe) && pe.difference(pf).isNotEmpty) errors.add('$area: $k placeholders differ (en $pe, fr $pf)');
      }
    }
    for (final k in f.keys) {
      if (!k.startsWith('@') && !e.containsKey(k)) errors.add('$area: French has extra key $k');
    }
  }
  const encoder = JsonEncoder.withIndent('  ');
  final outputs = {'lib/l10n/arb/app_en.arb': '${encoder.convert(en)}\n', 'lib/l10n/arb/app_fr.arb': '${encoder.convert(fr)}\n'};
  outputs.forEach((path, content) {
    final file = File(path);
    if (check) {
      if (!file.existsSync() || file.readAsStringSync() != content) errors.add('$path is stale: run dart run tool/merge_arb.dart');
    } else {
      file.writeAsStringSync(content);
    }
  });
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exit(1);
  }
  stdout.writeln('${en.keys.where((k) => !k.startsWith('@')).length} strings, English and French complete.');
}
