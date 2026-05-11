import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  FlexScheme _scheme = FlexScheme.hippieBlue;
  double _fontScale = 1.0;
  String _fontFamily = 'Roboto';

  ThemeMode get mode => _mode;
  FlexScheme get scheme => _scheme;
  double get fontScale => _fontScale;
  String get fontFamily => _fontFamily;

  static const fonts = ['Roboto', 'Lato', 'Open Sans', 'Montserrat', 'Poppins', 'Nunito'];

  TextTheme _googleTextTheme(TextTheme base) => GoogleFonts.getTextTheme(_fontFamily, base);

  ThemeData get light {
    final t = FlexThemeData.light(scheme: _scheme, useMaterial3: true);
    return t.copyWith(textTheme: _googleTextTheme(t.textTheme));
  }

  ThemeData get dark {
    final t = FlexThemeData.dark(scheme: _scheme, useMaterial3: true);
    return t.copyWith(textTheme: _googleTextTheme(t.textTheme));
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final modeIdx = p.getInt('theme_mode');
    if (modeIdx != null) _mode = ThemeMode.values[modeIdx];
    final schemeIdx = p.getInt('theme_scheme');
    if (schemeIdx != null && schemeIdx < FlexScheme.values.length) _scheme = FlexScheme.values[schemeIdx];
    _fontScale = p.getDouble('font_scale') ?? _fontScale;
    _fontFamily = p.getString('font_family') ?? _fontFamily;
    notifyListeners();
  }

  void setMode(ThemeMode m) { if (_mode != m) { _mode = m; _save(); notifyListeners(); } }
  void setScheme(FlexScheme s) { if (_scheme != s) { _scheme = s; _save(); notifyListeners(); } }
  void setFontScale(double s) { if (_fontScale != s) { _fontScale = s; _save(); notifyListeners(); } }
  void setFontFamily(String f) { if (_fontFamily != f) { _fontFamily = f; _save(); notifyListeners(); } }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme_mode', _mode.index);
    await p.setInt('theme_scheme', _scheme.index);
    await p.setDouble('font_scale', _fontScale);
    await p.setString('font_family', _fontFamily);
  }
}
