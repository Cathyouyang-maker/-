// ===== 极简记账 · 自绘图表（饼图 / 柱状图），无第三方依赖 =====

import 'dart:math' as math;
import 'package:flutter/material.dart';

const Color kExpense = Color(0xFFDC2626);
const Color kIncome = Color(0xFF16A34A);
const Color kBlue = Color(0xFF2563EB);

const List<Color> _palette = [
  Color(0xFF2563EB), Color(0xFF3B82F6), Color(0xFF60A5FA), Color(0xFF7C3AED),
  Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFF14B8A6), Color(0xFFF59E0B),
  Color(0xFFF97316), Color(0xFFEF4444), Color(0xFFEC4899), Color(0xFF84CC16),
  Color(0xFF6366F1), Color(0xFFA855F7), Color(0xFF06B6D4),
];

String fmtNum(double n) {
  final s = n.toStringAsFixed(2);
  final i = s.substring(0, s.length - 3);
  final buf = StringBuffer();
  for (var k = 0; k < i.length; k++) {
    if (k > 0 && (i.length - k) % 3 == 0) buf.write(',');
    buf.write(i[k]);
  }
  return '$buf${s.substring(s.length - 3)}';
}

void _drawText(Canvas c, String s, Offset o, {double size = 11, Color color = const Color(0xFF9CA3AF), bool centerX = true}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, centerX ? o - Offset(tp.width / 2, tp.height / 2) : o);
}

// ---------- 饼图 ----------
class PieSlice {
  final String label;
  final double value;
  PieSlice(this.label, this.value);
}

class PieChartView extends StatelessWidget {
  final List<PieSlice> slices;
  const PieChartView({super.key, required this.slices});

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('本期暂无支出', style: TextStyle(color: Colors.grey))));
    }
    return Column(
      children: [
        SizedBox(
          width: 190,
          height: 190,
          child: CustomPaint(painter: _PiePainter(slices, total)),
        ),
        const SizedBox(height: 6),
        ...slices.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _palette[slices.indexOf(s) % _palette.length], borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  Text(fmtNum(s.value), style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(width: 12),
                  SizedBox(width: 40, child: Text('${(s.value / total * 100).round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: Colors.grey))),
                ],
              ),
            )),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<PieSlice> slices;
  final double total;
  _PiePainter(this.slices, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 6;
    final inner = r * 0.58;
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].value / total * 2 * math.pi;
      final paint = Paint()..style = PaintingStyle.fill..color = _palette[i % _palette.length];
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, true, paint);
      start += sweep;
    }
    canvas.drawCircle(c, inner, Paint()..color = Colors.white);
    _drawText(canvas, '支出', c - const Offset(0, 6), size: 13, color: Colors.grey);
    _drawText(canvas, fmtNum(total), c + const Offset(0, 14), size: 15, color: kExpense);
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.slices != slices;
}

// ---------- 柱状图 ----------
class BarBucket {
  final String label;
  final double expense;
  final double income;
  BarBucket(this.label, this.expense, this.income);
}

class BarChartView extends StatefulWidget {
  final List<BarBucket> buckets;
  final String mode; // both / expense / income
  const BarChartView({super.key, required this.buckets, this.mode = 'both'});
  @override
  State<BarChartView> createState() => _BarChartViewState();
}

class _BarChartViewState extends State<BarChartView> {
  int? _hover;
  static const double _slot = 30.0;
  static const double _padX = 10.0;
  static const double _tipW = 124.0;

  int? _indexFromDx(double dx) {
    final i = ((dx - _padX) / _slot).floor();
    if (i < 0 || i >= widget.buckets.length) return null;
    return i;
  }

  void _onPos(Offset p) => setState(() => _hover = _indexFromDx(p.dx));
  void _onEnd(_) => setState(() => _hover = null);

  @override
  Widget build(BuildContext context) {
    if (widget.buckets.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('暂无数据', style: TextStyle(color: Colors.grey))));
    }
    final slot = _slot;
    final width = math.max(widget.buckets.length * slot + 20, 280.0);
    final buckets = widget.buckets;
    final h = _hover != null && _hover! < buckets.length ? buckets[_hover!] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: 210,
            child: GestureDetector(
              onLongPressStart: (d) => _onPos(d.localPosition),
              onLongPressMoveUpdate: (d) => _onPos(d.localPosition),
              onLongPressEnd: _onEnd,
              child: Stack(
                children: [
                  CustomPaint(painter: _BarPainter(buckets, widget.mode, slot), size: Size(width, 210)),
                  if (h != null)
                    Positioned(top: 2, left: _tipLeft(_hover!, width), child: _tooltip(h)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.mode != 'income') ...[
              _dot(kExpense),
              const SizedBox(width: 4),
              const Text('支出', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 14),
            ],
            if (widget.mode != 'expense') ...[
              _dot(kIncome),
              const SizedBox(width: 4),
              const Text('收入', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(left: 2),
          child: Text('长按柱形查看具体数字', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ),
      ],
    );
  }

  double _tipLeft(int i, double width) {
    final cx = _padX + i * _slot + _slot / 2;
    var left = cx - _tipW / 2;
    if (left < 0) left = 0;
    if (left > width - _tipW) left = width - _tipW;
    return left;
  }

  Widget _tooltip(BarBucket b) {
    final items = <Widget>[Text(b.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))];
    if (widget.mode != 'income') items.add(Text('支出 ¥${fmtNum(b.expense)}', style: const TextStyle(color: kExpense, fontSize: 12)));
    if (widget.mode != 'expense') items.add(Text('收入 ¥${fmtNum(b.income)}', style: TextStyle(color: kIncome, fontSize: 12)));
    return Container(
      width: _tipW,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: items),
    );
  }

  Widget _dot(Color c) => Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));
}

class _BarPainter extends CustomPainter {
  final List<BarBucket> buckets;
  final String mode;
  final double slot;
  _BarPainter(this.buckets, this.mode, this.slot);

  @override
  void paint(Canvas canvas, Size size) {
    final showE = mode != 'income';
    final showI = mode != 'expense';
    final maxV = math.max(1.0, buckets.fold<double>(0, (m, b) => math.max(m, math.max(showE ? b.expense : 0, showI ? b.income : 0))));
    const padTop = 20.0, padB = 26.0, padX = 10.0;
    final plotH = size.height - padTop - padB;

    final grid = Paint()..strokeWidth = 1..color = const Color(0xFFF0F1F4);
    for (var g = 1; g <= 3; g++) {
      final y = padTop + plotH - plotH * g / 3;
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), grid);
    }
    canvas.drawLine(Offset(padX, padTop + plotH), Offset(size.width - padX, padTop + plotH), Paint()..strokeWidth = 1..color = const Color(0xFFE5E7EB));

    final bw = mode == 'both' ? 10.0 : 12.0;
    final gap = 2.0;
    for (var i = 0; i < buckets.length; i++) {
      final b = buckets[i];
      final cx = padX + i * slot + slot / 2;
      if (showE && b.expense > 0) {
        final h = math.max(3.0, b.expense / maxV * plotH);
        final x = mode == 'both' ? cx - bw - gap / 2 : cx - bw / 2;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, padTop + plotH - h, bw, h), const Radius.circular(2)), Paint()..color = kExpense);
      }
      if (showI && b.income > 0) {
        final h = math.max(3.0, b.income / maxV * plotH);
        final x = mode == 'both' ? cx + gap / 2 : cx - bw / 2;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, padTop + plotH - h, bw, h), const Radius.circular(2)), Paint()..color = kIncome);
      }
      if (b.label.isNotEmpty) {
        _drawText(canvas, b.label, Offset(cx, size.height - 10), size: 10);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.buckets != buckets || old.mode != mode;
}
