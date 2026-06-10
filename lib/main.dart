import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mechanix_terminal/core/utils/app_logger.dart';
import 'package:mechanix_terminal/core/utils/app_theme.dart';
import 'package:mechanix_terminal/core/utils/constants.dart';
import 'package:mechanix_terminal/features/data/settings.dart';
import 'package:mechanix_terminal/features/data/settings_repository.dart';
import 'package:mechanix_terminal/features/screen/settings_screen.dart';
import 'package:mechanix_terminal/src/rust/api/simple.dart';
import 'package:mechanix_terminal/src/rust/frb_generated.dart';
import 'package:mechanix_terminal/src/rust/terminal.dart';
import 'package:show_fps/show_fps.dart';

Stream<int>? _terminalStream;
late SettingsRepository settingsRepository;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  AppSettings _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    try {
      settingsRepository = await SettingsRepository.create();

      if (!mounted) return;

      setState(() {
        _settings = settingsRepository.getSettings();
      });
    } catch (e) {
      AppLogger.i('Failed to initialize settings: $e');
    }
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    settingsRepository.saveSettings(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final showFps = Platform.environment['SHOW_FPS'] == 'true';

    ThemeMode themeMode = ThemeMode.dark;
    if (_settings.colorBackground?.toUpperCase() == '#EFF1F5') {
      themeMode = ThemeMode.light;
    }

    return MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: TerminalTabs(
        settings: _settings,
        onSettingsChanged: _updateSettings,
      ),
      builder: showFps
          ? (context, child) {
              return ShowFPS(visible: showFps, showChart: false, child: child!);
            }
          : null,
    );
  }
}

class TerminalTabs extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const TerminalTabs({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => TerminalSettingsPage(
                        settings: widget.settings,
                        onSettingsChanged: widget.onSettingsChanged,
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
            settings: widget.settings,
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
  final AppSettings settings;
  final TabController tabController;
  final int index;
  const TerminalView({
    super.key,
    required this.terminalId,
    required this.settings,
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

  // Estimate height per line dynamically based on font size
  double get _lineHeight => widget.settings.fontSize * 1.3;

  // ── TEXT SELECTION STATE ───────────────────────────────────────────────────
  // Cell coordinates (col, row) for selection anchor and active end.
  ({int col, int row})? _selectionStart;
  ({int col, int row})? _selectionEnd;
  bool _isSelecting = false;

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

      if (widget.tabController.index == widget.index) {
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

  /// Converts a Flutter KeyEvent into terminal strings or history sequences.
  String? _keyEventToTerminalInput(KeyEvent event) {
    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // ── Ctrl shortcuts ────────────────────────────────────────────────────────
    if (isCtrl && !isAlt) {
      final value = ctrlMappings[key];
      if (value != null) return value;
    }

    // ── Alt (Meta) shortcuts ──────────────────────────────────────────────────
    if (isAlt && !isCtrl) {
      if (key == LogicalKeyboardKey.digit0) {
        return '\x1b0';
      }

      final digit1 = LogicalKeyboardKey.digit1.keyId;
      final digit9 = LogicalKeyboardKey.digit9.keyId;

      if (key.keyId >= digit1 && key.keyId <= digit9) {
        return '\x1b${key.keyId - digit1 + 1}';
      }

      final value = altMappings[key];
      if (value != null) return value;
    }

    // ── Shift shortcuts ───────────────────────────────────────────────────────
    if (isShift) {
      final shiftValue = shiftMappings[key];
      if (shiftValue != null) {
        return shiftValue;
      }
    }

    final defaultValue = defaultMappings[key];
    if (defaultValue != null) {
      return defaultValue;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final character = event.character;
      if (character != null && character.isNotEmpty) {
        return character;
      }
    }

    return null;
  } // ── SELECTION HELPERS ──────────────────────────────────────────────────────

  /// Convert a pixel offset to a terminal cell coordinate.
  ({int col, int row}) _pixelToCell(
    Offset position,
    double charWidth,
    double charHeight,
  ) {
    final frame = _frame;
    int col = (position.dx / charWidth).floor();
    int row = (position.dy / charHeight).floor();
    if (frame != null) {
      col = col.clamp(0, frame.cols - 1);
      row = row.clamp(0, frame.rows - 1);
    } else {
      col = col.clamp(0, 9999);
      row = row.clamp(0, 9999);
    }
    return (col: col, row: row);
  }

  /// Extract the plain-text content of the current selection from [frame].
  String _extractSelection(TerminalFrame frame) {
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null || end == null) return '';

    // Normalise so startCell always comes before endCell in reading order.
    final ({int col, int row}) a;
    final ({int col, int row}) b;
    if (start.row < end.row || (start.row == end.row && start.col <= end.col)) {
      a = start;
      b = end;
    } else {
      a = end;
      b = start;
    }

    final buffer = StringBuffer();
    for (int y = a.row; y <= b.row; y++) {
      final startCol = (y == a.row) ? a.col : 0;
      final endCol = (y == b.row) ? b.col : frame.cols - 1;
      final rowStart = y * frame.cols;

      bool isWrapped = false;
      if (y < b.row) {
        final lastColIdx = rowStart + (frame.cols - 1);
        if (lastColIdx < frame.attributes.length) {
          isWrapped = (frame.attributes[lastColIdx] & 2) != 0;
        }
      }

      for (int x = startCol; x <= endCol; x++) {
        final idx = rowStart + x;
        if (idx < frame.content.length) {
          buffer.write(frame.content[idx]);
        }
      }

      if (y < b.row && !isWrapped) {
        buffer.write('\n');
      }
    }

    // Trim trailing spaces on each line, like a real terminal.
    return buffer.toString().split('\n').map((l) => l.trimRight()).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final fontSize = widget.settings.fontSize;
    final fontFamily = widget.settings.fontFamily ?? 'monospace';

    // Compute char metrics once here so pointer handlers and painter agree.
    final measureStyle = ui.TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
    );
    final measureParaStyle = ui.ParagraphStyle(
      fontSize: fontSize,
      fontFamily: 'monospace',
    );
    final measurePb = ui.ParagraphBuilder(measureParaStyle)
      ..pushStyle(measureStyle)
      ..addText('X');
    final charMeasure = measurePb.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
    final double charWidth = charMeasure.maxIntrinsicWidth;
    final double charHeight = charMeasure.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / charWidth).floor().clamp(10, 500);
        final rows = (constraints.maxHeight / charHeight).floor().clamp(5, 200);

        final currentFrame = _frame;
        if (currentFrame == null ||
            currentFrame.rows != rows ||
            currentFrame.cols != cols) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              resizeTerminal(id: widget.terminalId, rows: rows, cols: cols);
            }
          });
        }

        return Listener(
          // ── Mouse-wheel scrolling ──────────────────────────────────────────────
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final int lines = (pointerSignal.scrollDelta.dy / _lineHeight)
                  .round();
              if (lines != 0) {
                scrollTerminal(id: widget.terminalId, lines: lines);
              }
            }
          },
          // ── Left-button down: start selection ─────────────────────────────────
          onPointerDown: (event) {
            if (event.buttons == kPrimaryMouseButton) {
              _focusNode.requestFocus();
              final cell = _pixelToCell(
                event.localPosition,
                charWidth,
                charHeight,
              );
              setState(() {
                _isSelecting = true;
                _selectionStart = cell;
                _selectionEnd = cell;
              });
            }
          },
          // ── Left-button drag: extend selection ────────────────────────────────
          onPointerMove: (event) {
            if (_isSelecting && event.buttons == kPrimaryMouseButton) {
              final cell = _pixelToCell(
                event.localPosition,
                charWidth,
                charHeight,
              );
              setState(() {
                _selectionEnd = cell;
              });
            }
          },
          // ── Left-button up: finish & copy ─────────────────────────────────────
          onPointerUp: (event) {
            if (_isSelecting) {
              setState(() {
                _isSelecting = false;
              });
              final frame = _frame;
              if (frame != null) {
                final text = _extractSelection(frame);
                if (text.trim().isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: text));
                }
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
                final isMeta = HardwareKeyboard.instance.isMetaPressed;

                final isKeyC =
                    key == LogicalKeyboardKey.keyC ||
                    event.physicalKey == PhysicalKeyboardKey.keyC ||
                    key.keyLabel.toLowerCase() == 'c';
                final isKeyV =
                    key == LogicalKeyboardKey.keyV ||
                    event.physicalKey == PhysicalKeyboardKey.keyV ||
                    key.keyLabel.toLowerCase() == 'v';

                final isCopy =
                    (isCtrl && isShift && isKeyC) || (isMeta && isKeyC);
                final isPaste =
                    (isCtrl && isShift && isKeyV) || (isMeta && isKeyV);

                final isModifier =
                    key == LogicalKeyboardKey.controlLeft ||
                    key == LogicalKeyboardKey.controlRight ||
                    key == LogicalKeyboardKey.shiftLeft ||
                    key == LogicalKeyboardKey.shiftRight ||
                    key == LogicalKeyboardKey.altLeft ||
                    key == LogicalKeyboardKey.altRight ||
                    key == LogicalKeyboardKey.metaLeft ||
                    key == LogicalKeyboardKey.metaRight;

                // Clear selection on any key except modifiers and Copy/Paste shortcuts
                if (!isCopy && !isPaste && !isModifier) {
                  if (_selectionStart != null) {
                    setState(() {
                      _selectionStart = null;
                      _selectionEnd = null;
                    });
                  }
                }

                // Copy selection to clipboard
                if (isCopy) {
                  final frame = _frame;
                  if (frame != null) {
                    final text = _extractSelection(frame);
                    if (text.trim().isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: text));
                    }
                  }
                  return;
                }

                // Paste clipboard into terminal
                if (isPaste) {
                  Clipboard.getData(Clipboard.kTextPlain).then((data) {
                    final text = data?.text;
                    if (text != null && text.isNotEmpty) {
                      pasteTerminal(id: widget.terminalId, input: text);
                    }
                  });
                  return;
                }

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
              color:
                  _parseHexColor(widget.settings.colorBackground) ??
                  Theme.of(context).scaffoldBackgroundColor,
              child: CustomPaint(
                painter: _frame != null
                    ? TerminalPainter(
                        _frame!,
                        fontSize,
                        _parseHexColor(widget.settings.colorForeground) ??
                            Theme.of(context).textTheme.bodyMedium?.color ??
                            Colors.white,
                        _parseHexColor(widget.settings.colorBackground) ??
                            Theme.of(context).scaffoldBackgroundColor,
                        _parseHexColor(widget.settings.colorCursor) ??
                            Colors.white70,
                        fontFamily,
                        widget.terminalId,
                        selectionStart: _selectionStart,
                        selectionEnd: _selectionEnd,
                      )
                    : null,
                child: Container(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class TerminalPainter extends CustomPainter {
  final TerminalFrame frame;
  final double fontSize;
  final Color textColor;
  final Color backgroundColor;
  final Color cursorColor;
  final String fontFamily;
  final int terminalId;
  final ({int col, int row})? selectionStart;
  final ({int col, int row})? selectionEnd;

  static final Map<String, ui.Paragraph> _rowCache = {};

  TerminalPainter(
    this.frame,
    this.fontSize,
    this.textColor,
    this.backgroundColor,
    this.cursorColor,
    this.fontFamily,
    this.terminalId, {
    this.selectionStart,
    this.selectionEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = ui.TextStyle(
      color: textColor,
      fontFamily: fontFamily,
      fontSize: fontSize,
    );

    final paragraphStyle = ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontSize: fontSize,
      fontFamily: fontFamily,
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

      final cacheKey =
          "${terminalId}_${y}_${rowContent}_${fontSize}_${textColor.toARGB32()}_$fontFamily";

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

    // ── Draw selection highlight ───────────────────────────────────────────
    final ss = selectionStart;
    final se = selectionEnd;
    if (ss != null && se != null) {
      // Normalise order.
      final ({int col, int row}) a;
      final ({int col, int row}) b;
      if (ss.row < se.row || (ss.row == se.row && ss.col <= se.col)) {
        a = ss;
        b = se;
      } else {
        a = se;
        b = ss;
      }

      final selPaint = Paint()
        ..color = const Color(0x557CB9F5); // semi-transparent blue

      for (int y = a.row; y <= b.row; y++) {
        final startCol = (y == a.row) ? a.col : 0;
        final endCol = (y == b.row) ? b.col : frame.cols - 1;
        canvas.drawRect(
          Rect.fromLTWH(
            startCol * charWidth,
            y * charHeight,
            (endCol - startCol + 1) * charWidth,
            charHeight,
          ),
          selPaint,
        );
      }
    }

    // ── Draw cursor ───────────────────────────────────────────────────────────
    final cursorPaint = Paint()..color = cursorColor;
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
        oldDelegate.textColor != textColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.cursorColor != cursorColor ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.selectionStart != selectionStart ||
        oldDelegate.selectionEnd != selectionEnd;
  }
}

Color? _parseHexColor(String? hexString) {
  if (hexString == null) return null;
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  final parsed = int.tryParse(buffer.toString(), radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}
