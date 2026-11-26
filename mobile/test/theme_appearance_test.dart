import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sorynth/core/constants/app_colors.dart';
import 'package:sorynth/core/providers/app_providers.dart';
import 'package:sorynth/core/theme/app_theme.dart';
import 'package:sorynth/data/services/settings_service.dart';
import 'package:sorynth/features/home/home_screen.dart';
import 'package:sorynth/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late SettingsService settingsService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  Widget buildSettingsWithTheme({
    required ThemeMode themeMode,
    Brightness platformBrightness = Brightness.light,
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsServiceProvider.overrideWithValue(settingsService),
      ],
      child: MaterialApp(
        themeMode: themeMode,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const SettingsScreen(),
      ),
    );
  }

  group('AppTheme Architecture & Palette Verification', () {
    test('Light theme defines correct color scheme, scaffold and surfaces', () {
      final light = AppTheme.lightTheme;
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, AppColors.background);
      expect(light.cardColor, AppColors.white);
      expect(light.colorScheme.surface, AppColors.white);
      expect(light.colorScheme.onSurface, AppColors.textDark);
      expect(light.colorScheme.primary, AppColors.primaryBlue);
      expect(light.dividerColor, AppColors.borderLight);
    });

    test('Dark theme defines dark background, dark card surface, and light text', () {
      final dark = AppTheme.darkTheme;
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, AppColors.darkBackground);
      expect(dark.cardColor, AppColors.darkCardSurface);
      expect(dark.colorScheme.surface, AppColors.darkCardSurface);
      expect(dark.colorScheme.onSurface, AppColors.white);
      expect(dark.colorScheme.onSurfaceVariant, AppColors.darkSecondaryText);
      expect(dark.colorScheme.outline, AppColors.darkBorder);
      expect(dark.dividerColor, AppColors.darkBorder);
      expect(dark.colorScheme.primary, AppColors.primaryBlue);
    });

    test('SegmentedButton theme is configured for high contrast in light & dark', () {
      final lightSegment = AppTheme.lightTheme.segmentedButtonTheme;
      final darkSegment = AppTheme.darkTheme.segmentedButtonTheme;

      expect(lightSegment.style, isNotNull);
      expect(darkSegment.style, isNotNull);

      // Verify selected state background color
      final lightSelectedBg = lightSegment.style!.backgroundColor?.resolve({WidgetState.selected});
      expect(lightSelectedBg, AppColors.primaryBlue.withValues(alpha: 0.12));

      final darkSelectedBg = darkSegment.style!.backgroundColor?.resolve({WidgetState.selected});
      expect(darkSelectedBg, AppColors.primaryBlue.withValues(alpha: 0.35));

      // Verify unselected state background color
      final lightUnselectedBg = lightSegment.style!.backgroundColor?.resolve({});
      expect(lightUnselectedBg, Colors.transparent);

      final darkUnselectedBg = darkSegment.style!.backgroundColor?.resolve({});
      expect(darkUnselectedBg, Colors.transparent);
    });
  });

  group('Appearance Screen Rendering in Light Mode', () {
    testWidgets('Renders with light background, dark titles and legible text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildSettingsWithTheme(themeMode: ThemeMode.light),
      );
      await tester.pumpAndSettle();

      // Check AppBar and Scaffold
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.background);

      // Verify Appearance header and SegmentedButton exist
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Verify section header text is secondary text color
      final sectionTitle = tester.widget<Text>(find.text('App Preferences & About'));
      expect(sectionTitle.style?.color, AppColors.secondaryText);

      // Verify appearance title is dark navy
      final appearanceTitle = tester.widget<Text>(find.text('Appearance'));
      expect(appearanceTitle.style?.color, AppColors.textDark);
    });
  });

  group('Appearance Screen Rendering in Dark Mode', () {
    testWidgets('Renders with dark navy background, dark surfaces and white text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildSettingsWithTheme(themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();

      // Check Scaffold background is dark navy
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.darkBackground);

      // Check section header is darkSecondaryText
      final sectionTitle = tester.widget<Text>(find.text('App Preferences & About'));
      expect(sectionTitle.style?.color, AppColors.darkSecondaryText);

      // Check Appearance title is white, NOT dark navy or invisible
      final appearanceTitle = tester.widget<Text>(find.text('Appearance'));
      expect(appearanceTitle.style?.color, AppColors.white);

      // Verify all 3 mode labels are present
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });
  });

  group('Appearance Screen in System Mode', () {
    testWidgets('Adapts to simulated light platform brightness', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(() => tester.platformDispatcher.clearPlatformBrightnessTestValue());

      await tester.pumpWidget(
        buildSettingsWithTheme(themeMode: ThemeMode.system),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.background);

      final sectionTitle = tester.widget<Text>(find.text('App Preferences & About'));
      expect(sectionTitle.style?.color, AppColors.secondaryText);

      final appearanceTitle = tester.widget<Text>(find.text('Appearance'));
      expect(appearanceTitle.style?.color, AppColors.textDark);
    });

    testWidgets('Adapts to simulated dark platform brightness', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(() => tester.platformDispatcher.clearPlatformBrightnessTestValue());

      await tester.pumpWidget(
        buildSettingsWithTheme(themeMode: ThemeMode.system),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.darkBackground);

      final sectionTitle = tester.widget<Text>(find.text('App Preferences & About'));
      expect(sectionTitle.style?.color, AppColors.darkSecondaryText);

      final appearanceTitle = tester.widget<Text>(find.text('Appearance'));
      expect(appearanceTitle.style?.color, AppColors.white);
    });
  });

  group('Interactive Theme Switching via SegmentedButton', () {
    testWidgets('Tapping Dark switches themeMode and updates UI to dark palette', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsServiceProvider.overrideWithValue(settingsService),
          ],
          child: Consumer(
            builder: (context, ref, child) {
              final settings = ref.watch(settingsProvider);
              return MaterialApp(
                themeMode: settings.themeMode,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                home: const SettingsScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts in system mode (light on test runner)
      var scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.background);

      // Scroll to ensure SegmentedButton is in view
      await tester.scrollUntilVisible(find.text('Dark'), 100);
      await tester.pumpAndSettle();

      // Tap 'Dark' button
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      // Verify scaffold has transitioned to dark background
      scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.darkBackground);

      // Tap 'Light' button
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      // Verify scaffold has transitioned to light background
      scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.background);
    });
  });

  group('HomeScreen Dark Mode Contrast Verification', () {
    testWidgets('HomeScreen renders profile icon and greeting in dark theme with high contrast', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsServiceProvider.overrideWithValue(settingsService),
          ],
          child: MaterialApp(
            themeMode: ThemeMode.dark,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar has darkSurface background and subtle elevation in dark mode
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);
      final appBar = tester.widget<AppBar>(appBarFinder);
      expect(appBar.backgroundColor, equals(AppColors.darkSurface));
      expect(appBar.elevation, equals(0.5));
      expect(appBar.scrolledUnderElevation, equals(2.0));

      // Profile icon has white color in dark mode
      final iconFinder = find.byIcon(Icons.person_outline_rounded);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, equals(AppColors.white));

      // Greeting text has white color in dark mode
      final greetingFinder = find.text('Hello, Civilian Responder');
      expect(greetingFinder, findsOneWidget);
      final greetingText = tester.widget<Text>(greetingFinder);
      expect(greetingText.style?.color, equals(AppColors.white));
    });

    testWidgets('HomeScreen renders profile icon and greeting in light theme with high contrast', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsServiceProvider.overrideWithValue(settingsService),
          ],
          child: MaterialApp(
            themeMode: ThemeMode.light,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar has white background and subtle elevation in light mode
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);
      final appBar = tester.widget<AppBar>(appBarFinder);
      expect(appBar.backgroundColor, equals(AppColors.white));
      expect(appBar.elevation, equals(0.5));
      expect(appBar.scrolledUnderElevation, equals(2.0));

      // Profile icon has textDark color in light mode
      final iconFinder = find.byIcon(Icons.person_outline_rounded);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, equals(AppColors.textDark));

      // Greeting text has textDark color in light mode
      final greetingFinder = find.text('Hello, Civilian Responder');
      expect(greetingFinder, findsOneWidget);
      final greetingText = tester.widget<Text>(greetingFinder);
      expect(greetingText.style?.color, equals(AppColors.textDark));
    });
  });
}
