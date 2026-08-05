import 'package:flutter_test/flutter_test.dart';

import 'package:electrowave/features/player/services/audio_engine.dart';
import 'package:electrowave/features/settings/services/settings_persistence.dart';

const _stretch = 'scaletempo2=search-interval=30:window-size=20';

void main() {
  group('buildFilterChain', () {
    test('is empty when nothing is asked for', () {
      expect(
        buildFilterChain(settings: const AppSettings(), stretchFilter: null),
        '',
      );
      expect(buildFilterChain(settings: null, stretchFilter: null), '');
    });

    test('a disabled or flat EQ adds nothing', () {
      expect(
        buildFilterChain(
          settings: const AppSettings(eqGainsDb: [6, -3, 0, 2, 4]),
          stretchFilter: null,
        ),
        '',
      );
      expect(
        buildFilterChain(
          settings: const AppSettings(eqEnabled: true),
          stretchFilter: null,
        ),
        '',
      );
    });

    test('EQ bands go into a single bracketed lavfi graph', () {
      final chain = buildFilterChain(
        settings: const AppSettings(eqEnabled: true, eqGainsDb: [6, 0, 0, 0, -3]),
        stretchFilter: null,
      );

      // One node for the whole equalizer, not one per band: a long af chain is
      // what makes mpv's audio reinit fail and playback stall.
      expect(chain, startsWith('lavfi=['));
      expect(chain, endsWith(']'));
      expect('lavfi='.allMatches(chain).length, 1);

      // Inaudible bands are skipped, the rest keep their frequencies.
      expect('equalizer='.allMatches(chain).length, 2);
      expect(chain, contains('f=60'));
      expect(chain, contains('g=6.0'));
      expect(chain, contains('f=14000'));
      expect(chain, contains('g=-3.0'));
      expect(chain, isNot(contains('f=230')));
    });

    test('the stretcher is last so it absorbs the speed change', () {
      final chain = buildFilterChain(
        settings: const AppSettings(eqEnabled: true, eqGainsDb: [6, 0, 0, 0, 0]),
        stretchFilter: _stretch,
      );

      expect(chain.indexOf('lavfi=['), lessThan(chain.indexOf('scaletempo2')));
      expect(chain, endsWith(_stretch));

      // The graph's internal commas stay inside the brackets, so mpv reads
      // exactly two top-level filters.
      final topLevel = chain.substring(chain.indexOf(']') + 1);
      expect(topLevel, ',$_stretch');
    });

    test('speed alone yields just the stretcher', () {
      expect(
        buildFilterChain(settings: const AppSettings(), stretchFilter: _stretch),
        _stretch,
      );
    });
  });
}
