import 'package:objectbox/objectbox.dart';

@Entity()
class AppSettings {
  @Id()
  int id;

  double fontSize;
  String? fontFamily;
  String? colorForeground;
  String? colorBackground;
  String? colorCursor;
  String? colorSelection;

  AppSettings({
    this.id = 0,
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrains Mono',
    this.colorForeground = '#FFFFFF',
    this.colorBackground = '#000000',
    this.colorCursor = '#FFFFFF',
    this.colorSelection = '#264F78',
  });
}
