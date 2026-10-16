// Lists user-facing string literals that bypass localization.
//
//   dart run tool/check_hardcoded_strings.dart [paths...]   # report
//   dart run tool/check_hardcoded_strings.dart --check      # CI: fail if any
//
// Flags literals in Text(...), common text parameters (label:, title:, ...)
// and showMessage(...). Add `// l10n-ignore` to a line that is intentionally
// not translated (brand names, language names, debug-only text).
import 'dart:io';

final _patterns = [
  RegExp(r'''Text\(\s*['"][^'"]*[A-Za-z]{2}'''),
  RegExp(r'''\b(label|title|subtitle|message|hintText|labelText|helperText|errorText|tooltip|eyebrow|semanticLabel|semanticsLabel|actionLabel|secondaryLabel|description|body|reason|caption|heading)\s*:\s*['"][^'"]*[A-Za-z]{2}'''),
  RegExp(r'''showMessage\(\s*\w+\s*,\s*['"][^'"]*[A-Za-z]{2}'''),
  RegExp(r'''(SectionHeader|TagPill|EmptyState|ErrorState|LoadingState)\(\s*['"][^'"]*[A-Za-z]{2}'''),
];

void main(List<String> args) {
  final check = args.contains('--check');
  final roots = args.where((a) => !a.startsWith('--')).toList();
  final dirs = roots.isEmpty ? ['lib/features', 'lib/core'] : roots;
  var total = 0;
  for (final d in dirs) {
    final entity = FileSystemEntity.typeSync(d) == FileSystemEntityType.file ? [File(d)] : Directory(d).listSync(recursive: true).whereType<File>();
    for (final f in entity.where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('l10n-ignore') || line.trimLeft().startsWith('//')) continue;
        if (_patterns.any((p) => p.hasMatch(line))) {
          total++;
          stdout.writeln('${f.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
  }
  stdout.writeln('$total hard-coded user-facing strings');
  if (check && total > 0) exit(1);
}
