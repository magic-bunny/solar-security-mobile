import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'providers/device_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_detail_screen.dart';
import 'screens/me_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/recordings_screen.dart';
import 'screens/user_management_screen.dart';
import 'screens/weather_screen.dart';
import 'screens/relay_control_screen.dart';
import 'screens/device_logs_screen.dart';

final List<RouteBase> _routes = [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

    // Main app with bottom nav
    StatefulShellRoute.indexedStack(
      builder: (_, __, navigationShell) => AppShell(navigationShell: navigationShell),
      branches: [
        // Tab 0: Home (Map + Device list)
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const DashboardScreen(),
            routes: [
              GoRoute(
                path: 'device/:id',
                builder: (_, s) => DeviceDetailScreen(deviceId: s.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: ':tab',
                    builder: (_, s) => DeviceDetailScreen(
                      deviceId: s.pathParameters['id']!,
                      initialTab: s.pathParameters['tab'],
                    ),
                  ),
                ],
              ),
              GoRoute(path: 'relay/:id', builder: (_, s) => RelayControlScreen(deviceId: s.pathParameters['id']!)),
              GoRoute(path: 'recordings', builder: (_, s) => RecordingsScreen(
                cameraId: s.uri.queryParameters['camera'],
                cameraName: s.uri.queryParameters['name'],
              )),
              GoRoute(path: 'weather', builder: (_, __) => const WeatherScreen()),
              GoRoute(path: 'users', builder: (_, __) => const UserManagementScreen()),
              GoRoute(path: 'logs', builder: (_, __) => const DeviceLogsScreen()),
            ],
          ),
        ]),
        // Tab 1: Alerts
        StatefulShellBranch(routes: [
          GoRoute(path: '/alerts', builder: (ctx, __) {
            return const AlertsScreen();
          }),
        ]),
        // Tab 2: Settings
        StatefulShellBranch(routes: [
          GoRoute(path: '/settings', builder: (_, __) => const MeScreen()),
        ]),
      ],
    ),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('KeyEvent') ||
        details.exceptionAsString().contains('KeyDownEvent') ||
        details.exceptionAsString().contains('KeyUpEvent')) return;
    FlutterError.presentError(details);
  };

  final authProvider = AuthProvider();
  final themeProvider = ThemeProvider()..load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: SolarSecurityApp(authProvider: authProvider),
    ),
  );
}

class SolarSecurityApp extends StatefulWidget {
  final AuthProvider authProvider;
  const SolarSecurityApp({super.key, required this.authProvider});

  @override
  State<SolarSecurityApp> createState() => _SolarSecurityAppState();
}

class _SolarSecurityAppState extends State<SolarSecurityApp> with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = GoRouter(
      initialLocation: '/login',
      redirect: (_, state) {
        final loggedIn = widget.authProvider.isAuthenticated;
        final onLogin = state.matchedLocation == '/login';
        if (!loggedIn && !onLogin) return '/login';
        if (loggedIn && onLogin) return '/';
        return null;
      },
      routes: _routes,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.authProvider.isAuthenticated) {
      debugPrint('[App] Resumed from background');
      final conn = context.read<ConnectionProvider>();
      final auth = context.read<AuthProvider>();
      final dp = context.read<DeviceProvider>();
      conn.ensureConnected(auth, dp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Solar Security',
      theme: context.watch<ThemeProvider>().light,
      darkTheme: context.watch<ThemeProvider>().dark,
      themeMode: context.watch<ThemeProvider>().mode,
      routerConfig: _router,
      builder: (context, child) {
        final scale = context.read<ThemeProvider>().fontScale;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
    );
  }
}
