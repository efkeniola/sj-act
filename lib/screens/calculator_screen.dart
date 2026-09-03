import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ACT Calculator — TI-30 equivalent functions allowed on the real ACT.
// Standard tab: basic arithmetic + memory.
// Scientific tab: trig, logs, powers, roots — exactly what ACT math needs.
// ═══════════════════════════════════════════════════════════════════════════════

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ACT Calculator'),
      bottom: TabBar(
        controller: _tab,
        indicatorColor: Colors.white,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        tabs: const [Tab(text: 'Standard'), Tab(text: 'Scientific')],
      ),
    ),
    body: TabBarView(
      controller: _tab,
      children: const [_StandardCalc(), _ScientificCalc()],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared engine
// ─────────────────────────────────────────────────────────────────────────────
class _Engine {
  String display = '0';
  String expression = '';
  double _stored = 0;
  String _pendingOp = '';
  bool _newEntry = true;
  double? _mem;

  void press(String t) {
    switch (t) {
      case 'AC': _ac(); break;
      case 'CE': display = '0'; _newEntry = true; break;
      case '⌫': _back(); break;
      case '=': _calc(); break;
      case '+/-': _negate(); break;
      case '%': _pct(); break;
      case 'MR': if (_mem != null) { display = _fmt(_mem!); _newEntry = true; } break;
      case 'MS': _mem = double.tryParse(display); break;
      case 'M+': _mem = (_mem ?? 0) + (double.tryParse(display) ?? 0); break;
      case 'MC': _mem = null; break;
      default:
        if (['+', '−', '×', '÷', 'xʸ'].contains(t)) { _applyOp(t); }
        else if (t == '.') { _dot(); }
        else { _digit(t); }
    }
  }

  void fn(String f) {
    final v = double.tryParse(display) ?? 0;
    double r;
    switch (f) {
      case 'sin':   r = sin(v * pi / 180); break;
      case 'cos':   r = cos(v * pi / 180); break;
      case 'tan':   r = tan(v * pi / 180); break;
      case 'sin⁻¹': r = asin(v.clamp(-1,1)) * 180 / pi; break;
      case 'cos⁻¹': r = acos(v.clamp(-1,1)) * 180 / pi; break;
      case 'tan⁻¹': r = atan(v) * 180 / pi; break;
      case 'ln':    r = v > 0 ? log(v) : double.nan; break;
      case 'log':   r = v > 0 ? log(v) / ln10 : double.nan; break;
      case 'eˣ':    r = exp(v); break;
      case '10ˣ':   r = pow(10, v).toDouble(); break;
      case 'x²':    r = v * v; break;
      case '√':     r = v >= 0 ? sqrt(v) : double.nan; break;
      case '1/x':   r = v != 0 ? 1 / v : double.nan; break;
      case 'π':     display = _fmt(pi); expression = 'π'; _newEntry = true; return;
      case 'e':     display = _fmt(e); expression = 'e'; _newEntry = true; return;
      case 'n!':    r = _fact(v.toInt()).toDouble(); break;
      case 'abs':   r = v.abs(); break;
      default: return;
    }
    expression = '$f(${display}) =';
    display = _fmt(r);
    _newEntry = true;
  }

  int _fact(int n) {
    if (n < 0 || n > 20) return -1;
    int r = 1; for (int i = 2; i <= n; i++) r *= i; return r;
  }

  void _ac() { display = '0'; expression = ''; _stored = 0; _pendingOp = ''; _newEntry = true; }
  void _back() {
    if (_newEntry) return;
    display = display.length > 1 ? display.substring(0, display.length - 1) : '0';
    if (display == '-') { display = '0'; _newEntry = true; }
  }
  void _digit(String d) {
    if (_newEntry) { display = d; _newEntry = false; }
    else { display = display == '0' ? d : (display.length < 14 ? display + d : display); }
  }
  void _dot() {
    if (_newEntry) { display = '0.'; _newEntry = false; return; }
    if (!display.contains('.')) display += '.';
  }
  void _negate() { display = display.startsWith('-') ? display.substring(1) : (display == '0' ? '0' : '-$display'); }
  void _pct() { display = _fmt((double.tryParse(display) ?? 0) / 100); _newEntry = true; }
  void _applyOp(String o) {
    if (_pendingOp.isNotEmpty && !_newEntry) _calc(keep: true);
    _stored = double.tryParse(display) ?? 0;
    _pendingOp = o;
    expression = '${display} $o';
    _newEntry = true;
  }
  void _calc({bool keep = false}) {
    if (_pendingOp.isEmpty) return;
    final cur = double.tryParse(display) ?? 0;
    double r;
    switch (_pendingOp) {
      case '+':  r = _stored + cur; break;
      case '−':  r = _stored - cur; break;
      case '×':  r = _stored * cur; break;
      case '÷':  r = cur == 0 ? double.infinity : _stored / cur; break;
      case 'xʸ': r = pow(_stored, cur).toDouble(); break;
      default:   r = cur;
    }
    expression = '${_stored} ${_pendingOp} ${cur} =';
    display = _fmt(r);
    if (!keep) _pendingOp = '';
    _newEntry = true;
  }

  String _fmt(double v) {
    if (v.isNaN) return 'Error';
    if (v.isInfinite) return v > 0 ? '∞' : '-∞';
    if (v == v.truncateToDouble() && v.abs() < 1e12) return v.toInt().toString();
    String s = v.toStringAsPrecision(10);
    if (s.contains('.')) s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  // Show fraction equivalent if value is rational
  String? get fraction {
    final v = double.tryParse(display);
    if (v == null || v.isNaN || v.isInfinite) return null;
    if (v == v.truncateToDouble()) return null; // already integer
    for (int d = 2; d <= 1000; d++) {
      final n = (v * d).round();
      if ((v - n / d).abs() < 1e-9) {
        int g = _gcd(n.abs(), d);
        final fn = n ~/ g, fd = d ~/ g;
        return fd == 1 ? '$fn' : '$fn/$fd';
      }
    }
    return null;
  }
  int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
}

// ─────────────────────────────────────────────────────────────────────────────
// Button style
// ─────────────────────────────────────────────────────────────────────────────
class _Btn extends StatelessWidget {
  final String label;
  final Color bg, fg;
  final VoidCallback onTap;
  final int flex;
  final double fontSize;

  const _Btn(this.label, {
    required this.bg, required this.fg, required this.onTap,
    this.flex = 1, this.fontSize = 20,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 2, offset: const Offset(0,1))],
        ),
        child: Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: Text(label, style: TextStyle(color: fg, fontSize: fontSize, fontWeight: FontWeight.w500)))),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Standard Calculator
// ─────────────────────────────────────────────────────────────────────────────
class _StandardCalc extends StatefulWidget {
  const _StandardCalc();
  @override
  State<_StandardCalc> createState() => _StandardCalcState();
}

class _StandardCalcState extends State<_StandardCalc> {
  final _e = _Engine();
  void _t(String t) => setState(() => _e.press(t));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final d1 = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD4D4D4);
    final d2 = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final fg = isDark ? Colors.white : Colors.black;
    const op = Color(0xFFFF9F0A);

    return Column(children: [
      // Display
      Container(
        color: isDark ? Colors.black : Colors.white,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_e.expression, style: TextStyle(fontSize: 13, color: ActColors.midGray),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
            child: Text(_e.display, style: TextStyle(fontSize: 52, fontWeight: FontWeight.w200,
              color: isDark ? Colors.white : Colors.black))),
          if (_e.fraction != null)
            Text('= ${_e.fraction}', style: TextStyle(fontSize: 12, color: ActColors.primary)),
          if (_e._mem != null)
            Text('M: ${_e._fmt(_e._mem!)}', style: TextStyle(fontSize: 11, color: ActColors.primary)),
        ]),
      ),
      Expanded(child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          Row(children: [_Btn('MC',bg:d1,fg:fg,onTap:()=>_t('MC'),fontSize:14), _Btn('MR',bg:d1,fg:fg,onTap:()=>_t('MR'),fontSize:14), _Btn('MS',bg:d1,fg:fg,onTap:()=>_t('MS'),fontSize:14), _Btn('M+',bg:d1,fg:fg,onTap:()=>_t('M+'),fontSize:14)]),
          Row(children: [_Btn('AC',bg:d1,fg:fg,onTap:()=>_t('AC')), _Btn('+/-',bg:d1,fg:fg,onTap:()=>_t('+/-')), _Btn('%',bg:d1,fg:fg,onTap:()=>_t('%')), _Btn('÷',bg:op,fg:Colors.black,onTap:()=>_t('÷'))]),
          Row(children: [_Btn('7',bg:d2,fg:fg,onTap:()=>_t('7')), _Btn('8',bg:d2,fg:fg,onTap:()=>_t('8')), _Btn('9',bg:d2,fg:fg,onTap:()=>_t('9')), _Btn('×',bg:op,fg:Colors.black,onTap:()=>_t('×'))]),
          Row(children: [_Btn('4',bg:d2,fg:fg,onTap:()=>_t('4')), _Btn('5',bg:d2,fg:fg,onTap:()=>_t('5')), _Btn('6',bg:d2,fg:fg,onTap:()=>_t('6')), _Btn('−',bg:op,fg:Colors.black,onTap:()=>_t('−'))]),
          Row(children: [_Btn('1',bg:d2,fg:fg,onTap:()=>_t('1')), _Btn('2',bg:d2,fg:fg,onTap:()=>_t('2')), _Btn('3',bg:d2,fg:fg,onTap:()=>_t('3')), _Btn('+',bg:op,fg:Colors.black,onTap:()=>_t('+'))]),
          Row(children: [_Btn('0',bg:d2,fg:fg,onTap:()=>_t('0'),flex:2), _Btn('.',bg:d2,fg:fg,onTap:()=>_t('.')), _Btn('=',bg:ActColors.primary,fg:Colors.white,onTap:()=>_t('='))]),
        ]),
      )),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scientific Calculator — ACT-legal functions only
// ─────────────────────────────────────────────────────────────────────────────
class _ScientificCalc extends StatefulWidget {
  const _ScientificCalc();
  @override
  State<_ScientificCalc> createState() => _ScientificCalcState();
}

class _ScientificCalcState extends State<_ScientificCalc> {
  final _e = _Engine();
  bool _inv = false;
  void _t(String t) => setState(() => _e.press(t));
  void _f(String f) => setState(() => _e.fn(f));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final d1 = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD4D4D4);
    final d2 = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final fn = isDark ? const Color(0xFF48484A) : const Color(0xFFBEBEC2);
    final fg = isDark ? Colors.white : Colors.black;
    final inv = _inv ? ActColors.primary : fn;
    const op = Color(0xFFFF9F0A);

    Widget f(String lbl, String fnName, {Color? bg, double fs = 14}) =>
      _Btn(lbl, bg: bg ?? fn, fg: fg, onTap: () => _f(fnName), fontSize: fs);
    Widget b(String lbl, {Color? bg, Color? fgc, double fs = 20}) =>
      _Btn(lbl, bg: bg ?? d2, fg: fgc ?? fg, onTap: () => _t(lbl), fontSize: fs);

    return Column(children: [
      // Display
      Container(
        color: isDark ? Colors.black : Colors.white,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_e.expression, style: TextStyle(fontSize: 12, color: ActColors.midGray),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight,
            child: Text(_e.display, style: TextStyle(fontSize: 40, fontWeight: FontWeight.w200,
              color: isDark ? Colors.white : Colors.black))),
          if (_e.fraction != null)
            Text('= ${_e.fraction}', style: TextStyle(fontSize: 12, color: ActColors.primary)),
          if (_e._mem != null)
            Text('M: ${_e._fmt(_e._mem!)}', style: TextStyle(fontSize: 10, color: ActColors.primary)),
        ]),
      ),
      Expanded(child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(children: [
          // Row 0: INV toggle + memory
          Row(children: [
            _Btn(_inv ? 'INV ✓' : 'INV', bg: inv, fg: _inv ? Colors.white : fg,
              onTap: () => setState(() => _inv = !_inv), fontSize: 12),
            _Btn('MC', bg:d1, fg:fg, onTap:()=>_t('MC'), fontSize:12),
            _Btn('MR', bg:d1, fg:fg, onTap:()=>_t('MR'), fontSize:12),
            _Btn('MS', bg:d1, fg:fg, onTap:()=>_t('MS'), fontSize:12),
            _Btn('M+', bg:d1, fg:fg, onTap:()=>_t('M+'), fontSize:12),
          ]),
          // Row 1: trig
          Row(children: [
            f(_inv?'sin⁻¹':'sin',  _inv?'sin⁻¹':'sin'),
            f(_inv?'cos⁻¹':'cos',  _inv?'cos⁻¹':'cos'),
            f(_inv?'tan⁻¹':'tan',  _inv?'tan⁻¹':'tan'),
            f(_inv?'eˣ':'ln',      _inv?'eˣ':'ln'),
            f(_inv?'10ˣ':'log',    _inv?'10ˣ':'log'),
          ]),
          // Row 2: powers & roots
          Row(children: [
            f('x²', 'x²'),
            f('√', '√'),
            f('xʸ', 'xʸ', bg: op), // this feeds into the op stack
            f('1/x', '1/x'),
            f('n!', 'n!'),
          ]),
          // Row 3: constants + percent + abs
          Row(children: [
            f('π', 'π'),
            f('e', 'e'),
            f('abs', 'abs'),
            b('%', bg: d1),
            b('+/-', bg: d1, fs: 14),
          ]),
          // Row 4: AC CE ⌫ ÷ ×
          Row(children: [
            b('AC', bg:d1), b('CE', bg:d1), b('⌫', bg:d1),
            _Btn('÷', bg:op, fg:Colors.black, onTap:()=>_t('÷')),
            _Btn('×', bg:op, fg:Colors.black, onTap:()=>_t('×')),
          ]),
          // Row 5: 7 8 9 −
          Row(children: [
            b('7'), b('8'), b('9'),
            _Btn('−', bg:op, fg:Colors.black, onTap:()=>_t('−')),
            _Btn('+', bg:op, fg:Colors.black, onTap:()=>_t('+')),
          ]),
          // Row 6: 4 5 6 + =
          Row(children: [
            b('4'), b('5'), b('6'),
            _Btn('0', bg:d2, fg:fg, onTap:()=>_t('0')),
            _Btn('.', bg:d2, fg:fg, onTap:()=>_t('.')),
          ]),
          // Row 7: 1 2 3 0 .
          Row(children: [
            b('1'), b('2'), b('3'),
            _Btn('=', bg:ActColors.primary, fg:Colors.white, onTap:()=>_t('='), flex:2),
          ]),
        ]),
      )),
    ]);
  }
}
