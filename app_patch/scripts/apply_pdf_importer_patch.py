from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return source.replace(old, new, 1)


def patch_importer() -> None:
    path = Path("lib/import/pdf_course_importer.dart")
    source = path.read_text()
    if "class ImportedCourse {" in source:
        print("PDF importer model patch already present")
        return

    source = replace_once(
        source,
        "import 'dart:typed_data';\n",
        "import 'dart:convert';\nimport 'dart:typed_data';\n",
        "import dart:convert",
    )
    source = replace_once(
        source,
        "/// One occurrence extracted from a single weekday cell in the timetable PDF.\nclass ImportedMeeting {\n  final String courseName;",
        """/// Stable course identity, independent of its timetable occurrences.\n/// Several ImportedMeeting records can reference the same ImportedCourse.\nclass ImportedCourse {\n  final String id;\n  final String name;\n  final String courseCode;\n  final String kind;\n  final bool online;\n\n  const ImportedCourse({\n    required this.id,\n    required this.name,\n    this.courseCode = '',\n    this.kind = '其他',\n    this.online = false,\n  });\n}\n\n/// One occurrence extracted from a single weekday cell in the timetable PDF.\nclass ImportedMeeting {\n  final String courseId;\n  final String courseName;""",
        "ImportedCourse model",
    )
    source = replace_once(
        source,
        "  const ImportedMeeting({\n    required this.courseName,",
        "  const ImportedMeeting({\n    this.courseId = '',\n    required this.courseName,",
        "ImportedMeeting courseId",
    )
    source = replace_once(
        source,
        "class PdfImportResult {\n  final String semester;\n  final List<ImportedMeeting> meetings;",
        "class PdfImportResult {\n  final String semester;\n  final List<ImportedCourse> courses;\n  final List<ImportedMeeting> meetings;",
        "PdfImportResult courses field",
    )
    source = replace_once(
        source,
        "  const PdfImportResult({\n    required this.semester,\n    required this.meetings,",
        "  const PdfImportResult({\n    required this.semester,\n    this.courses = const [],\n    required this.meetings,",
        "PdfImportResult courses constructor",
    )
    early_return = "          meetings: const [],\n          unscheduled: _parseUnscheduled(allText),"
    if source.count(early_return) != 2:
        raise SystemExit(f"early PdfImportResult courses: expected two matches, found {source.count(early_return)}")
    source = source.replace(early_return, "          courses: const [],\n" + early_return)
    source = replace_once(
        source,
        "      final meetings = <ImportedMeeting>[];\n      // The supplied timetable grid is split across pages 1 and 2.",
        "      final meetings = <ImportedMeeting>[];\n      final coursesById = <String, ImportedCourse>{};\n      // The supplied timetable grid is split across pages 1 and 2.",
        "course definition accumulator",
    )
    source = replace_once(
        source,
        "              final meeting = _parseBlock(block, day);",
        "              final meeting = _parseBlock(block, day, coursesById);",
        "parse block call",
    )
    source = replace_once(
        source,
        "        semester: semester,\n        meetings: List.unmodifiable(meetings),",
        "        semester: semester,\n        courses: List.unmodifiable(coursesById.values),\n        meetings: List.unmodifiable(meetings),",
        "final PdfImportResult courses",
    )
    source = replace_once(
        source,
        "  static ImportedMeeting? _parseBlock(List<_PdfLine> block, int day) {",
        "  static ImportedMeeting? _parseBlock(\n    List<_PdfLine> block,\n    int day,\n    Map<String, ImportedCourse> coursesById,\n  ) {",
        "parse block signature",
    )
    source = replace_once(
        source,
        "    final kind = titleLine.contains('○') ? '实验'\n        : titleLine.contains('●') ? '实践'\n        : titleLine.contains('◇') ? '上机'\n        : titleLine.contains('◆') ? '讨论' : '讲课';\n\n    return ImportedMeeting(\n      courseName: title,",
        """    final kind = titleLine.contains('○') ? '实验'\n        : titleLine.contains('●') ? '实践'\n        : titleLine.contains('◇') ? '上机'\n        : titleLine.contains('◆') ? '讨论' : '讲课';\n    final teachingClass = field('教学班');\n    final codeMatch = RegExp(\n      r'^\\(?\\d{4}-\\d{4}-\\d+\\)?-?(.+)$',\n    ).firstMatch(teachingClass);\n    final courseCode = codeMatch?.group(1)?.trim() ?? '';\n    final identity = courseCode.isNotEmpty ? courseCode : '$title|$kind';\n    final courseId = 'course_' + base64Url.encode(utf8.encode(identity)).replaceAll('=', '');\n    coursesById.putIfAbsent(\n      courseId,\n      () => ImportedCourse(\n        id: courseId,\n        name: title,\n        courseCode: courseCode,\n        kind: kind,\n      ),\n    );\n\n    return ImportedMeeting(\n      courseId: courseId,\n      courseName: title,""",
        "course definition linking",
    )

    # Generalize unscheduled-course parsing by section rather than hard-coding
    # the two names in the current sample PDF.
    start = source.index("  static List<UnscheduledImportedCourse> _parseUnscheduled(String allText) {")
    end = source.index("\n  /// Finds overlapping meetings week by week.", start)
    new_method = r'''  static List<UnscheduledImportedCourse> _parseUnscheduled(String allText) {
    final result = <UnscheduledImportedCourse>[];

    String section(String heading) {
      final startMatch = RegExp('$heading\\s*[:：]').firstMatch(allText);
      if (startMatch == null) return '';
      final remainder = allText.substring(startMatch.end);
      final nextHeading = RegExp(
        r'(?:实践课程|其他课程)\s*[:：]|★\s*[:：]',
      ).firstMatch(remainder);
      final end = nextHeading == null
          ? allText.length
          : startMatch.end + nextHeading.start;
      return allText.substring(startMatch.end, end);
    }

    void readSection(String heading, {required bool practice}) {
      final raw = section(heading);
      if (raw.isEmpty) return;
      for (final rawItem in raw.split(RegExp(r'[;；]'))) {
        final item = rawItem.trim();
        if (item.isEmpty) continue;
        final marker = RegExp(r'[★○●◇◆]').firstMatch(item);
        final name = (marker == null
                ? item.split(RegExp(r'[/（(]')).first
                : item.substring(0, marker.start))
            .trim();
        if (name.isEmpty) continue;

        final weeks = parseWeekNumbers(item);
        if (weeks.isEmpty) continue;
        final teacherMatch = marker == null
            ? null
            : RegExp(r'[★○●◇◆]\s*([^(/;；]+)').firstMatch(item);
        final teacher = teacherMatch?.group(1)?.trim() ?? '';
        final online = item.contains('线上') || item.contains('网络课程');
        final pathParts = item.split('/');
        final trailingNote = pathParts.length > 2
            ? pathParts.skip(2).join('/').trim()
            : '';
        final normalizedNote = trailingNote
            .replaceAll('“', '')
            .replaceAll('”', '')
            .replaceAll('，', '；')
            .replaceAll(RegExp(r'[。.]
        result.add(UnscheduledImportedCourse(
          name,
          Set.unmodifiable(weeks),
          teacher,
          note,
          online: online,
        ));
      }
    }

    readSection('实践课程', practice: true);
    readSection('其他课程', practice: false);
    return List.unmodifiable(result);
  }
'''
    source = source[:start] + new_method + source[end:]
    path.write_text(source)
    print("Patched PDF importer with linked course definitions and generic unscheduled parsing")


def patch_main_model() -> None:
    path = Path("lib/main.dart")
    source = path.read_text()
    if "final String courseId;" in source:
        print("Course courseId patch already present")
        return
    source = replace_once(source, "class Course {\n  final String name;", "class Course {\n  final String name;\n  final String courseId;", "Course field")
    source = replace_once(source, "    required this.name,\n    this.teacher = '',", "    required this.name,\n    this.courseId = '',\n    this.teacher = '',", "Course constructor")
    source = replace_once(source, "    'name': name, 'teacher': teacher,", "    'name': name, 'courseId': courseId, 'teacher': teacher,", "Course toJson")
    source = replace_once(source, "    String? name,\n    String? teacher,", "    String? name,\n    String? courseId,\n    String? teacher,", "Course copyWith args")
    source = replace_once(source, "    name: name ?? this.name,\n    teacher: teacher ?? this.teacher,", "    name: name ?? this.name,\n    courseId: courseId ?? this.courseId,\n    teacher: teacher ?? this.teacher,", "Course copyWith fields")
    dollar = chr(36)
    old_from_json = "    name: '" + dollar + "{j['name'] ?? ''}', teacher: '" + dollar + "{j['teacher'] ?? ''}',"
    new_from_json = "    name: '" + dollar + "{j['name'] ?? ''}', courseId: '" + dollar + "{j['courseId'] ?? ''}',\n    teacher: '" + dollar + "{j['teacher'] ?? ''}',"
    source = replace_once(source, old_from_json, new_from_json, "Course fromJson")
    source = replace_once(source, "    courseName: course.name,\n    weekday: course.weekday,", "    courseId: course.courseId,\n    courseName: course.name,\n    weekday: course.weekday,", "to imported meeting")
    source = replace_once(source, "      return Course(\n        name: m.courseName,", "      return Course(\n        name: m.courseName,\n        courseId: m.courseId,", "preview Course mapping")
    path.write_text(source)
    print("Patched timetable Course rows to retain normalized courseId")


def patch_header_word_bounds() -> None:
    path = Path("lib/import/pdf_course_importer.dart")
    source = path.read_text()
    if "weekdayHeaderWords" in source:
        print("Weekday word-bound extraction patch already present")
        return
    old_extract = """      final lines = <_PdfLine>[];

      for (var page = 0; page < document.pages.count; page++) {"""
    new_extract = """      final lines = <_PdfLine>[];
      final weekdayHeaderWords = <int, ({double x, double y})>{};
      const weekdayMap = {
        '一': 1, '二': 2, '三': 3, '四': 4,
        '五': 5, '六': 6, '日': 7, '天': 7,
      };
      final weekdayPattern = RegExp(r'星期([一二三四五六日天])');
      for (var page = 0; page < document.pages.count; page++) {"""
    source = replace_once(source, old_extract, new_extract, "weekday header map")
    old_add = """          lines.add(_PdfLine(
            page: page,
            centerX: center.dx,
            centerY: center.dy,
            text: text,
          ));"""
    new_add = """          lines.add(_PdfLine(
            page: page,
            centerX: center.dx,
            centerY: center.dy,
            text: text,
          ));
          if (page == 0) {
            final matches = weekdayPattern.allMatches(text).toList();
            if (matches.length == 1) {
              final match = matches.single;
              weekdayHeaderWords[weekdayMap[match.group(1)]!] =
                  (x: center.dx, y: center.dy);
            } else if (matches.length > 1) {
              // Syncfusion may combine all seven header labels into one visual
              // TextLine. Use each TextWord's own bounds instead of the
              // combined line center, otherwise only one weekday is found.
              for (final word in line.wordCollection) {
                final match = weekdayPattern.firstMatch(word.text);
                if (match == null) continue;
                final wordCenter = word.bounds.center;
                weekdayHeaderWords[weekdayMap[match.group(1)]!] =
                    (x: wordCenter.dx, y: wordCenter.dy);
              }
            }
          }"""
    source = replace_once(source, old_add, new_add, "weekday word bounds")
    old_headers = """      final headerPoints = <int, ({double x, double y})>{};
      for (final line in lines.where((l) => l.page == 0)) {
        final match = RegExp(r'星期([一二三四五六日天])').firstMatch(line.text);
        if (match == null) continue;
        const dayMap = {
          '一': 1, '二': 2, '三': 3, '四': 4,
          '五': 5, '六': 6, '日': 7, '天': 7,
        };
        headerPoints[dayMap[match.group(1)]!] =
            (x: line.centerX, y: line.centerY);
      }"""
    new_headers = "      final headerPoints = weekdayHeaderWords;"
    source = replace_once(source, old_headers, new_headers, "replace combined header center")
    path.write_text(source)
    print("Patched weekday header extraction to use per-word coordinates")


if __name__ == "__main__":
    patch_importer()
    patch_main_model()
    patch_header_word_bounds()
), '')
            .trim();
        final note = practice
            ? '实践课程；原 PDF 未指定星期和节次'
            : normalizedNote.isNotEmpty
                ? normalizedNote
                : online
                    ? '线上课程；原 PDF 未指定固定上课时间'
                    : '其他课程；原 PDF 未指定固定上课时间';
        result.add(UnscheduledImportedCourse(
          name,
          Set.unmodifiable(weeks),
          teacher,
          note,
          online: online,
        ));
      }
    }

    readSection('实践课程', practice: true);
    readSection('其他课程', practice: false);
    return List.unmodifiable(result);
  }
'''
    source = source[:start] + new_method + source[end:]
    path.write_text(source)
    print("Patched PDF importer with linked course definitions and generic unscheduled parsing")


def patch_main_model() -> None:
    path = Path("lib/main.dart")
    source = path.read_text()
    if "final String courseId;" in source:
        print("Course courseId patch already present")
        return
    source = replace_once(source, "class Course {\n  final String name;", "class Course {\n  final String name;\n  final String courseId;", "Course field")
    source = replace_once(source, "    required this.name,\n    this.teacher = '',", "    required this.name,\n    this.courseId = '',\n    this.teacher = '',", "Course constructor")
    source = replace_once(source, "    'name': name, 'teacher': teacher,", "    'name': name, 'courseId': courseId, 'teacher': teacher,", "Course toJson")
    source = replace_once(source, "    String? name,\n    String? teacher,", "    String? name,\n    String? courseId,\n    String? teacher,", "Course copyWith args")
    source = replace_once(source, "    name: name ?? this.name,\n    teacher: teacher ?? this.teacher,", "    name: name ?? this.name,\n    courseId: courseId ?? this.courseId,\n    teacher: teacher ?? this.teacher,", "Course copyWith fields")
    dollar = chr(36)
    old_from_json = "    name: '" + dollar + "{j['name'] ?? ''}', teacher: '" + dollar + "{j['teacher'] ?? ''}',"
    new_from_json = "    name: '" + dollar + "{j['name'] ?? ''}', courseId: '" + dollar + "{j['courseId'] ?? ''}',\n    teacher: '" + dollar + "{j['teacher'] ?? ''}',"
    source = replace_once(source, old_from_json, new_from_json, "Course fromJson")
    source = replace_once(source, "    courseName: course.name,\n    weekday: course.weekday,", "    courseId: course.courseId,\n    courseName: course.name,\n    weekday: course.weekday,", "to imported meeting")
    source = replace_once(source, "      return Course(\n        name: m.courseName,", "      return Course(\n        name: m.courseName,\n        courseId: m.courseId,", "preview Course mapping")
    path.write_text(source)
    print("Patched timetable Course rows to retain normalized courseId")


def patch_header_word_bounds() -> None:
    path = Path("lib/import/pdf_course_importer.dart")
    source = path.read_text()
    if "weekdayHeaderWords" in source:
        print("Weekday word-bound extraction patch already present")
        return
    old_extract = """      final lines = <_PdfLine>[];

      for (var page = 0; page < document.pages.count; page++) {"""
    new_extract = """      final lines = <_PdfLine>[];
      final weekdayHeaderWords = <int, ({double x, double y})>{};
      const weekdayMap = {
        '一': 1, '二': 2, '三': 3, '四': 4,
        '五': 5, '六': 6, '日': 7, '天': 7,
      };
      final weekdayPattern = RegExp(r'星期([一二三四五六日天])');
      for (var page = 0; page < document.pages.count; page++) {"""
    source = replace_once(source, old_extract, new_extract, "weekday header map")
    old_add = """          lines.add(_PdfLine(
            page: page,
            centerX: center.dx,
            centerY: center.dy,
            text: text,
          ));"""
    new_add = """          lines.add(_PdfLine(
            page: page,
            centerX: center.dx,
            centerY: center.dy,
            text: text,
          ));
          if (page == 0) {
            final matches = weekdayPattern.allMatches(text).toList();
            if (matches.length == 1) {
              final match = matches.single;
              weekdayHeaderWords[weekdayMap[match.group(1)]!] =
                  (x: center.dx, y: center.dy);
            } else if (matches.length > 1) {
              // Syncfusion may combine all seven header labels into one visual
              // TextLine. Use each TextWord's own bounds instead of the
              // combined line center, otherwise only one weekday is found.
              for (final word in line.wordCollection) {
                final match = weekdayPattern.firstMatch(word.text);
                if (match == null) continue;
                final wordCenter = word.bounds.center;
                weekdayHeaderWords[weekdayMap[match.group(1)]!] =
                    (x: wordCenter.dx, y: wordCenter.dy);
              }
            }
          }"""
    source = replace_once(source, old_add, new_add, "weekday word bounds")
    old_headers = """      final headerPoints = <int, ({double x, double y})>{};
      for (final line in lines.where((l) => l.page == 0)) {
        final match = RegExp(r'星期([一二三四五六日天])').firstMatch(line.text);
        if (match == null) continue;
        const dayMap = {
          '一': 1, '二': 2, '三': 3, '四': 4,
          '五': 5, '六': 6, '日': 7, '天': 7,
        };
        headerPoints[dayMap[match.group(1)]!] =
            (x: line.centerX, y: line.centerY);
      }"""
    new_headers = "      final headerPoints = weekdayHeaderWords;"
    source = replace_once(source, old_headers, new_headers, "replace combined header center")
    path.write_text(source)
    print("Patched weekday header extraction to use per-word coordinates")


if __name__ == "__main__":
    patch_importer()
    patch_main_model()
    patch_header_word_bounds()
