import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/color_tile.dart';
import 'package:flutter_alacritty/constants.dart';
import 'package:flutter_alacritty/settings_tile.dart';

import 'src/rust/api/simple.dart';

class TerminalSettingsPage extends StatefulWidget {
  final TermPreferences initialPrefs;
  final ValueChanged<TermPreferences> onPrefsChanged;

  const TerminalSettingsPage({
    super.key,
    required this.initialPrefs,
    required this.onPrefsChanged,
  });

  @override
  State<TerminalSettingsPage> createState() => _TerminalSettingsPageState();
}

class _TerminalSettingsPageState extends State<TerminalSettingsPage> {
  late String _fontFamily;
  late double _fontSize;
  late double _lineHeight;
  late int _colorFg;
  late int _colorBg;
  late int _colorCursor;
  late int _colorSelection;
  late Uint32List _palette;
  late String _themeName;

  static const _bg = Color(0xFF1A1B1E);
  static const _surface = Color(0xFF25262B);
  static const _border = Color(0xFF2C2D32);
  static const _textPrimary = Color(0xFFCDD6F4);
  static const _textMuted = Color(0xFF6C7086);
  static const _accent = Color(0xFFFFAB40); // orange

  @override
  void initState() {
    super.initState();
    final p = widget.initialPrefs;
    _fontFamily = p.fontFamily;
    _fontSize = p.fontSize;
    _lineHeight = p.lineHeight;
    _colorFg = p.colorForeground;
    _colorBg = p.colorBackground;
    _colorCursor = p.colorCursor;
    _colorSelection = p.colorSelection;
    _palette = p.palette;
    _themeName = _detectTheme();
  }

  String _detectTheme() {
    for (final t in terminalThemes) {
      if (t.bg == _colorBg && t.fg == _colorFg) return t.name;
    }
    return 'custom';
  }

  TermPreferences _buildPrefs() => TermPreferences(
    fontFamily: _fontFamily,
    fontSize: _fontSize,
    lineHeight: _lineHeight,
    colorForeground: _colorFg,
    colorBackground: _colorBg,
    colorCursor: _colorCursor,
    colorSelection: _colorSelection,
    palette: _palette,
  );

  void _applyTheme(TermTheme t) {
    setState(() {
      _themeName = t.name;
      _colorFg = t.fg;
      _colorBg = t.bg;
      _colorCursor = t.cursor;
      _colorSelection = t.selection;
      _palette = t.palette;
    });
  }

  // Bottom sheets

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          ...terminalThemes.map(
            (t) => ListTile(
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(0xFF000000 | t.bg),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _border),
                ),
                child: Center(
                  child: Text(
                    'A',
                    style: TextStyle(
                      color: Color(0xFF000000 | t.fg),
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              title: Text(
                t.name,
                style: const TextStyle(
                  color: _textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
              trailing: _themeName == t.name
                  ? const Icon(Icons.check, color: _accent, size: 18)
                  : null,
              onTap: () {
                _applyTheme(t);
                Navigator.pop(context);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showFontPicker() {
    final families = [
      'monospace',
      'JetBrains Mono',
      'Fira Code',
      'Hack',
      'Source Code Pro',
      'Inconsolata',
      'Cascadia Code',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        double tempFontSize = _fontSize;
        String tempFontFamily = _fontFamily;

        return StatefulBuilder(
          builder: (context, modalSetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    'Font Size: ${_fontSize.round()}px',
                    style: const TextStyle(
                      color: _textMuted,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Slider(
                    value: tempFontSize,
                    // value: _fontSize,
                    min: 8,
                    max: 32,
                    divisions: 24,
                    activeColor: _accent,
                    inactiveColor: _border,
                    label: '${_fontSize.round()}px',
                    // onChanged: (v) => setState(() => _fontSize = v),
                    onChanged: (v) {
                      modalSetState(() {
                        tempFontSize = v;
                      });

                      setState(() {
                        _fontSize = v;
                      });
                    },
                  ),
                ),
                const Divider(color: _border, height: 1),
                ...families.map(
                  (f) => ListTile(
                    title: Text(
                      f,
                      style: TextStyle(
                        color: _textPrimary,
                        fontFamily: f == 'monospace' ? 'monospace' : null,
                        fontSize: 14,
                      ),
                    ),
                    // trailing: _fontFamily == f
                    //     ? const Icon(Icons.check, color: _accent, size: 18)
                    //     : null,
                    trailing: tempFontFamily == f
                        ? const Icon(Icons.check, color: _accent, size: 18)
                        : null,
                    // onTap: () => setState(() => _fontFamily = f),
                    onTap: () {
                      modalSetState(() {
                        tempFontFamily = f;
                      });
                      setState(() {
                        _fontFamily = f;
                      });
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _surface,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              // Top bar
              Container(
                height: 52,
                decoration: const BoxDecoration(
                  color: _surface,
                  border: Border(bottom: BorderSide(color: _border)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: _textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: _textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        widget.onPrefsChanged(_buildPrefs());
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          color: _accent,
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Settings list
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _SectionHeader('Customize'),

                    _TileContainer(
                      child: SettingsTile(
                        label: 'Theme',
                        value: _themeName,
                        onTap: _showThemePicker,
                      ),
                    ),

                    _TileContainer(
                      child: SettingsTile(
                        label: 'Font',
                        value:
                            '${_fontFamily == 'monospace' ? 'Default' : _fontFamily}  ${_fontSize.round()}px',
                        onTap: _showFontPicker,
                      ),
                    ),

                    _SectionHeader('Colors'),

                    _TileContainer(
                      child: ColorTile(label: 'Foreground', color: _colorFg),
                    ),
                    _TileContainer(
                      child: ColorTile(label: 'Background', color: _colorBg),
                    ),
                    _TileContainer(
                      child: ColorTile(label: 'Cursor', color: _colorCursor),
                    ),
                    _TileContainer(
                      child: ColorTile(
                        label: 'Selection',
                        color: _colorSelection,
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper widgets

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF6C7086),
        fontFamily: 'monospace',
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _TileContainer extends StatelessWidget {
  final Widget child;
  const _TileContainer({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF25262B),
      border: Border(bottom: BorderSide(color: Color(0xFF2C2D32))),
    ),
    child: child,
  );
}
