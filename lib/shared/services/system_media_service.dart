import 'dart:async';
import 'dart:io';
import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/local_log.dart';
import '../../features/player/providers/player_provider.dart';
import '../../features/player/services/audio_engine.dart';

const _root = 'org.mpris.MediaPlayer2';
const _player = 'org.mpris.MediaPlayer2.Player';
final systemMediaProvider = Provider<void>((ref) {
  final service = SystemMediaService(ref);
  unawaited(service.initialize());
  ref.onDispose(service.dispose);
});

class SystemMediaService extends DBusObject {
  SystemMediaService(this.ref)
    : super(DBusObjectPath('/org/mpris/MediaPlayer2'));
  final Ref ref;
  static const _channel = MethodChannel('electrowave/media');
  DBusClient? _bus;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      if (Platform.isWindows) {
        _channel.setMethodCallHandler((call) async {
          await _command(call.method);
        });
        await _channel.invokeMethod<void>('initialize');
      } else if (Platform.isLinux) {
        _bus = DBusClient.session();
        await _bus!.registerObject(this);
        await _bus!.requestName('org.mpris.MediaPlayer2.electrowave');
      } else {
        return;
      }
      if (_disposed) return;
      final player = ref.read(playerProvider);
      _subscriptions.add(player.stream.playing.listen((_) => _update()));
      _subscriptions.add(player.stream.duration.listen((_) => _update()));
      ref.listen(currentTrackProvider, (_, _) => _update());
      ref.listen(shuffleProvider, (_, _) => _update());
      ref.listen(repeatModeProvider, (_, _) => _update());
      _update();
    } catch (e, st) {
      LocalLog.write(e, st);
    }
  }

  Future<void> _command(String command) async {
    if (_disposed) return;
    ref.read(audioEngineProvider).noteUserActivity();
    final player = ref.read(playerProvider);
    switch (command.toLowerCase()) {
      case 'play':
        await player.play();
      case 'pause':
        await player.pause();
      case 'playpause':
        await player.playOrPause();
      case 'stop':
        await player.pause();
        await player.seek(Duration.zero);
      case 'next':
        ref.read(playbackControllerProvider).playNextTrack();
      case 'previous':
        ref.read(playbackControllerProvider).playPreviousTrack();
      case 'raise':
        await windowManager.show();
        await windowManager.focus();
    }
  }

  Map<String, DBusValue> _properties(String interface) {
    if (interface == _root) {
      return {
        'CanQuit': const DBusBoolean(false),
        'CanRaise': const DBusBoolean(true),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('Electrowave'),
        'DesktopEntry': const DBusString('io.github.yuuge7.electrowave'),
        'SupportedUriSchemes': DBusArray.string(['file']),
        'SupportedMimeTypes': DBusArray.string([
          'audio/mpeg',
          'audio/flac',
          'audio/ogg',
          'audio/wav',
        ]),
      };
    }
    if (interface != _player) return {};
    final track = ref.read(currentTrackProvider);
    final player = ref.read(playerProvider);
    return {
      'PlaybackStatus': DBusString(
        track == null
            ? 'Stopped'
            : player.state.playing
            ? 'Playing'
            : 'Paused',
      ),
      'LoopStatus': DBusString(switch (ref.read(repeatModeProvider)) {
        PlaybackRepeatMode.off => 'None',
        PlaybackRepeatMode.all => 'Playlist',
        PlaybackRepeatMode.one => 'Track',
      }),
      'Rate': DBusDouble(player.state.rate),
      'Shuffle': DBusBoolean(ref.read(shuffleProvider)),
      'Volume': DBusDouble(player.state.volume / 100),
      'Position': DBusInt64(player.state.position.inMicroseconds),
      'MinimumRate': const DBusDouble(0.5),
      'MaximumRate': const DBusDouble(2),
      'CanGoNext': const DBusBoolean(true),
      'CanGoPrevious': const DBusBoolean(true),
      'CanPlay': const DBusBoolean(true),
      'CanPause': const DBusBoolean(true),
      'CanSeek': const DBusBoolean(true),
      'CanControl': const DBusBoolean(true),
      'Metadata': DBusDict.stringVariant(
        track == null
            ? {}
            : {
                'mpris:trackid': DBusObjectPath(
                  '/org/mpris/MediaPlayer2/track/${track.id}',
                ),
                'mpris:length': DBusInt64(track.durationMs * 1000),
                'xesam:title': DBusString(track.title),
                'xesam:artist': DBusArray.string([track.artist]),
                'xesam:album': DBusString(track.album),
                if (track.coverArtPath != null)
                  'mpris:artUrl': DBusString(
                    Uri.file(track.coverArtPath!).toString(),
                  ),
                'xesam:url': DBusString(Uri.file(track.filePath).toString()),
              },
      ),
    };
  }

  void _update() {
    if (_disposed) return;
    if (Platform.isWindows) {
      final track = ref.read(currentTrackProvider);
      unawaited(
        _channel
            .invokeMethod<void>('update', {
              'title': track?.title ?? '',
              'artist': track?.artist ?? '',
              'album': track?.album ?? '',
              'cover': track?.coverArtPath ?? '',
              'playing': ref.read(playerProvider).state.playing,
              'durationMs': track?.durationMs ?? 0,
            })
            .catchError((Object e) => LocalLog.write(e)),
      );
    } else if (_bus != null) {
      final props = _properties(_player)..remove('Position');
      unawaited(
        emitPropertiesChanged(
          _player,
          changedProperties: props,
        ).catchError((Object e) => LocalLog.write(e)),
      );
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    for (final interface in [_root, _player])
      DBusIntrospectInterface(
        interface,
        methods: [
          for (final name
              in interface == _root
                  ? ['Raise']
                  : ['Next', 'Previous', 'Pause', 'PlayPause', 'Stop', 'Play'])
            DBusIntrospectMethod(name),
          if (interface == _player)
            DBusIntrospectMethod(
              'Seek',
              args: [
                DBusIntrospectArgument(
                  DBusSignature('x'),
                  DBusArgumentDirection.in_,
                ),
              ],
            ),
          if (interface == _player)
            DBusIntrospectMethod(
              'SetPosition',
              args: [
                DBusIntrospectArgument(
                  DBusSignature('o'),
                  DBusArgumentDirection.in_,
                ),
                DBusIntrospectArgument(
                  DBusSignature('x'),
                  DBusArgumentDirection.in_,
                ),
              ],
            ),
        ],
        properties: [
          for (final entry in _properties(interface).entries)
            DBusIntrospectProperty(
              entry.key,
              entry.value.signature,
              access:
                  interface == _player &&
                      [
                        'Volume',
                        'Shuffle',
                        'LoopStatus',
                        'Rate',
                      ].contains(entry.key)
                  ? DBusPropertyAccess.readwrite
                  : DBusPropertyAccess.read,
            ),
        ],
      ),
  ];

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = _properties(interface)[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(_properties(interface));
  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface != _player) return DBusMethodErrorResponse.unknownInterface();
    final player = ref.read(playerProvider);
    switch (name) {
      case 'Volume':
        await player.setVolume((value.asDouble() * 100).clamp(0, 100));
      case 'Shuffle':
        ref.read(shuffleProvider.notifier).set(value.asBoolean());
      case 'LoopStatus':
        ref.read(repeatModeProvider.notifier).set(switch (value.asString()) {
          'Track' => PlaybackRepeatMode.one,
          'Playlist' => PlaybackRepeatMode.all,
          _ => PlaybackRepeatMode.off,
        });
      case 'Rate':
        await ref.read(audioEngineProvider).setRate(value.asDouble());
      default:
        return DBusMethodErrorResponse.propertyReadOnly();
    }
    _update();
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != _player && methodCall.interface != _root) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final player = ref.read(playerProvider);
    if (methodCall.name == 'Seek' && methodCall.values.length == 1) {
      final target =
          player.state.position +
          Duration(microseconds: methodCall.values.first.asInt64());
      await player.seek(target < Duration.zero ? Duration.zero : target);
    } else if (methodCall.name == 'SetPosition' &&
        methodCall.values.length == 2) {
      final track = ref.read(currentTrackProvider);
      if (methodCall.values.first.asObjectPath().value ==
          '/org/mpris/MediaPlayer2/track/${track?.id}') {
        await player.seek(
          Duration(
            microseconds: methodCall.values[1].asInt64().clamp(
              0,
              player.state.duration.inMicroseconds,
            ),
          ),
        );
      }
    } else if ([
      'Next',
      'Previous',
      'Pause',
      'PlayPause',
      'Stop',
      'Play',
      'Raise',
    ].contains(methodCall.name)) {
      await _command(methodCall.name);
    } else {
      return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (Platform.isWindows) {
      _channel.setMethodCallHandler(null);
      unawaited(
        _channel.invokeMethod<void>('dispose').catchError((Object _) {}),
      );
    }
    if (_bus != null) unawaited(_bus!.close());
  }
}
