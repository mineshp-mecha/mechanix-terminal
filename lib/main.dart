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
          toolbarHeight: 0, // Hide the toolbar part
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
                        .map(
                          (e) => Tab(
                            child: Row(
                              children: [
                                Text("Tab ${e.key + 1}"),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _removeTab(e.value),
                                  child: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.add), onPressed: _addTab),
                IconButton(
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
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Close"),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          physics:
              const NeverScrollableScrollPhysics(), // Prevent swipe switching to avoid conflict with terminal input
          children: _terminalIds
              .map(
                (id) => TerminalView(terminalId: id, fontSize: widget.fontSize),
              )
              .toList(),
        ),
      ),
    );
  }
}

class TerminalView extends StatefulWidget {
  final int terminalId;
  final double fontSize;
  const TerminalView({
    super.key,
    required this.terminalId,
    required this.fontSize,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  TerminalFrame? _frame;
  Timer? _timer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (mounted) {
        setState(() {
          _frame = getTerminalFrame(id: widget.terminalId);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  /// Converts a Flutter KeyEvent into the correct terminal escape sequence or character.
  String? _keyEventToTerminalInput(KeyEvent event) {
    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    // ── Ctrl shortcuts ────────────────────────────────────────────────────────
    if (isCtrl && !isAlt) {
      // Ctrl+C  → ETX (interrupt)
      if (key == LogicalKeyboardKey.keyC) return '\x03';
      // Ctrl+D  → EOT (EOF / logout)
      if (key == LogicalKeyboardKey.keyD) return '\x04';
      // Ctrl+Z  → SUB (suspend)
      if (key == LogicalKeyboardKey.keyZ) return '\x1a';
      // Ctrl+L  → FF  (clear screen)
      if (key == LogicalKeyboardKey.keyL) return '\x0c';
      // Ctrl+A  → SOH (beginning of line)
      if (key == LogicalKeyboardKey.keyA) return '\x01';
      // Ctrl+E  → ENQ (end of line)
      if (key == LogicalKeyboardKey.keyE) return '\x05';
      // Ctrl+K  → VT  (kill to end of line)
      if (key == LogicalKeyboardKey.keyK) return '\x0b';
      // Ctrl+U  → NAK (kill to beginning of line)
      if (key == LogicalKeyboardKey.keyU) return '\x15';
      // Ctrl+W  → BS  (delete word before cursor)
      if (key == LogicalKeyboardKey.keyW) return '\x17';
      // Ctrl+R  → DC2 (reverse history search)
      if (key == LogicalKeyboardKey.keyR) return '\x12';
      // Ctrl+S  → XOFF (pause output / forward search)
      if (key == LogicalKeyboardKey.keyS) return '\x13';
      // Ctrl+Q  → XON  (resume output)
      if (key == LogicalKeyboardKey.keyQ) return '\x11';
      // Ctrl+P  → DLE  (previous history)
      if (key == LogicalKeyboardKey.keyP) return '\x10';
      // Ctrl+N  → SO   (next history)
      if (key == LogicalKeyboardKey.keyN) return '\x0e';
      // Ctrl+B  → STX  (move back one char)
      if (key == LogicalKeyboardKey.keyB) return '\x02';
      // Ctrl+F  → ACK  (move forward one char)
      if (key == LogicalKeyboardKey.keyF) return '\x06';
      // Ctrl+T  → EM   (transpose chars)
      if (key == LogicalKeyboardKey.keyT) return '\x14';
      // Ctrl+Y  → EM   (yank / paste kill-ring)
      if (key == LogicalKeyboardKey.keyY) return '\x19';
      // Ctrl+backslash → QUIT signal
      if (key == LogicalKeyboardKey.backslash) return '\x1c';
      // Ctrl+]  → GS   (escape character for telnet etc.)
      if (key == LogicalKeyboardKey.bracketRight) return '\x1d';
      // Ctrl+Space / Ctrl+@ → NUL
      if (key == LogicalKeyboardKey.space) return '\x00';

      // Ctrl+Arrow  → word jump (xterm sequences)
      if (key == LogicalKeyboardKey.arrowLeft) return '\x1b[1;5D';
      if (key == LogicalKeyboardKey.arrowRight) return '\x1b[1;5C';
      if (key == LogicalKeyboardKey.arrowUp) return '\x1b[1;5A';
      if (key == LogicalKeyboardKey.arrowDown) return '\x1b[1;5B';

      // Ctrl+Home / End
      if (key == LogicalKeyboardKey.home) return '\x1b[1;5H';
      if (key == LogicalKeyboardKey.end) return '\x1b[1;5F';

      // Ctrl+Delete → delete word forward
      if (key == LogicalKeyboardKey.delete) return '\x1b[3;5~';
    }

    // ── Alt (Meta) shortcuts ──────────────────────────────────────────────────
    if (isAlt && !isCtrl) {
      if (key == LogicalKeyboardKey.keyB) return '\x1bb'; // Alt+B → back word
      if (key == LogicalKeyboardKey.keyF)
        return '\x1bf'; // Alt+F → forward word
      if (key == LogicalKeyboardKey.keyD)
        return '\x1bd'; // Alt+D → delete word forward
      if (key == LogicalKeyboardKey.backspace)
        return '\x1b\x7f'; // Alt+BS → delete word back
      if (key == LogicalKeyboardKey.keyU)
        return '\x1bu'; // Alt+U → uppercase word
      if (key == LogicalKeyboardKey.keyL)
        return '\x1bl'; // Alt+L → lowercase word
      if (key == LogicalKeyboardKey.keyC)
        return '\x1bc'; // Alt+C → capitalize word
      if (key == LogicalKeyboardKey.keyR) return '\x1br'; // Alt+R → revert line
      if (key == LogicalKeyboardKey.period)
        return '\x1b.'; // Alt+. → last argument
      if (key == LogicalKeyboardKey.digit0) return '\x1b0';
      // Alt+<digit> → argument prefix
      for (int i = 1; i <= 9; i++) {
        if (key.keyId == LogicalKeyboardKey.digit1.keyId + i - 1) {
          return '\x1b$i';
        }
      }
      // Alt+Arrow → word jump (some terminals)
      if (key == LogicalKeyboardKey.arrowLeft) return '\x1b[1;3D';
      if (key == LogicalKeyboardKey.arrowRight) return '\x1b[1;3C';
    }

    // ── Shift shortcuts ───────────────────────────────────────────────────────
    if (isShift) {
      if (key == LogicalKeyboardKey.arrowUp) return '\x1b[1;2A';
      if (key == LogicalKeyboardKey.arrowDown) return '\x1b[1;2B';
      if (key == LogicalKeyboardKey.pageUp) return '\x1b[5;2~';
      if (key == LogicalKeyboardKey.pageDown) return '\x1b[6;2~';
      if (key == LogicalKeyboardKey.tab)
        return '\x1b[Z'; // Shift+Tab → back-tab
    }

    // ── Special / navigation keys ─────────────────────────────────────────────
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

    // ── Printable character (already includes Shift-modified chars via OS) ────
    final character = event is KeyDownEvent || event is KeyRepeatEvent
        ? event.character
        : null;
    if (character != null && character.isNotEmpty) return character;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _focusNode.requestFocus(),
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
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

  TerminalPainter(this.frame, this.fontSize, this.textColor);

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: textColor,
      fontFamily: 'monospace',
      fontSize: fontSize,
    );

    // Measure character size
    final textPainter = TextPainter(
      text: TextSpan(text: 'X', style: textStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final double charWidth = textPainter.width;
    final double charHeight = textPainter.height;

    for (int y = 0; y < frame.rows; y++) {
      for (int x = 0; x < frame.cols; x++) {
        final index = y * frame.cols + x;
        if (index >= frame.cells.length) return;

        final cell = frame.cells[index];
        if (cell.content == ' ' || cell.content.isEmpty) continue;

        final cellPainter = TextPainter(
          text: TextSpan(text: cell.content, style: textStyle),
          textDirection: TextDirection.ltr,
        );
        cellPainter.layout();
        cellPainter.paint(canvas, Offset(x * charWidth, y * charHeight));
      }
    }

    // Draw cursor
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
  }

  @override
  bool shouldRepaint(covariant TerminalPainter oldDelegate) {
    return true; // Simple for demo
  }
}
