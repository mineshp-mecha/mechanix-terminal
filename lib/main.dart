import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/constants.dart';
import 'package:flutter_alacritty/settings_page.dart';
import 'package:flutter_alacritty/src/rust/api/simple.dart';
import 'package:flutter_alacritty/src/rust/frb_generated.dart';
import 'package:flutter_alacritty/src/rust/terminal.dart';

TermPreferences getPreferencesFor(ThemeMode mode, double fontSize) {
  final isDark =
      mode == ThemeMode.dark ||
      (mode == ThemeMode.system &&
          ui.PlatformDispatcher.instance.platformBrightness ==
              ui.Brightness.dark);

  if (isDark) {
    return TermPreferences(
      fontFamily: 'monospace',
      fontSize: fontSize,
      lineHeight: 1.2,
      colorForeground: 0xCDD6F4,
      colorBackground: 0x1E1E2E,
      colorCursor: 0xF5C2E7,
      colorSelection: 0x45475A,
      palette: defaultDarkThemePalette,
    );
  } else {
    return TermPreferences(
      fontFamily: 'monospace',
      fontSize: fontSize,
      lineHeight: 1.2,
      colorForeground: 0x4C4F69,
      colorBackground: 0xEFF1F5,
      colorCursor: 0xEA76CB,
      colorSelection: 0xACB0BE,
      palette: defaultLightThemePalette,
    );
  }
}

Stream<int>? _terminalStream;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final initialPrefs = loadConfigPrefs();
  _terminalStream = createTerminalStream().asBroadcastStream();
  runApp(MyApp(initialPrefs: initialPrefs));
}

class MyApp extends StatefulWidget {
  final TermPreferences initialPrefs;
  const MyApp({super.key, required this.initialPrefs});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late TermPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
  }

  void _updatePrefs(TermPreferences p) {
    setState(() => _prefs = p);
    saveConfigPrefs(prefs: p);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _prefs.colorBackground < 0x808080;
    return MaterialApp(
      theme: ThemeData.light(),
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: TerminalTabs(prefs: _prefs, onPrefsChanged: _updatePrefs),
    );
  }
}

class TerminalTabs extends StatefulWidget {
  final TermPreferences prefs;
  final ValueChanged<TermPreferences> onPrefsChanged;

  const TerminalTabs({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
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
      final id = addTerminalWithPrefs(rows: 24, cols: 80, prefs: widget.prefs);
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => TerminalSettingsPage(
                        initialPrefs: widget.prefs,
                        onPrefsChanged: widget.onPrefsChanged,
                      ),
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
            fontSize: widget.prefs.fontSize,
            prefs: widget.prefs,
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
  final TermPreferences prefs;
  final TabController tabController;
  final int index;
  const TerminalView({
    super.key,
    required this.terminalId,
    required this.fontSize,
    required this.prefs,
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

  // ── SCROLL STATE TRACKING ──────────────────────────────────────────────────
  double _dragDistance = 0.0;
  // Estimate height per line dynamically based on font size
  double get _lineHeight => widget.fontSize * 1.3;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_handleTabChange);

    if (widget.tabController.index == widget.index) {
      _activateTerminal();
    }

    // Load active settings/preferences on terminal startup
    updateTerminalPrefs(id: widget.terminalId, prefs: widget.prefs);

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

      if (widget.tabController.index == widget.index) {
        _activateTerminal();
      }
    }
    if (oldWidget.prefs != widget.prefs) {
      updateTerminalPrefs(id: widget.terminalId, prefs: widget.prefs);
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

  /// Converts a Flutter KeyEvent into terminal strings or history sequences.
  String? _keyEventToTerminalInput(KeyEvent event) {
    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // ── Ctrl shortcuts ────────────────────────────────────────────────────────
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

    // ── Alt (Meta) shortcuts ──────────────────────────────────────────────────
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

    // ── Shift shortcuts ───────────────────────────────────────────────────────
    if (isShift) {
      if (key == LogicalKeyboardKey.arrowUp) return '\x1b[1;2A';
      if (key == LogicalKeyboardKey.arrowDown) return '\x1b[1;2B';
      if (key == LogicalKeyboardKey.pageUp) return '\x1b[5;2~';
      if (key == LogicalKeyboardKey.pageDown) return '\x1b[6;2~';
      if (key == LogicalKeyboardKey.tab) return '\x1b[Z';
    }

    // ── Special / Navigation & Command History keys ───────────────────────────
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

    // FIX: Standard Shell Command History Navigation mappings.
    // If your shell uses Application Mode, use '\x1bOA' and '\x1bOB'.
    if (key == LogicalKeyboardKey.arrowUp) return '\x1b[A';
    if (key == LogicalKeyboardKey.arrowDown) return '\x1b[B';
    if (key == LogicalKeyboardKey.arrowRight) return '\x1b[C';
    if (key == LogicalKeyboardKey.arrowLeft) return '\x1b[D';

    // ── Function keys ─────────────────────────────────────────────────────────
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

      // ── FEATURE 1a: Mobile touch gesture scrolling ──────────────────────────
      onVerticalDragUpdate: (details) {
        _dragDistance += details.primaryDelta ?? 0.0;
        final int lines = (_dragDistance / _lineHeight).round();
        if (lines != 0) {
          // Swiping down moves the viewport UP (negative value)
          // Assumes scrollTerminal(id, lines) is exposed by your Rust FFI wrapper
          scrollTerminal(id: widget.terminalId, lines: -lines);
          _dragDistance -= lines * _lineHeight;
        }
      },
      onVerticalDragEnd: (_) => _dragDistance = 0.0,

      child: Listener(
        // ── FEATURE 1b: Desktop mouse wheel scrolling ────────────────────────
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            final int lines = (pointerSignal.scrollDelta.dy / _lineHeight)
                .round();
            if (lines != 0) {
              scrollTerminal(id: widget.terminalId, lines: lines);
            }
          }
        },
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
            color: Color(0xFF000000 | widget.prefs.colorBackground),
            child: CustomPaint(
              painter: _frame != null
                  ? TerminalPainter(_frame!, widget.prefs, widget.terminalId)
                  : null,
              child: Container(),
            ),
          ),
        ),
      ),
    );
  }
}

class TerminalPainter extends CustomPainter {
  final TerminalFrame frame;
  final TermPreferences prefs;
  final int terminalId;

  static final Map<String, ui.Paragraph> _rowCache = {};

  TerminalPainter(this.frame, this.prefs, this.terminalId);

  int _hashList(Uint32List list, int start, int end) {
    int hash = 17;
    for (int i = start; i < end; i++) {
      hash = hash * 31 + list[i];
    }
    return hash;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double fontSize = prefs.fontSize;
    final String fontFamily = prefs.fontFamily;
    final double lineHeight = prefs.lineHeight;

    final baselineTextStyle = ui.TextStyle(
      color: Color(0xFF000000 | prefs.colorForeground),
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: lineHeight,
    );

    final paragraphStyle = ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontFamily: fontFamily,
      height: lineHeight,
    );

    final pb = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(baselineTextStyle)
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

      final attrHash = _hashList(frame.attributes, startIndex, actualEnd);
      final cacheKey =
          "${terminalId}_${y}_${rowContent}_${attrHash}_${fontSize}_$fontFamily";

      ui.Paragraph? paragraph = _rowCache[cacheKey];
      if (paragraph == null) {
        final rowBuilder = ui.ParagraphBuilder(paragraphStyle);

        int currentSpanStart = 0;
        int? lastAttr;

        void commitSpan(int end) {
          if (end <= currentSpanStart) return;
          final spanText = rowContent.substring(currentSpanStart, end);
          final attr = lastAttr ?? 0;
          final flags = attr & 0xFF;
          final fgColorVal = (attr >> 8) & 0xFFFFFF;

          final isBold = (flags & 1) != 0;
          final isItalic = (flags & 2) != 0;
          final isUnderline = (flags & 4) != 0;

          final fgColor = Color(
            0xFF000000 | (fgColorVal != 0 ? fgColorVal : prefs.colorForeground),
          );

          rowBuilder.pushStyle(
            ui.TextStyle(
              color: fgColor,
              fontFamily: fontFamily,
              fontSize: fontSize,
              height: lineHeight,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              decoration: isUnderline
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          );
          rowBuilder.addText(spanText);
          rowBuilder.pop();
        }

        for (int col = 0; col < (actualEnd - startIndex); col++) {
          final attr = frame.attributes[startIndex + col];
          if (lastAttr != attr) {
            commitSpan(col);
            currentSpanStart = col;
            lastAttr = attr;
          }
        }
        commitSpan(actualEnd - startIndex);

        paragraph = rowBuilder.build();
        paragraph.layout(
          ui.ParagraphConstraints(width: charWidth * frame.cols),
        );
        _rowCache[cacheKey] = paragraph;
      }

      canvas.drawParagraph(paragraph, Offset(0, y * charHeight));
    }

    if (frame.cursorY != 65535) {
      final cursorPaint = Paint()
        ..color = Color(0xFF000000 | prefs.colorCursor).withValues(alpha: 0.65);
      final double cursorLeft = frame.cursorX * charWidth;
      final double cursorTop = frame.cursorY * charHeight;
      // Block cursor
      canvas.drawRect(
        Rect.fromLTWH(cursorLeft, cursorTop, charWidth, charHeight),
        cursorPaint,
      );
    }

    if (_rowCache.length > 1000) {
      _rowCache.clear();
    }
  }

  @override
  bool shouldRepaint(covariant TerminalPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.prefs != prefs ||
        oldDelegate.terminalId != terminalId;
  }
}
