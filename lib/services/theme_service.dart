import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme {
  colorful,     // Gradient vibrant multicolor - TEMA DE BAZĂ
  current,      // Tema curentă PRO (dark elegantă cu teal) - PRO
}

class AppThemeData {
  final String name;
  final String description;
  final Color primaryColor;
  final Color backgroundColor;
  final Color cardColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color accentColor;
  final Brightness brightness;
  final bool isPro;
  final List<Color>? gradientColors;  // Pentru teme cu gradient
  final AlignmentGeometry? gradientBegin;
  final AlignmentGeometry? gradientEnd;

  const AppThemeData({
    required this.name,
    required this.description,
    required this.primaryColor,
    required this.backgroundColor,
    required this.cardColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.accentColor,
    required this.brightness,
    this.isPro = false,
    this.gradientColors,
    this.gradientBegin,
    this.gradientEnd,
  });
  
  // Helper pentru a verifica dacă tema are gradient
  bool get hasGradient => gradientColors != null && gradientColors!.length > 1;
}

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'selected_theme';
  AppTheme _currentTheme = AppTheme.current;
  
  AppTheme get currentTheme => _currentTheme;
  AppThemeData get currentThemeData => _getThemeData(_currentTheme);
  
  // Doar 2 teme disponibile - COLORFUL (bază) și CURRENT (PRO)
  static const Map<AppTheme, AppThemeData> themes = {
    // 1. COLORFUL - gradient vibrant multicolor - TEMA DE BAZĂ
    AppTheme.colorful: AppThemeData(
      name: 'COLORFUL',
      description: 'Gradient vibrant multicolor',
      primaryColor: Color(0xFF00D4FF),    // Cyan principal
      backgroundColor: Color(0xFF0F0F23),  // Fundal închis pentru contrast
      cardColor: Color(0xFF1A1A2E),       // Card-uri cu nuanță
      textColor: Colors.white,
      secondaryTextColor: Color(0xFFAAFFFF),
      accentColor: Color(0xFF4ECDC4),     // Teal accent
      brightness: Brightness.dark,
      isPro: false,  // TEMA DE BAZĂ
      gradientColors: [
        Color(0xFF00D4FF),  // Cyan
        Color(0xFF4ECDC4),  // Teal
        Color(0xFFFF6B6B),  // Coral
        Color(0xFFFFE66D),  // Galben
        Color(0xFF95A5FF),  // Lavandă
      ],
      gradientBegin: Alignment.topLeft,
      gradientEnd: Alignment.bottomRight,
    ),
    
    // 2. CURRENT (PRO) - păstrez tema existentă intactă
    AppTheme.current: AppThemeData(
      name: 'CURRENT',
      description: 'Tema PRO dark elegantă',
      primaryColor: Colors.teal,
      backgroundColor: Colors.black,
      cardColor: Color(0xFF1E1E1E),
      textColor: Colors.white,
      secondaryTextColor: Color(0xFF9E9E9E),
      accentColor: Colors.teal,
      brightness: Brightness.dark,
      isPro: true,  // RĂMÂNE PRO
    ),
  };
  
  ThemeService() {
    _loadTheme();
  }
  
  Future<void> _loadTheme() async {
    // Tema PRO (cu casă) forțată permanent pentru toți utilizatorii
    _currentTheme = AppTheme.current;
    notifyListeners();
  }
  
  Future<void> setTheme(AppTheme theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, theme.index);
    notifyListeners();
  }
  
  AppThemeData _getThemeData(AppTheme theme) {
    return themes[theme]!;
  }
  
  // Verifică dacă utilizatorul poate folosi o temă
  bool canUseTheme(AppTheme theme, bool isPro) {
    final themeData = themes[theme]!;
    return !themeData.isPro || isPro;
  }
  
  // Obține toate temele disponibile pentru utilizator
  List<AppTheme> getAvailableThemes(bool isPro) {
    return AppTheme.values.where((theme) => canUseTheme(theme, isPro)).toList();
  }
  
  // Obține Flutter ThemeData pentru aplicare în MaterialApp
  ThemeData get flutterThemeData {
    final theme = currentThemeData;
    
    return ThemeData(
      primarySwatch: _createMaterialColor(theme.primaryColor),
      primaryColor: theme.primaryColor,
      scaffoldBackgroundColor: theme.backgroundColor,
      cardColor: theme.cardColor,
      brightness: theme.brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: theme.primaryColor,
        brightness: theme.brightness,
        surface: theme.cardColor,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: theme.textColor),
        bodyMedium: TextStyle(color: theme.textColor),
        titleLarge: TextStyle(color: theme.textColor),
        titleMedium: TextStyle(color: theme.textColor),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: theme.cardColor,
        elevation: 2,
      ),
      useMaterial3: true,
    );
  }
  
  // Helper pentru a crea MaterialColor din Color
  MaterialColor _createMaterialColor(Color color) {
    final strengths = <double>[.05];
    final swatch = <int, Color>{};
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    
    for (final strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    
    return MaterialColor(color.toARGB32(), swatch);
  }
  
  // Helper pentru a crea un gradient decoration pentru temele cu gradient
  BoxDecoration? getGradientDecoration() {
    final theme = currentThemeData;
    if (!theme.hasGradient) return null;
    
    return BoxDecoration(
      gradient: LinearGradient(
        colors: theme.gradientColors!,
        begin: theme.gradientBegin ?? Alignment.topLeft,
        end: theme.gradientEnd ?? Alignment.bottomRight,
      ),
    );
  }
  
  // Helper pentru a obține background-ul corespunzător (gradient sau solid)
  Widget getBackgroundWidget(Widget child) {
    final theme = currentThemeData;
    
    if (theme.hasGradient) {
      return Container(
        decoration: getGradientDecoration(),
        child: child,
      );
    } else {
      return Container(
        color: theme.backgroundColor,
        child: child,
      );
    }
  }
} 