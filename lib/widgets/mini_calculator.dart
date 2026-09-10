import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// A small floating calculator overlay, self-contained (manages its own
/// input state internally) so it can be dropped into any screen — used by
/// Online Challenge and WiFi Challenge match screens for Math/Science
/// questions, same look-and-feel as the one in regular practice sessions.
class MiniCalculatorOverlay extends StatefulWidget {
  final VoidCallback onClose;
  const MiniCalculatorOverlay({super.key, required this.onClose});

  @override
  State<MiniCalculatorOverlay> createState() => _MiniCalculatorOverlayState();
}

class _MiniCalculatorOverlayState extends State<MiniCalculatorOverlay> {
  String _display = '0';
  String _op = '';
  double _val = 0;
  bool _newNum = true;

  void _input(String v) {
    setState(() {
      if (v == 'C') {
        _display = '0'; _op = ''; _val = 0; _newNum = true; return;
      }
      if (v == '⌫') {
        _display = _display.length > 1 ? _display.substring(0, _display.length - 1) : '0';
        return;
      }
      if (v == '=') {
        final cur = double.tryParse(_display) ?? 0;
        double r = cur;
        if (_op == '+') r = _val + cur;
        else if (_op == '−') r = _val - cur;
        else if (_op == '×') r = _val * cur;
        else if (_op == '÷') r = cur == 0 ? 0 : _val / cur;
        _display = r == r.truncateToDouble() ? r.toInt().toString() : r.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '');
        _op = ''; _newNum = true;
        return;
      }
      if (v == '+' || v == '−' || v == '×' || v == '÷') {
        _val = double.tryParse(_display) ?? 0;
        _op = v; _newNum = true;
        return;
      }
      if (v == '.') {
        if (_newNum) { _display = '0.'; _newNum = false; }
        else if (!_display.contains('.')) _display += '.';
        return;
      }
      if (_newNum) { _display = v; _newNum = false; }
      else { _display = _display == '0' ? v : (_display.length < 14 ? _display + v : _display); }
    });
  }

  Widget _btn(String label, {Color bg = const Color(0xFF2A2A2E), Color fg = Colors.white}) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _input(label),
        child: Container(
          margin: const EdgeInsets.all(2),
          height: 40,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Center(
            child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Expanded(child: Text('Calculator', style: TextStyle(color: Colors.white54, fontSize: 11))),
            GestureDetector(onTap: widget.onClose, child: const Icon(Icons.close, color: Colors.white38, size: 18)),
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
            child: Text(_display,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w300),
                textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _btn('C', bg: const Color(0xFF636366)),
            _btn('⌫', bg: const Color(0xFF636366)),
            _btn('%', bg: const Color(0xFF636366)),
            _btn('÷', bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('7'), _btn('8'), _btn('9'),
            _btn('×', bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('4'), _btn('5'), _btn('6'),
            _btn('−', bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('1'), _btn('2'), _btn('3'),
            _btn('+', bg: const Color(0xFFFF9F0A), fg: Colors.black),
          ]),
          Row(children: [
            _btn('0'), _btn('.'), _btn('⌫', bg: const Color(0xFF3A3A3C)),
            _btn('=', bg: ActColors.primary),
          ]),
        ],
      ),
    );
  }
}
