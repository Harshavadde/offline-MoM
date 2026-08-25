import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/accent_colors.dart';
import '../../../../providers/app_providers.dart';

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final notifier = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (value) {
                if (value != null) notifier.setThemeMode(value);
              },
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(_themeModeLabel(mode)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Accent color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final color in AccentColors.presets)
                _ColorSwatch(
                  color: color,
                  isSelected: settings.accentColorValue == color.toARGB32(),
                  onTap: () => notifier.setAccentColor(color),
                ),
              _CustomColorSwatch(
                isSelected: !AccentColors.presets
                    .any((c) => c.toARGB32() == settings.accentColorValue),
                onPick: (color) => notifier.setAccentColor(color),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'Match system',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = AccentColors.names[color.toARGB32()] ?? 'Accent color';
    return Semantics(
      button: true,
      selected: isSelected,
      label: isSelected ? '$name, selected' : name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                : null,
          ),
          child: isSelected
              ? const Icon(Icons.check_rounded, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _CustomColorSwatch extends StatelessWidget {
  const _CustomColorSwatch({required this.isSelected, required this.onPick});

  final bool isSelected;
  final ValueChanged<Color> onPick;

  Future<void> _showPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Color>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('More colors', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final color in AccentColors.extended)
                    _ColorSwatch(
                      color: color,
                      isSelected: false,
                      onTap: () => Navigator.of(sheetContext).pop(color),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: isSelected,
      label: isSelected ? 'Custom accent color, selected' : 'Choose a custom accent color',
      child: InkWell(
        onTap: () => _showPicker(context),
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surfaceContainerHighest,
            border: Border.all(
              color: isSelected ? scheme.onSurface : scheme.outline,
              width: isSelected ? 3 : 1,
            ),
          ),
          child: Icon(Icons.add_rounded, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
