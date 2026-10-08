import 'package:flutter/material.dart';
import 'theme.dart';
import 'text.dart';

/// กราฟเส้นแนวโน้มอย่างง่าย ไม่พึ่ง package เสริม — ใช้กับอุณหภูมิและ THI
/// ใช้แบบ: TrendLineChart(title: 'อุณหภูมิ', values: [...], labels: [...], unit: '°C', color: ...)
class TrendLineChart extends StatelessWidget {
  final String title;
  final List<double> values;
  final List<String> labels; // แสดงใต้กราฟ (เช่น ชั่วโมง) — โชว์แค่บางจุดกันแน่นเกินไป
  final String unit;
  final Color color;
  final double? warningThreshold; // เส้นประบอกเกณฑ์เตือน (ถ้ามี)

  const TrendLineChart({
    super.key,
    required this.title,
    required this.values,
    required this.labels,
    required this.unit,
    required this.color,
    this.warningThreshold,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(child: Text('ยังไม่มีข้อมูลเพียงพอสำหรับกราฟ', style: AppTextStyles.bodySecondary)),
      );
    }

    final latest = values.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title, style: AppTextStyles.bodySecondary),
            const Spacer(),
            Text('${latest.toStringAsFixed(1)} $unit', style: AppTextStyles.subheading.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          width: double.infinity,
          child: CustomPaint(
            painter: _LineChartPainter(
              values: values,
              color: color,
              warningThreshold: warningThreshold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _buildLabelRow(),
      ],
    );
  }

  Widget _buildLabelRow() {
    // โชว์แค่ label แรก-กลาง-ท้าย กันตัวหนังสือแน่นเกินไปบนจอเล็ก
    if (labels.isEmpty) return const SizedBox.shrink();
    final first = labels.first;
    final last = labels.last;
    final middle = labels[labels.length ~/ 2];

    return Row(
      children: [
        Text(first, style: AppTextStyles.caption),
        Expanded(child: Center(child: Text(middle, style: AppTextStyles.caption))),
        Text(last, style: AppTextStyles.caption),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? warningThreshold;

  _LineChartPainter({required this.values, required this.color, this.warningThreshold});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs() < 0.01 ? 1 : maxVal - minVal;

    double yFor(double v) => size.height - ((v - minVal) / range) * size.height;
    double xFor(int i) => values.length <= 1 ? 0 : (i / (values.length - 1)) * size.width;

    // เส้นประบอกเกณฑ์เตือน (ถ้าอยู่ในช่วงข้อมูลที่มี)
    if (warningThreshold != null && warningThreshold! >= minVal && warningThreshold! <= maxVal) {
      final dashPaint = Paint()
        ..color = AppColors.warning.withOpacity(0.5)
        ..strokeWidth = 1;
      final y = yFor(warningThreshold!);
      const dashWidth = 4.0;
      double startX = 0;
      while (startX < size.width) {
        canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), dashPaint);
        startX += dashWidth * 2;
      }
    }

    // เส้นกราฟหลัก
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final point = Offset(xFor(i), yFor(values[i]));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // พื้นที่ใต้เส้น (ระบายจางๆ)
    final fillPath = Path.from(path)
      ..lineTo(xFor(values.length - 1), size.height)
      ..lineTo(xFor(0), size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withOpacity(0.08));

    // จุดสุดท้าย (ค่าล่าสุด) เน้นให้เห็นชัด
    final lastPoint = Offset(xFor(values.length - 1), yFor(values.last));
    canvas.drawCircle(lastPoint, 4, Paint()..color = color);
    canvas.drawCircle(lastPoint, 4, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}