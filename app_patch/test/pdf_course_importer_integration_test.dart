import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:ketishiguang/import/pdf_course_importer.dart';

Future<Uint8List> _buildSyntheticTimetablePdf() async {
  final document = PdfDocument();
  document.pageSettings.size = PdfPageSize.a4;
  document.pageSettings.rotate = PdfPageRotateAngle.rotateAngle90;
  final font = PdfCjkStandardFont(PdfCjkFontFamily.heiseiMinchoW3, 8);

  void drawLine(PdfPage page, String text, double centerX, double y) {
    final width = font.measureString(text).width;
    page.graphics.drawString(
      text,
      font,
      brush: PdfBrushes.black,
      bounds: Rect.fromLTWH(centerX - width / 2, y, width + 2, 14),
    );
  }

  final grid = document.pages.add();
  drawLine(grid, '2026-2027学年第1学期', 297, 20);
  const dayNames = ['一', '二', '三', '四', '五', '六', '日'];
  final dayCenters = <int, double>{
    for (var day = 1; day <= 7; day++) day: 45 + day * 72,
  };
  for (var day = 1; day <= 7; day++) {
    drawLine(grid, '星期${dayNames[day - 1]}', dayCenters[day]!, 60);
  }

  final monday = dayCenters[1]!;
  drawLine(grid, '化工原理Ⅱ★', monday, 120);
  drawLine(grid, '(1-2节)1-14周/校区:常青花园', monday, 135);
  drawLine(grid, '/场地:A101/教师:教师甲', monday, 150);
  drawLine(grid, '/教学班:(2026-2027-1)-TEST001', monday, 165);

  final wednesday = dayCenters[3]!;
  drawLine(grid, '化工原理Ⅱ★', wednesday, 120);
  drawLine(grid, '(3-4节)1-14周/校区:常青花园', wednesday, 135);
  drawLine(grid, '/场地:B202/教师:教师丙', wednesday, 150);
  drawLine(grid, '/教学班:(2026-2027-1)-TEST001', wednesday, 165);

  final thursday = dayCenters[4]!;
  drawLine(grid, '化工原理实验Ⅱ○', thursday, 120);
  drawLine(grid, '(5-8节)第6周/校区:常青花园', thursday, 135);
  drawLine(grid, '/场地:实验室/教师:教师乙', thursday, 150);
  drawLine(grid, '/教学班:(2026-2027-1)-TEST002', thursday, 165);

  final notes = document.pages.add();
  drawLine(notes, '实践课程：认识实习●教师甲(共1周)/第19周;', 250, 80);
  drawLine(
    notes,
    '其他课程：线上选修（通识）★网络教师(共15周)/4-18周/线上课程，上课方式及时间另行通知。;',
    250,
    100,
  );

  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

String _formatWeekExpression(List<int> source) {
  final weeks = source.toList()..sort();
  if (weeks.isEmpty) return '';
  final parts = <String>[];
  var start = weeks.first;
  var previous = start;
  for (final week in weeks.skip(1)) {
    if (week == previous + 1) {
      previous = week;
      continue;
    }
    parts.add(start == previous ? '$start周' : '$start-$previous周');
    start = previous = week;
  }
  parts.add(start == previous ? '$start周' : '$start-$previous周');
  return parts.join(',');
}

List<String> _chunks(String value, int size) {
  final result = <String>[];
  for (var offset = 0; offset < value.length; offset += size) {
    final end = offset + size < value.length ? offset + size : value.length;
    result.add(value.substring(offset, end));
  }
  return result;
}

Future<Uint8List> _buildGoldenSchedulePdf(
  Map<String, dynamic> fixture,
) async {
  final document = PdfDocument();
  document.pageSettings.size = PdfPageSize.a4;
  document.pageSettings.rotate = PdfPageRotateAngle.rotateAngle90;
  final font = PdfCjkStandardFont(PdfCjkFontFamily.heiseiMinchoW3, 5);

  void drawLine(PdfPage page, String text, double centerX, double y) {
    final width = font.measureString(text).width;
    page.graphics.drawString(
      text,
      font,
      brush: PdfBrushes.black,
      bounds: Rect.fromLTWH(centerX - width / 2, y, width + 2, 12),
    );
  }

  const dayNames = ['一', '二', '三', '四', '五', '六', '日'];
  final dayCenters = <int, double>{
    for (var day = 1; day <= 7; day++) day: 45 + day * 72,
  };
  final fixed = (fixture['fixedMeetings'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  final codeByCourse = <String, String>{};

  String markerForSource(String source) {
    for (final marker in ['★', '○', '●', '◇', '◆']) {
      if (source.contains(marker)) return marker;
    }
    return '★';
  }

  String kindForMarker(String marker) => switch (marker) {
        '○' => '实验',
        '●' => '实践',
        '◇' => '上机',
        '◆' => '讨论',
        _ => '讲课',
      };

  String codeFor(Map<String, dynamic> meeting) {
    final marker = markerForSource(meeting['kind'] as String);
    final key = '${meeting['courseName']}|$marker';
    return codeByCourse.putIfAbsent(
      key,
      () => 'GOLD${(codeByCourse.length + 1).toString().padLeft(3, '0')}',
    );
  }

  for (var pageIndex = 0; pageIndex < 2; pageIndex++) {
    final page = document.pages.add();
    if (pageIndex == 0) {
      drawLine(page, '2026-2027学年第1学期', 297, 20);
      for (var day = 1; day <= 7; day++) {
        drawLine(page, '星期${dayNames[day - 1]}', dayCenters[day]!, 60);
      }
    }

    for (var day = 1; day <= 7; day++) {
      final dayRows = fixed.where((meeting) {
        final start = (meeting['startSection'] as num).toInt();
        return meeting['weekday'] == day &&
            (pageIndex == 0 ? start <= 4 : start >= 5);
      }).toList()
        ..sort((a, b) {
          final section = (a['startSection'] as num)
              .compareTo(b['startSection'] as num);
          if (section != 0) return section;
          return (a['courseName'] as String)
              .compareTo(b['courseName'] as String);
        });

      for (var slot = 0; slot < dayRows.length; slot++) {
        final meeting = dayRows[slot];
        final name = meeting['courseName'] as String;
        final sourceKind = meeting['kind'] as String;
        final marker = markerForSource(sourceKind);
        final start = (meeting['startSection'] as num).toInt();
        final end = (meeting['endSection'] as num).toInt();
        final weeks = (meeting['weeks'] as List).cast<int>();
        final campus = meeting['campus'] as String;
        final room = meeting['room'] as String;
        final teacher = meeting['teacher'] as String;
        final code = codeFor(meeting);
        final baseY = 90.0 + slot * 180.0;

        // Keep the marker on the title line so the parser can reliably start
        // a new course block. Remaining text is split into short visual lines;
        // the parser joins them before extracting slash-delimited fields.
        drawLine(page, '$name$marker', dayCenters[day]!, baseY);
        final details =
            '($start-$end节)${_formatWeekExpression(weeks)}/校区:$campus'
            '/场地:$room/教师:$teacher/教学班:(2026-2027-1)-$code';
        var lineY = baseY + 12;
        for (final chunk in _chunks(details, 8)) {
          drawLine(page, chunk, dayCenters[day]!, lineY);
          lineY += 12;
        }
      }
    }
  }

  final notes = document.pages.add();
  final unscheduled = (fixture['unscheduled'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  for (final item in unscheduled) {
    final name = item['name'] as String;
    final teacher = item['teacher'] as String;
    final weeks = (item['weeks'] as List).cast<int>();
    final expression = _formatWeekExpression(weeks);
    final count = weeks.length;
    final online = item['online'] == true;
    final prefix = online ? '其他课程：' : '实践课程：';
    final marker = online ? '★' : '●';
    final sourceNote =
        online ? (item['note'] as String).replaceAll('；', '，') : '';
    final note = online && sourceNote.isNotEmpty ? '/$sourceNote。' : '';
    drawLine(
      notes,
      '$prefix$name$marker$teacher(共${count}周)/$expression$note;',
      250,
      online ? 110 : 80,
    );
  }

  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

void main() {
  test('旋转90度 PDF 可拆分课程与时段并识别非固定安排', () async {
    final bytes = await _buildSyntheticTimetablePdf();
    final diagnosticDocument = PdfDocument(inputBytes: bytes);
    for (final line in PdfTextExtractor(diagnosticDocument).extractTextLines()) {
      print('PDF_LINE ${line.text} @ ${line.bounds.center}');
    }
    diagnosticDocument.dispose();
    final result = await PdfCourseImporter.parse(bytes);
    print('PDF_RESULT meetings=${result.meetings.length} issues=${result.issues.map((e) => e.message).join(' | ')}');

    expect(result.semester, '2026-2027学年第1学期');
    expect(result.meetings, hasLength(3));
    expect(result.courses, hasLength(2));

    final chemistryMeetings = result.meetings
        .where((m) => m.courseName == '化工原理Ⅱ')
        .toList();
    expect(chemistryMeetings, hasLength(2));
    expect(chemistryMeetings.map((m) => m.courseId).toSet(), hasLength(1));
    expect(
      chemistryMeetings.any((m) =>
          m.weekday == 1 &&
          m.startSection == 1 &&
          m.endSection == 2 &&
          m.weeks.length == 14),
      isTrue,
    );
    expect(
      chemistryMeetings.any((m) =>
          m.weekday == 3 &&
          m.startSection == 3 &&
          m.endSection == 4 &&
          m.weeks.length == 14),
      isTrue,
    );
    expect(
      result.meetings.any((m) =>
          m.courseName == '化工原理实验Ⅱ' &&
          m.weekday == 4 &&
          m.startSection == 5 &&
          m.endSection == 8 &&
          m.weeks.length == 1 &&
          m.weeks.contains(6)),
      isTrue,
    );

    expect(result.unscheduled, hasLength(2));
    expect(
      result.unscheduled.any((c) =>
          c.name == '认识实习' &&
          c.weeks.length == 1 &&
          c.weeks.contains(19)),
      isTrue,
    );
    expect(
      result.unscheduled.any((c) =>
          c.name == '线上选修（通识）' &&
          c.online &&
          c.weeks.length == 15),
      isTrue,
    );
    expect(result.issues, isEmpty);
  });

  test('完整课程基准可从多页旋转PDF恢复23条安排与2条非固定课程',
      () async {
    final fixture = jsonDecode(
      await File('test/fixtures/expected_schedule.json').readAsString(),
    ) as Map<String, dynamic>;
    final bytes = await _buildGoldenSchedulePdf(fixture);
    final result = await PdfCourseImporter.parse(bytes);

    expect(result.semester, fixture['semester']);
    expect(result.meetings, hasLength(23));
    expect(result.unscheduled, hasLength(2));
    expect(result.issues, isEmpty);

    String meetingKey({
      required String name,
      required int weekday,
      required int start,
      required int end,
      required List<int> weeks,
      required String teacher,
      required String room,
      required String campus,
      required String kind,
    }) =>
        '$name|$weekday|$start-$end|${weeks.join(',')}|$teacher|$room|$campus|$kind';

    final expectedMeetings = (fixture['fixedMeetings'] as List).map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      final weeks = (m['weeks'] as List).cast<int>()..sort();
      return meetingKey(
        name: m['courseName'] as String,
        weekday: (m['weekday'] as num).toInt(),
        start: (m['startSection'] as num).toInt(),
        end: (m['endSection'] as num).toInt(),
        weeks: weeks,
        teacher: m['teacher'] as String,
        room: m['room'] as String,
        campus: m['campus'] as String,
        kind: kindForMarker(markerForSource(m['kind'] as String)),
      );
    }).toList();

    final actualMeetings = result.meetings.map((m) {
      final weeks = m.weeks.toList()..sort();
      return meetingKey(
        name: m.courseName,
        weekday: m.weekday,
        start: m.startSection,
        end: m.endSection,
        weeks: weeks,
        teacher: m.teacher,
        room: m.room,
        campus: m.campus,
        kind: m.kind,
      );
    }).toList();
    expect(actualMeetings, unorderedEquals(expectedMeetings));

    final expectedUnscheduled =
        (fixture['unscheduled'] as List).map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      final weeks = (m['weeks'] as List).cast<int>()..sort();
      return '${m['name']}|${weeks.join(',')}|${m['teacher']}|${m['online']}|${m['note']}';
    }).toList();
    final actualUnscheduled = result.unscheduled.map((m) {
      final weeks = m.weeks.toList()..sort();
      return '${m.name}|${weeks.join(',')}|${m.teacher}|${m.online}|${m.note}';
    }).toList();
    expect(actualUnscheduled, unorderedEquals(expectedUnscheduled));

    final expectedCourseKeys = (fixture['fixedMeetings'] as List).map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      return '${m['courseName']}|${kindForMarker(markerForSource(m['kind'] as String))}';
    }).toSet();
    final actualCourseKeys = result.courses
        .map((course) => '${course.name}|${course.kind}')
        .toSet();
    expect(actualCourseKeys, unorderedEquals(expectedCourseKeys));
    expect(result.courses, hasLength(expectedCourseKeys.length));

    final idsByCourse = <String, Set<String>>{};
    for (final meeting in result.meetings) {
      final key = '${meeting.courseName}|${meeting.kind}';
      idsByCourse.putIfAbsent(key, () => <String>{}).add(meeting.courseId);
    }
    expect(idsByCourse.values.every((ids) => ids.length == 1), isTrue);

    final courseIds = result.courses.map((course) => course.id).toSet();
    expect(
      result.meetings.every((meeting) => courseIds.contains(meeting.courseId)),
      isTrue,
    );
    expect(
      PdfCourseImporter.findConflicts(result.meetings, maxWeek: 20),
      isEmpty,
    );
  });
}
