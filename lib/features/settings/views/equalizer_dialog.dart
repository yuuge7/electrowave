import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../services/settings_persistence.dart';

/// 5-band equalizer with presets, driving libmpv's own filter chain.
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
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kEqPresets.keys)
                  ActionChip(
                    label: Text(preset),
                    backgroundColor: colors.surfaceAlt,
                    labelStyle: TextStyle(color: colors.textSecondary),
                    side: BorderSide(color: colors.border),
                    onPressed: () => controller.applyEqPreset(preset),
                  ),
              ],
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
                                color: colors.textFaint, fontSize: 11),
                          ),
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Slider(
                                value: settings.eqGainsDb[i]
                                    .clamp(-kEqMaxGainDb, kEqMaxGainDb),
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
                                color: colors.textSecondary, fontSize: 11),
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
      actions: [
        TextButton(
          onPressed: controller.resetEq,
          child: Text('Reset', style: TextStyle(color: colors.textFaint)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Done',
              style:
                  TextStyle(color: colors.accent, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
