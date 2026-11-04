import 'package:flutter/material.dart';

/// Texto en una línea: si no entra, se va corriendo de a poco para que se
/// lea entero ("Impresiones 3D para el taller…").
class MarqueeText extends StatefulWidget {
  const MarqueeText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final _scroll = ScrollController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
    }
  }

  Future<void> _loop() async {
    if (_running) return;
    _running = true;
    while (mounted && _scroll.hasClients) {
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted || !_scroll.hasClients) break;
      await _scroll.animateTo(
        max,
        duration: Duration(milliseconds: (max * 25).round() + 400),
        curve: Curves.linear,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !_scroll.hasClients) break;
      _scroll.jumpTo(0);
    }
    _running = false;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: _scroll,
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
  );
}
