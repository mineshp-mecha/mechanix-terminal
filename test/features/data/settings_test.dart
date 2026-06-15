import 'package:flutter_test/flutter_test.dart';
import 'package:mechanix_terminal/features/data/settings.dart';

void main() {
  group('AppSettings', () {
    test('Constructor applies default values correctly', () {
      final settings = AppSettings();

      expect(settings.id, 0);
      expect(settings.fontSize, 14.0);
      expect(settings.fontFamily, 'JetBrains Mono');
      expect(settings.colorForeground, '#FFFFFF');
      expect(settings.colorBackground, '#000000');
      expect(settings.colorCursor, '#FFFFFF');
      expect(settings.colorSelection, '#264F78');
    });

    test('Constructor applies custom values correctly', () {
      final settings = AppSettings(
        id: 1,
        fontSize: 16.0,
        fontFamily: 'Roboto',
        colorForeground: '#111111',
        colorBackground: '#EEEEEE',
        colorCursor: '#FF0000',
        colorSelection: '#00FF00',
      );

      expect(settings.id, 1);
      expect(settings.fontSize, 16.0);
      expect(settings.fontFamily, 'Roboto');
      expect(settings.colorForeground, '#111111');
      expect(settings.colorBackground, '#EEEEEE');
      expect(settings.colorCursor, '#FF0000');
      expect(settings.colorSelection, '#00FF00');
    });
  });
}
