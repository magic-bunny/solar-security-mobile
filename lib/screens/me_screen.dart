import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import '../providers/auth_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/theme_provider.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  static const _schemes = [
    FlexScheme.green, FlexScheme.brandBlue, FlexScheme.deepPurple,
    FlexScheme.redWine, FlexScheme.amber, FlexScheme.shark,
    FlexScheme.aquaBlue, FlexScheme.sakura, FlexScheme.espresso,
    FlexScheme.money, FlexScheme.hippieBlue, FlexScheme.mandyRed,
  ];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final tp = context.watch<ThemeProvider>();
    final initial = user?.name ?? user?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          CircleAvatar(radius: 28, child: Text(
            initial.isEmpty ? '?' : initial[0].toUpperCase(),
            style: const TextStyle(fontSize: 24),
          )),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.name ?? user?.email ?? 'User', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (user?.role != null) Text(user!.role!, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
          ])),
        ]))),
        const SizedBox(height: 24),
        Text('Color Scheme', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final s in _schemes.sublist(row * 6, row * 6 + 6))
              GestureDetector(
                onTap: () => tp.setScheme(s),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? FlexThemeData.dark(scheme: s).colorScheme.primary
                        : FlexThemeData.light(scheme: s).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: tp.scheme == s
                        ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                        : null,
                  ),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 24),
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Theme.of(context).colorScheme.primaryContainer;
              return null;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Theme.of(context).colorScheme.onPrimaryContainer;
              return null;
            }),
          ),
          segments: const [
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('System')),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
          ],
          selected: {tp.mode},
          onSelectionChanged: (s) => tp.setMode(s.first),
        ),
        const SizedBox(height: 24),
        Text('Font Size', style: Theme.of(context).textTheme.titleMedium),
        Row(children: [
          const Text('A', style: TextStyle(fontSize: 12)),
          Expanded(child: Slider(
            value: tp.fontScale, min: 0.8, max: 1.4, divisions: 6,
            label: '${(tp.fontScale * 100).round()}%',
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (v) => tp.setFontScale(v),
          )),
          const Text('A', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        Text('Font', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in ThemeProvider.fonts)
            ChoiceChip(
              label: Text(f, style: TextStyle(fontFamily: f)),
              selected: tp.fontFamily == f,
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              onSelected: (_) => tp.setFontFamily(f),
            ),
        ]),
        const Divider(height: 40),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          onTap: () {
            context.read<ConnectionProvider>().disconnectAll();
            context.read<AuthProvider>().signOut();
            context.go('/login');
          },
        ),
      ]),
    );
  }
}
