import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/src/rust/api/simple.dart';
import 'package:flutter_alacritty/src/rust/terminal.dart';
import 'package:flutter_alacritty/src/rust/frb_generated.dart';

Stream<int>? _terminalStream;

Future<void> main() async {
  await RustLib.init();
  _terminalStream = createTerminalStream().asBroadcastStream();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  double _fontSize = 14.0;
  ThemeMode _themeMode = ThemeMode.dark;

  void _updateFontSize(double newSize) {
    setState(() {
      _fontSize = newSize;
    });
  }

  void _updateThemeMode(ThemeMode newMode) {
    setState(() {
      _themeMode = newMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: _themeMode,
      home: TerminalTabs(
        fontSize: _fontSize,
        themeMode: _themeMode,
        onFontSizeChanged: _updateFontSize,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }
}

class TerminalTabs extends StatefulWidget {
  final double fontSize;
  final ThemeMode themeMode;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const TerminalTabs({
    super.key,
    required this.fontSize,
    required this.themeMode,
    required this.onFontSizeChanged,
    required this.onThemeModeChanged,
  });

  @override
  State<TerminalTabs> createState() => _TerminalTabsState();
}

class _TerminalTabsState extends State<TerminalTabs>
    with TickerProviderStateMixin {
  final List<int> _terminalIds = [];
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _addTab();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _addTab() {
    setState(() {
      final id = addTerminal(rows: 24, cols: 80);
      _terminalIds.add(id);

      _tabController?.dispose();
      _tabController = TabController(
        length: _terminalIds.length,
        vsync: this,
        initialIndex: _terminalIds.length - 1,
      );
    });
  }

  void _removeTab(int id) {
    setState(() {
      final indexToRemove = _terminalIds.indexOf(id);
      removeTerminal(id: id);
      _terminalIds.remove(id);

      if (_terminalIds.isEmpty) {
        _addTab();
      } else {
        int newIndex = _tabController!.index;
        if (indexToRemove <= newIndex) {
          newIndex = (newIndex - 1).clamp(0, _terminalIds.length - 1);
        }

        _tabController?.dispose();
        _tabController = TabController(
          length: _terminalIds.length,
          vsync: this,
          initialIndex: newIndex,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_terminalIds.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: PreferredSize(
          // Height set to 48dp, which complies with safety targets (≥ 44dp)
          preferredSize: const Size.fromHeight(48),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  // Ensures standard Tab items span minimum target sizes cleanly
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                  tabs: _terminalIds
                      .asMap()
                      .entries
                      .map(
                        (e) => Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 8),
                              Text("Tab ${e.key + 1}"),
                              // ── TOUCH TARGET ENHANCEMENT ───────────────────
                              // Replaced raw GestureDetector with an explicitly
                              // constrained IconButton ensuring exact 44x44 dp dimensions.
                              IconButton(
                                iconSize: 16,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                icon: const Icon(Icons.close),
                                onPressed: () => _removeTab(e.value),
                                tooltip: 'Close Tab',
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              // Standard material IconButtons default to 48x48 dp touch targets.
              // Added explicit constraints to completely guarantee compliance.
              IconButton(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.add),
                onPressed: _addTab,
                tooltip: 'Add Tab',
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.settings),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setDialogState) {
                        return AlertDialog(
                          title: const Text("Settings"),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text("Font Size"),
                              Slider(
                                value: widget.fontSize,
                                min: 8,
                                max: 30,
                                divisions: 22,
                                label: widget.fontSize.round().toString(),
                                onChanged: (val) {
                                  widget.onFontSizeChanged(val);
                                  setDialogState(() {});
                                },
                              ),
                              const SizedBox(height: 16),
                              ListTile(
                                title: const Text("Theme"),
                                trailing: DropdownButton<ThemeMode>(
                                  value: widget.themeMode,
                                  onChanged: (ThemeMode? newMode) {
                                    if (newMode != null) {
                                      widget.onThemeModeChanged(newMode);
                                      setDialogState(() {});
                                    }
                                  },
                                  items: const [
                                    DropdownMenuItem(
                                      value: ThemeMode.light,
                                      child: Text("Light"),
                                    ),
                                    DropdownMenuItem(
                                      value: ThemeMode.dark,
                                      child: Text("Dark"),
                                    ),
                                    DropdownMenuItem(
                                      value: ThemeMode.system,
                                      child: Text("System"),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(
                                  64,
                                  44,
                                ), // Ensure ≥ 44dp target
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Close"),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
                tooltip: 'Settings',
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: _terminalIds.asMap().entries.map((entry) {
          return TerminalView(
            terminalId: entry.value,
            fontSize: widget.fontSize,
            tabController: _tabController!,
            index: entry.key,
          );
        }).toList(),
      ),
    );
  }
}

class TerminalView extends StatefulWidget {
  final int terminalId;
  final double fontSize;
  final TabController tabController;
  final int index;
  const TerminalView({
    super.key,
    required this.terminalId,
    required this.fontSize,
    required this.tabController,
    required this.index,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView>
    with AutomaticKeepAliveClientMixin {
  TerminalFrame? _frame;
  StreamSubscription? _subscription;
  final FocusNode _focusNode = FocusNode();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_handleTabChange);

    if (widget.tabController.index == widget.index) {
      _activateTerminal();
    }

    _subscription = _terminalStream?.listen((id) {
      if (id == widget.terminalId && mounted) {
        final newFrame = getTerminalFrame(id: widget.terminalId);
        if (newFrame != null) {
          setState(() {
            _frame = newFrame;
          });
        }
      }
    });
    _frame = getTerminalFrame(id: widget.terminalId);
  }

  @override
  void didUpdateWidget(covariant TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController.removeListener(_handleTabChange);
      widget.tabController.addListener(_handleTabChange);

      if (widget.tabController.index == widget.TerminalVindex) {
        _activateTerminal();
      }
    }
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_handleTabChange);
    _subscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (widget.tabController.index == widget.index) {
      _activateTerminal();
    }
  }

  void _activateTerminal() {
    setActiveTerminal(id: widget.terminalId);

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  String? _keyEventToTerminalInput(KeyEvent event) {
    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    if (isCtrl && !isAlt) {
      if (key == LogicalKeyboardKey.keyC) return '\x03';
      if (key == LogicalKeyboardKey.keyD) return '\x04';
      if (key == LogicalKeyboardKey.keyZ) return '\x1a';
      if (key == LogicalKeyboardKey.keyL) return '\x0c';
      if (key == LogicalKeyboardKey.keyA) return '\x01';
      if (key == LogicalKeyboardKey.keyE) return '\x05';
      if (key == LogicalKeyboardKey.keyK) return '\x0b';
      if (key == LogicalKeyboardKey.keyU) return '\x15';
      if (key == LogicalKeyboardKey.keyW) return '\x17';
      if (key == LogicalKeyboardKey.keyR) return '\x12';
      if (key == LogicalKeyboardKey.keyS) return '\x13';
      if (key == LogicalKeyboardKey.keyQ) return '\x11';
      if (key == LogicalKeyboardKey.keyP) return '\x10';
      if (key == LogicalKeyboardKey.keyN) return '\x0e';
      if (key == LogicalKeyboardKey.keyB) return '\x02';
      if (key == LogicalKeyboardKey.keyF) return '\x06';
      if (key == LogicalKeyboardKey.keyT) return '\x14';
      if (key == LogicalKeyboardKey.keyY) return '\x19';
      if (key == LogicalKeyboardKey.backslash) return '\x1c';
      if (key == LogicalKeyboardKey.bracketRight) return '\x1d';
      if (key == LogicalKeyboardKey.space) return '\x00';

      if (key == LogicalKeyboardKey.arrowLeft) return '\x1b[1;5D';
      if (key == LogicalKeyboardKey.arrowRight) return '\x1b[1;5C';
      if (key == LogicalKeyboardKey.arrowUp) return '\x1b[1;5A';
      if (key == LogicalKeyboardKey.arrowDown) return '\x1b[1;5B';

      if (key == LogicalKeyboardKey.home) return '\x1b[1;5H';
      if (key == LogicalKeyboardKey.end) return '\x1b[1;5F';
      if (key == LogicalKeyboardKey.delete) return '\x1b[3;5~';
    }

    if (isAlt && !isCtrl) {
      if (key == LogicalKeyboardKey.keyB) return '\x1bb';
      if (key == LogicalKeyboardKey.keyF) return '\x1bf';
      if (key == LogicalKeyboardKey.keyD) return '\x1bd';
      if (key == LogicalKeyboardKey.backspace) return '\x1b\x7f';
      if (key == LogicalKeyboardKey.keyU) return '\x1bu';
      if (key == LogicalKeyboardKey.keyL) return '\x1bl';
      if (key == LogicalKeyboardKey.keyC) return '\x1bc';
      if (key == LogicalKeyboardKey.keyR) return '\x1br';
      if (key == LogicalKeyboardKey.period) return '\x1b.';

      if (key == LogicalKeyboardKey.digit0) return '\x1b0';
      for (int i = 1; i <= 9; i++) {
        if (key.keyId == LogicalKeyboardKey.digit1.keyId + i - 1) {
          return '\x1b$i';
        }
      }
      if (key == LogicalKeyboardKey.arrowLeft) return '\x1b[1;3D';
      if (key == LogicalKeyboardKey.arrowRight) return '\x1b[1;3C';
    }

    if (isShift) {
      if (key == LogicalKeyboardKey.arrowUp) return '\x1b[1;2A';
      if (key == LogicalKeyboardKey.arrowDown) return '\x1b[1;2B';
      if (key == LogicalKeyboardKey.pageUp) return '\x1b[5;2~';
      if (key == LogicalKeyboardKey.pageDown) return '\x1b[6;2~';
      if (key == LogicalKeyboardKey.tab) return '\x1b[Z';
    }

    if (key == LogicalKeyboardKey.enter) return '\r';
    if (key == LogicalKeyboardKey.backspace) return '\x7f';
    if (key == LogicalKeyboardKey.tab) return '\t';
    if (key == LogicalKeyboardKey.escape) return '\x1b';
    if (key == LogicalKeyboardKey.delete) return '\x1b[3~';
    if (key == LogicalKeyboardKey.home) return '\x1b[H';
    if (key == LogicalKeyboardKey.end) return '\x1b[F';
    if (key == LogicalKeyboardKey.pageUp) return '\x1b[5~';
    if (key == LogicalKeyboardKey.pageDown) return '\x1b[6~';
    if (key == LogicalKeyboardKey.insert) return '\x1b[2~';
    if (key == LogicalKeyboardKey.arrowUp) return '\x1b[A';
    if (key == LogicalKeyboardKey.arrowDown) return '\x1b[B';
    if (key == LogicalKeyboardKey.arrowRight) return '\x1b[C';
    if (key == LogicalKeyboardKey.arrowLeft) return '\x1b[D';

    if (key == LogicalKeyboardKey.f1) return '\x1bOP';
    if (key == LogicalKeyboardKey.f2) return '\x1bOQ';
    if (key == LogicalKeyboardKey.f3) return '\x1bOR';
    if (key == LogicalKeyboardKey.f4) return '\x1bOS';
    if (key == LogicalKeyboardKey.f5) return '\x1b[15~';
    if (key == LogicalKeyboardKey.f6) return '\x1b[17~';
    if (key == LogicalKeyboardKey.f7) return '\x1b[18~';
    if (key == LogicalKeyboardKey.f8) return '\x1b[19~';
    if (key == LogicalKeyboardKey.f9) return '\x1b[20~';
    if (key == LogicalKeyboardKey.f10) return '\x1b[21~';
    if (key == LogicalKeyboardKey.f11) return '\x1b[23~';
    if (key == LogicalKeyboardKey.f12) return '\x1b[24~';

    final character = event is KeyDownEvent || event is KeyRepeatEvent
        ? event.character
        : null;
    if (character != null && character.isNotEmpty) return character;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            final key = event.logicalKey;
            final isAlt = HardwareKeyboard.instance.isAltPressed;
            final isCtrl = HardwareKeyboard.instance.isControlPressed;
            final isShift = HardwareKeyboard.instance.isShiftPressed;

            if (isAlt && !isCtrl && !isShift) {
              final int? targetIndex = switch (key) {
                LogicalKeyboardKey.digit1 => 0,
                LogicalKeyboardKey.digit2 => 1,
                LogicalKeyboardKey.digit3 => 2,
                LogicalKeyboardKey.digit4 => 3,
                LogicalKeyboardKey.digit5 => 4,
                LogicalKeyboardKey.digit6 => 5,
                LogicalKeyboardKey.digit7 => 6,
                LogicalKeyboardKey.digit8 => 7,
                LogicalKeyboardKey.digit9 => 8,
                LogicalKeyboardKey.digit0 => 9,
                _ => null,
              };

              if (targetIndex != null &&
                  targetIndex < widget.tabController.length) {
                widget.tabController.animateTo(targetIndex);
                return;
              }
            }

            final input = _keyEventToTerminalInput(event);
            if (input != null) {
              sendInput(id: widget.terminalId, input: input);
            }
          }
        },
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: CustomPaint(
            painter: _frame != null
                ? TerminalPainter(
                    _frame!,
                    widget.fontSize,
                    Theme.of(context).textTheme.bodyMedium?.color ??
                        Colors.white,
                    widget.terminalId,
                  )
                : null,
            child: Container(),
          ),
        ),
      ),
    );
  }
}

class TerminalPainter extends CustomPainter {
  final TerminalFrame frame;
  final double fontSize;
  final Color textColor;
  final int terminalId;

  static final Map<String, ui.Paragraph> _rowCache = {};

  TerminalPainter(this.frame, this.fontSize, this.textColor, this.terminalId);

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = ui.TextStyle(
      color: textColor,
      fontFamily: 'monospace',
      fontSize: fontSize,
    );

    final paragraphStyle = ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontFamily: 'monospace',
    );
    final pb = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText('X');
    final charMeasure = pb.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final double charWidth = charMeasure.maxIntrinsicWidth;
    final double charHeight = charMeasure.height;

    for (int y = 0; y < frame.rows; y++) {
      final startIndex = y * frame.cols;
      final endIndex = (y + 1) * frame.cols;
      if (startIndex >= frame.content.length) break;

      final actualEnd = endIndex > frame.content.length
          ? frame.content.length
          : endIndex;
      final rowContent = frame.content.substring(startIndex, actualEnd);

      final cacheKey = "${terminalId}_${y}_${rowContent}_${fontSize}";

      ui.Paragraph? paragraph = _rowCache[cacheKey];
      if (paragraph == null) {
        final rowBuilder = ui.ParagraphBuilder(paragraphStyle);
        rowBuilder.pushStyle(textStyle);
        rowBuilder.addText(rowContent);
        paragraph = rowBuilder.build();
        paragraph.layout(
          ui.ParagraphConstraints(width: charWidth * frame.cols),
        );
        _rowCache[cacheKey] = paragraph;
      }

      canvas.drawParagraph(paragraph, Offset(0, y * charHeight));
    }

    final cursorPaint = Paint()..color = textColor.withOpacity(0.5);
    canvas.drawRect(
      Rect.fromLTWH(
        frame.cursorX * charWidth,
        frame.cursorY * charHeight,
        charWidth,
        charHeight,
      ),
      cursorPaint,
    );

    if (_rowCache.length > 1000) {
      _rowCache.clear();
    }
  }

  @override
  bool shouldRepaint(covariant TerminalPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.textColor != textColor;
  }
}
