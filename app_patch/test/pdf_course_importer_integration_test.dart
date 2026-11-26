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

void main() {
  test('旋转90度 PDF 可拆分课程与时段并识别非固定安排', () async {
    final result = await PdfCourseImporter.parse(
      await _buildSyntheticTimetablePdf(),
    );

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
}
