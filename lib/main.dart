import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/src/rust/api/simple.dart';
import 'package:flutter_alacritty/src/rust/terminal.dart';
import 'package:flutter_alacritty/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const TerminalTabs(),
    );
  }
}

class TerminalTabs extends StatefulWidget {
  const TerminalTabs({super.key});

  @override
  State<TerminalTabs> createState() => _TerminalTabsState();
}

class _TerminalTabsState extends State<TerminalTabs> {
  final List<int> _terminalIds = [];

  @override
  void initState() {
    super.initState();
    _addTab();
  }

  void _addTab() {
    setState(() {
      final id = addTerminal(rows: 24, cols: 80);
      _terminalIds.add(id);
    });
  }

  void _removeTab(int id) {
    setState(() {
      removeTerminal(id: id);
      _terminalIds.remove(id);
      if (_terminalIds.isEmpty) {
        _addTab();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_terminalIds.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: _terminalIds.length,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    isScrollable: true,
                    tabs: _terminalIds
                        .asMap()
                        .entries
                        .map((e) => Tab(
                              child: Row(
                                children: [
                                  Text('Tab ${e.key + 1}'),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _removeTab(e.value),
                                    child: const Icon(Icons.close, size: 16),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addTab,
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: _terminalIds.map((id) => TerminalView(terminalId: id)).toList(),
        ),
      ),
    );
  }
}

class TerminalView extends StatefulWidget {
  final int terminalId;
  const TerminalView({super.key, required this.terminalId});

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  TerminalFrame? _frame;
  StreamSubscription<TerminalFrame>? _subscription;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _subscription = createTerminalStream(id: widget.terminalId).listen((frame) {
      if (mounted) {
        if (frame.terminalId != widget.terminalId) return;
        setState(() {
          _frame = frame;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: RawKeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            String? input;
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              input = '\r';
            } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
              input = '\x7f';
            } else if (event.logicalKey == LogicalKeyboardKey.tab) {
              input = '\t';
            } else if (event.character != null) {
              input = event.character;
            }

            if (input != null) {
              sendInput(id: widget.terminalId, input: input);
            }
          }
        },
        child: Container(
          color: Colors.black,
          child: CustomPaint(
            child: Container(),
          ),
        ),
      ),
    );
  }
}

class TerminalPainter extends CustomPainter {
  final TerminalFrame frame;
  static final Map<String, ui.Paragraph> _paragraphCache = {};

  TerminalPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    const double charWidth = 8.4;
    const double charHeight = 16.0;

    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontFamily: 'monospace',
      fontSize: 14,
    );

    for (int y = 0; y < frame.rows; y++) {
      final rowText = frame.cells.substring(y * frame.cols, (y + 1) * frame.cols);
      if (rowText.trim().isEmpty) continue;
      
      final cacheKey = rowText;
      ui.Paragraph? paragraph;
      if (_paragraphCache.containsKey(cacheKey)) {
      } else {
        final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
          ..pushStyle(textStyle)
          ..addText(rowText);
        paragraph = builder.build()..layout(ui.ParagraphConstraints(width: size.width));
        _paragraphCache[cacheKey] = paragraph;
      }

      canvas.drawParagraph(paragraph!, Offset(0, y * charHeight));
    }

    final cursorPaint = Paint()..color = Colors.white54;
    canvas.drawRect(
      Rect.fromLTWH(
        frame.cursorX * charWidth,
        frame.cursorY * charHeight,
        charWidth,
        charHeight,
      ),
      cursorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant TerminalPainter oldDelegate) {
    return oldDelegate.frame.cells != frame.cells || 
           oldDelegate.frame.cursorX != frame.cursorX || 
           oldDelegate.frame.cursorY != frame.cursorY;
  }
}
