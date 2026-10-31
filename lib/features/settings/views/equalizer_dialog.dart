import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../services/settings_persistence.dart';

/// 10-band equalizer with presets, driving libmpv's own filter chain.
class EqualizerDialog extends ConsumerWidget {
  const EqualizerDialog({super.key});

  String _formatBand(int hz) => hz >= 1000 ? '${(hz / 1000).round()}k' : '$hz';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Text('Equalizer', style: TextStyle(color: colors.textPrimary)),
          const Spacer(),
          Switch(
            value: settings.eqEnabled,
            activeThumbColor: colors.accent,
            onChanged: controller.setEqEnabled,
          ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in {
                    ...kEqPresets,
                    ...settings.eqUserPresets,
                  }.keys)
                    ActionChip(
                      label: Text(preset),
                      backgroundColor: colors.surfaceAlt,
                      labelStyle: TextStyle(color: colors.textSecondary),
                      side: BorderSide(color: colors.border),
                      onPressed: () => controller.applyEqPreset(preset),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final text = TextEditingController();
                      final name = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Save EQ preset'),
                          content: TextField(
                            controller: text,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Preset name',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(context, text.text.trim()),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                      text.dispose();
                      if (name != null && name.isNotEmpty) {
                        await controller.saveEqPreset(name);
                      }
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save preset'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final path = await FilePicker.platform.saveFile(
                        fileName: 'electrowave-eq.json',
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (path != null) {
                        await File(path).writeAsString(
                          jsonEncode({
                            'format': 'electrowave-eq',
                            'version': 1,
                            'presets': settings.eqUserPresets,
                          }),
                          flush: true,
                        );
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Export presets'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (result?.files.single.path == null) return;
                      try {
                        final raw =
                            jsonDecode(
                                  await File(
                                    result!.files.single.path!,
                                  ).readAsString(),
                                )
                                as Map<String, dynamic>;
                        if (raw['format'] != 'electrowave-eq' ||
                            raw['version'] != 1 ||
                            raw['presets'] is! Map) {
                          throw const FormatException();
                        }
                        final presets = <String, List<double>>{};
                        for (final entry in (raw['presets'] as Map).entries) {
                          if (entry.key is! String ||
                              entry.value is! List ||
                              (entry.value as List).length != 10) {
                            throw const FormatException();
                          }
                          presets[entry.key
                              as String] = (entry.value as List).map((n) {
                            if (n is! num || !n.isFinite || n < -12 || n > 12) {
                              throw const FormatException();
                            }
                            return n.toDouble();
                          }).toList();
                        }
                        await controller.importEqPresets(presets);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Choose a valid Electrowave EQ preset file.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.upload),
                    label: const Text('Import presets'),
                  ),
                ],
              ),
              const Text(
                'Preamp (automatic headroom also reduces gain by the largest band boost)',
              ),
              Slider(
                value: settings.eqPreampDb,
                min: -24,
                max: 0,
                divisions: 48,
                label: '${settings.eqPreampDb.toStringAsFixed(1)} dB',
                onChanged: controller.setPreamp,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < kEqBandFrequencies.length; i++)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${settings.eqGainsDb[i].toStringAsFixed(1)} dB',
                              style: TextStyle(
                                color: colors.textFaint,
                                fontSize: 11,
                              ),
                            ),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Slider(
                                  semanticFormatterCallback: (value) =>
                                      '${kEqBandFrequencies[i]} hertz, ${value.toStringAsFixed(1)} decibels',
                                  value: settings.eqGainsDb[i].clamp(
                                    -kEqMaxGainDb,
                                    kEqMaxGainDb,
                                  ),
                                  min: -kEqMaxGainDb,
                                  max: kEqMaxGainDb,
                                  divisions: (kEqMaxGainDb * 4).round(),
                                  activeColor: colors.accent,
                                  inactiveColor: colors.border,
                                  onChanged: (value) =>
                                      controller.setEqBand(i, value),
                                ),
                              ),
                            ),
                            Text(
                              '${_formatBand(kEqBandFrequencies[i])}Hz',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                settings.eqEnabled
                    ? 'Bands are applied live; a flat curve costs nothing.'
                    : 'The equalizer is off — bands are saved but not applied.',
                style: TextStyle(color: colors.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: controller.resetEq,
          child: Text('Reset', style: TextStyle(color: colors.textFaint)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Done',
            style: TextStyle(color: colors.accent, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
