import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/app_log.dart';
import '../core/app_models.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/episode_choice.dart';
import '../quark/quark_login_screen.dart';
import '../quark/quark_playback_service.dart';
import '../rex/rex_interactions.dart';
import '../rex/rex_metadata.dart';
import 'apple_playback.dart';
import 'rex_player_controls.dart';
import 'rex_player_tools.dart';
import 'subtitle_files.dart';
import 'native_player.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({
    super.key,
    required this.detail,
    required this.initialChoice,
    this.updatedDetail,
    this.rexStyle = false,
  });

  final VodDetail detail;
  final EpisodeChoice initialChoice;
  final Future<VodDetail>? updatedDetail;
  final bool rexStyle;

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen>
    with WidgetsBindingObserver {
  late AppServices _services;
  late EpisodeChoice _choice;
  late VodDetail _detail;
  SubtitleFiles? _subtitleFiles;
  Player? _player;
  ApplePlayback? _apple;
  bool _appleComplete = false;
  bool _preferApple = true;
  bool _locked = false, _menuOpen = false;
  RexPlayerPanel? _dock;
  int _dockSeason = 1;
  double _volume = 100, _brightness = .5, _audioDelay = 0;
  double? _aspect;
  bool _boosted = false;
  String? _hud;
  Timer? _hudTimer;
  bool _leftGesture = false;
  double _gestureValue = 0;
  bool _gestureStarted = false;
  final _tools = RexPlayerTools();
  String? _externalSubtitle;
  String? _secondarySubtitle;
  static const _device = MethodChannel('cinema/player-device');
  VideoController? _videoController;
  QuarkPlaybackLease? _lease;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _started = false;
  bool _loading = true;
  bool _disposed = false;
  bool _buffering = true;
  bool _playing = false;
  bool _controlsVisible = true;
  bool _needsAccount = false;
  bool _ended = false;
  bool _mediaReady = false;
  String _stage = '正在准备播放';
  String? _errorTitle;
  String? _errorDetail;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  double? _dragPositionMs;
  double _rate = 1.0;
  BoxFit _fit = BoxFit.contain;
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  Timer? _hideControlsTimer;
  Timer? _bufferTimer;
  Timer? _prepareTimer;
  Timer? _nextTimer;
  int _generation = 0;
  QuarkPlaybackCancellation? _cancellation;
  EpisodeChoice? _nextChoice;
  int _nextCountdown = 0;
  bool _savingProgress = false;
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);

  MediaResource? get _resource => _choice.resource;
  bool get _completed =>
      _apple != null ? _appleComplete : _player?.state.completed == true;
  Duration get _currentPosition =>
      _apple != null ? _position : _player?.state.position ?? _position;
  bool get _hasEngine => _apple != null || _player != null;

  Future<void> _pauseEngine() async {
    if (_apple != null) {
      await _apple!.send('pause');
    } else {
      await _player?.pause();
    }
  }

  Future<void> _playEngine() async {
    if (_apple != null) {
      await _apple!.send('play');
    } else {
      await _player?.play();
    }
  }

  Future<void> _seekEngine(Duration at) async {
    if (_apple != null) {
      await _apple!.send('seek', at.inMilliseconds);
    } else {
      await _player?.seek(at);
    }
  }

  Future<void> _rateEngine(double rate) async {
    if (_apple != null) {
      await _apple!.send('rate', rate);
    } else {
      await _player?.setRate(rate);
    }
  }

  Future<void> _closeApple() async {
    final apple = _apple;
    _apple = null;
    _appleComplete = false;
    await apple?.close();
  }

  void _appleEvent(
    ApplePlayback apple,
    int generation,
    Map<Object?, Object?> event,
  ) {
    if (_disposed ||
        !mounted ||
        !identical(_apple, apple) ||
        generation != _generation) {
      return;
    }
    if (event['failed'] == true) {
      if (_mediaReady) _handlePlaybackError();
      return;
    }
    final wasPlaying = _playing;
    final complete = event['complete'] == true;
    setState(() {
      _playing = event['playing'] == true;
      _buffering = event['buffering'] == true;
      if (_dragPositionMs == null) {
        _position = Duration(milliseconds: event['position'] as int? ?? 0);
      }
      _duration = Duration(milliseconds: event['duration'] as int? ?? 0);
      _buffer = Duration(milliseconds: event['buffer'] as int? ?? 0);
      _tracks = apple.tracks;
      _track = apple.track;
      _appleComplete = complete;
    });
    if (!wasPlaying && _playing) _armHideControls();
    if (complete) unawaited(_handleCompleted());
    if (DateTime.now().difference(_lastProgressSave).inSeconds >= 10) {
      _lastProgressSave = DateTime.now();
      unawaited(_saveProgress());
    }
  }

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
    _choice = widget.initialChoice;
    WidgetsBinding.instance.addObserver(this);
    widget.updatedDetail
        ?.then<void>((updated) {
          if (_disposed ||
              !mounted ||
              updated.item.identityKey != _detail.item.identityKey) {
            return;
          }
          final selected = EpisodeChoice.choiceForResource(
            updated,
            _resource?.id ?? '',
          );
          setState(() {
            _detail = updated;
            if (selected != null) _choice = selected;
          });
          if (_ended &&
              _completed &&
              EpisodeChoice.nextEpisode(updated, _choice) != null) {
            _ended = false;
            unawaited(_handleCompleted());
          }
        })
        .catchError((Object error) {
          AppLog.error('player-detail-update', error);
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
    if (!_started) {
      _started = true;
      _enterPlayerMode();
      WidgetsBinding.instance.addPostFrameCallback((_) => _startPlayback());
    }
  }

  void _enterPlayerMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _leavePlayerMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  void _setStateIfMounted(VoidCallback action) {
    if (!mounted || _disposed) return;
    setState(action);
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    final player = createNativePlayer();
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _player = player;
    _videoController = controller;
    _subscriptions.addAll([
      player.stream.playing.listen((value) {
        _setStateIfMounted(() => _playing = value);
        if (value) {
          _armHideControls();
        }
      }),
      player.stream.position.listen((value) {
        if (!mounted) return;
        if (_dragPositionMs == null) {
          setState(() => _position = value);
        }
        if (DateTime.now().difference(_lastProgressSave).inSeconds >= 10) {
          _lastProgressSave = DateTime.now();
          unawaited(_saveProgress());
        }
      }),
      player.stream.duration.listen((value) {
        _setStateIfMounted(() => _duration = value);
      }),
      player.stream.buffer.listen((value) {
        _setStateIfMounted(() => _buffer = value);
      }),
      player.stream.buffering.listen((value) {
        _setStateIfMounted(() => _buffering = value);
        if (value) {
          _startBufferWatchdog();
        } else {
          _bufferTimer?.cancel();
        }
      }),
      player.stream.completed.listen((value) {
        if (value) unawaited(_handleCompleted());
      }),
      player.stream.error.listen((value) {
        AppLog.error('player', value);
        _handlePlaybackError();
      }),
      player.stream.tracks.listen((value) {
        _setStateIfMounted(() => _tracks = value);
      }),
      player.stream.track.listen((value) {
        _setStateIfMounted(() => _track = value);
      }),
    ]);
  }

  Future<void> _startPlayback({
    Duration? resumeAt,
    bool refreshLease = false,
  }) async {
    if (_disposed || !mounted) return;
    final resource = _resource;
    if (resource == null) {
      _showError('线路缺少资源描述', '接口没有返回这条线路的文件信息。请切换线路，或在后台补齐资源描述后再试。');
      return;
    }
    _cancellation?.cancel();
    final cancellation = QuarkPlaybackCancellation();
    _cancellation = cancellation;
    final generation = ++_generation;
    _cancelOverlays();
    bool hasAccount;
    try {
      hasAccount = await _services.quark.hasAccount;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _showError('无法读取登录状态', '系统安全存储暂时不可用，请退出播放后重新连接夸克账号。');
      return;
    }
    if (_disposed || generation != _generation) return;
    if (!hasAccount) {
      _setStateIfMounted(() {
        _loading = false;
        _needsAccount = true;
        _errorTitle = '连接你的夸克账号';
        _errorDetail = '选片后需要在设备内完成转存并获取播放地址。账号会话只保存在本机安全存储，不使用开发者账号代播。';
      });
      return;
    }

    _mediaReady = false;
    await _closeApple();
    if (_player != null) {
      await _player!.stop();
    }
    if (_disposed || generation != _generation) return;
    if (!refreshLease) await _releaseLease();
    if (_disposed || generation != _generation) return;
    _setStateIfMounted(() {
      _loading = true;
      _buffering = true;
      _ended = false;
      _errorTitle = null;
      _errorDetail = null;
      _needsAccount = false;
      _stage = '正在准备播放';
      _controlsVisible = true;
    });
    _prepareTimer?.cancel();
    _prepareTimer = Timer(const Duration(seconds: 75), () {
      if (!mounted || !_loading || generation != _generation) return;
      cancellation.cancel();
      _generation++;
      _showError('准备播放超时', '在规定时间内没有完成账号校验、文件定位和地址获取。本次等待已结束，请检查网络后重试。');
    });

    try {
      QuarkPlaybackLease? lease = refreshLease ? _lease : null;
      if (lease != null) {
        _setStateIfMounted(() => _stage = '正在刷新播放地址');
        try {
          cancellation.throwIfCancelled();
          await lease.refresh();
        } on QuarkException catch (error) {
          if (error.kind != QuarkFailureKind.fileNotFound) rethrow;
          await _releaseLease();
          lease = null;
        }
      }
      lease ??= await _services.quark.acquire(
        resource,
        cancellation: cancellation,
        onStage: (stage) {
          if (mounted && generation == _generation) {
            setState(() => _stage = stage);
          }
        },
      );
      if (_disposed || generation != _generation) {
        if (!identical(_lease, lease)) await lease.release();
        return;
      }
      _lease = lease;
      final record = _services.store.recordForItem(_detail.item);
      final storedMatches =
          record != null &&
          !record.completed &&
          (!_detail.isSeries ||
              ((record.season ?? 1) == (resource.season ?? 1) &&
                  record.episode == resource.episode));
      final resume = EpisodeChoice.resumeWithinResource(
        resumeAt ??
            (storedMatches
                ? Duration(milliseconds: record.safePositionMs)
                : Duration.zero),
        resource,
      );
      _stage = '正在起播';
      _setStateIfMounted(() {});
      var appleReady = false;
      if (widget.rexStyle &&
          _preferApple &&
          ApplePlayback.canOpen(resource.fileName)) {
        late final ApplePlayback apple;
        apple = ApplePlayback((event) => _appleEvent(apple, generation, event));
        _setStateIfMounted(() => _apple = apple);
        try {
          await Future.any<void>([
            apple.open(
              lease.mediaUri,
              lease.headers,
              resource.fileName,
              resume,
            ),
            cancellation.whenCancelled.then(
              (_) => cancellation.throwIfCancelled(),
            ),
          ]);
          if (_disposed || generation != _generation) return;
          await apple.send('rate', _rate);
          await apple.send('volume', _volume);
          await apple.send('fit', _fit.name);
          appleReady = true;
        } on Object catch (error) {
          if (_disposed || generation != _generation) return;
          AppLog.error('apple-playback-fallback', error.runtimeType);
          await _closeApple();
          _setStateIfMounted(() {});
        }
      }
      if (!appleReady) {
        await _ensurePlayer();
        if (_disposed || generation != _generation) return;
        await _player!.open(
          Media(
            lease.mediaUri.toString(),
            httpHeaders: lease.headers,
            start: resume,
          ),
          play: true,
        );
        if (_disposed || generation != _generation) {
          if (!identical(_lease, lease)) await lease.release();
          return;
        }
        await Future.any<void>([
          _videoController!.waitUntilFirstFrameRendered,
          cancellation.whenCancelled.then(
            (_) => cancellation.throwIfCancelled(),
          ),
        ]).timeout(const Duration(seconds: 40));
        if (widget.rexStyle && !_disposed && generation == _generation) {
          await _player!.setRate(_rate);
          await _player!.setVolume(_volume);
        }
      }
      if (_disposed || generation != _generation) {
        if (!identical(_lease, lease)) await lease.release();
        return;
      }
      _prepareTimer?.cancel();
      _mediaReady = true;
      _setStateIfMounted(() {
        _loading = false;
        _buffering = appleReady ? _buffering : _player!.state.buffering;
        _ended = false;
        _errorTitle = null;
        _controlsVisible = true;
      });
      _startBufferWatchdog();
      _armHideControls();
    } on TimeoutException {
      if (_disposed || generation != _generation) return;
      _showError('起播超时', '播放地址已取得，但仍未显示画面。请检查网络或切换线路后重试。');
    } on QuarkException catch (error) {
      AppLog.error('playback-acquire', error);
      if (_disposed || generation != _generation) return;
      _prepareTimer?.cancel();
      _setStateIfMounted(() {
        _loading = false;
        _buffering = false;
        _needsAccount =
            error.kind == QuarkFailureKind.authRequired ||
            error.kind == QuarkFailureKind.authExpired;
        _errorTitle = error.kind == QuarkFailureKind.authRequired
            ? '连接你的夸克账号'
            : '暂时无法起播';
        _errorDetail = error.userMessage;
      });
    } catch (error) {
      AppLog.error('playback-acquire', error);
      if (_disposed || generation != _generation) return;
      _prepareTimer?.cancel();
      _showError('暂时无法起播', '播放准备过程失败。请稍后重试；反复失败时请切换线路。');
    }
  }

  void _showError(String title, String detail) {
    _prepareTimer?.cancel();
    _bufferTimer?.cancel();
    _nextTimer?.cancel();
    unawaited(_pauseEngine());
    _setStateIfMounted(() {
      _loading = false;
      _buffering = false;
      _playing = false;
      _ended = false;
      _errorTitle = title;
      _errorDetail = detail;
      _controlsVisible = true;
    });
  }

  void _handlePlaybackError() {
    if (_disposed) return;
    _bufferTimer?.cancel();
    _showError('播放已中断', '播放地址可能已失效，或当前网络中断。点击“重新获取地址”会重新使用你的账号获取新地址，并从当前进度继续。');
  }

  void _startBufferWatchdog() {
    _bufferTimer?.cancel();
    if (!_buffering) return;
    _bufferTimer = Timer(const Duration(seconds: 40), () {
      if (!mounted ||
          _loading ||
          !_buffering ||
          !_playing ||
          _errorTitle != null) {
        return;
      }
      _showError('加载超时', '连续缓冲超过 40 秒。本次等待已停止，请检查网络或切换线路；不会无限加载。');
      unawaited(_pauseEngine());
    });
  }

  Future<void> _cancelLoading() async {
    _cancellation?.cancel();
    _generation++;
    _prepareTimer?.cancel();
    _bufferTimer?.cancel();
    final lease = _lease;
    _lease = null;
    final player = _player;
    _setStateIfMounted(() {
      _loading = false;
      _buffering = false;
      _errorTitle = '已取消加载';
      _errorDetail = '本次播放准备已取消。如果资源已经转存，会在后台清理。';
    });
    try {
      await _closeApple();
      await player?.stop();
    } finally {
      try {
        await lease?.release();
      } catch (error) {
        AppLog.error('playback-release', error);
      }
    }
  }

  Future<void> _releaseLease() async {
    final lease = _lease;
    _lease = null;
    if (lease == null) return;
    try {
      await lease.release();
    } catch (error) {
      AppLog.error('playback-release', error);
    }
  }

  Future<void> _connectAccount() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuarkLoginScreen(playbackService: _services.quark),
      ),
    );
    if (changed == true && mounted) {
      await _startPlayback();
    }
  }

  Future<void> _retryPlayback() async {
    final position = _currentPosition;
    await _saveProgress();
    if (_disposed) return;
    await _startPlayback(resumeAt: position, refreshLease: _lease != null);
  }

  Future<void> _saveProgress({bool completed = false}) async {
    final resource = _resource;
    if (!_mediaReady ||
        !_hasEngine ||
        resource == null ||
        resource.id.isEmpty ||
        _savingProgress) {
      return;
    }
    final duration = _duration.inMilliseconds > 0
        ? _duration
        : _player?.state.duration ?? Duration.zero;
    final position = _currentPosition;
    if (duration.inMilliseconds <= 0 && position.inMilliseconds <= 0) return;
    _savingProgress = true;
    try {
      await _services.store.saveProgress(
        item: _detail.item,
        resource: resource,
        position: position,
        duration: duration,
        lineGroup: _choice.line.group,
        completed: completed || _completed,
      );
    } finally {
      _savingProgress = false;
    }
  }

  Future<void> _handleCompleted() async {
    if (_disposed ||
        !_mediaReady ||
        _loading ||
        _ended ||
        _nextChoice != null) {
      return;
    }
    await _saveProgress(completed: true);
    if (_disposed) return;
    final next = EpisodeChoice.nextEpisode(_detail, _choice);
    if (next == null) {
      _hideControlsTimer?.cancel();
      _setStateIfMounted(() {
        _ended = true;
        _controlsVisible = false;
        _playing = false;
      });
      return;
    }
    _showNextPrompt(next);
  }

  Future<void> _replay() async {
    if (!_hasEngine) return;
    _cancelOverlays();
    await _seekEngine(Duration.zero);
    await _playEngine();
    _setStateIfMounted(() {
      _ended = false;
      _controlsVisible = true;
    });
    _showControlsTemporarily();
  }

  void _showNextPrompt(EpisodeChoice next) {
    _nextTimer?.cancel();
    _hideControlsTimer?.cancel();
    _setStateIfMounted(() {
      _nextChoice = next;
      _nextCountdown = 8;
      _controlsVisible = false;
      _playing = false;
    });
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_nextCountdown <= 1) {
        timer.cancel();
        _playNext();
      } else {
        setState(() => _nextCountdown--);
      }
    });
  }

  void _cancelNextPrompt() {
    _nextTimer?.cancel();
    _setStateIfMounted(() {
      _nextChoice = null;
      _nextCountdown = 0;
      _controlsVisible = true;
    });
  }

  Future<void> _playNext() async {
    final next = _nextChoice;
    if (next == null) return;
    _nextTimer?.cancel();
    _setStateIfMounted(() {
      _nextChoice = null;
      _nextCountdown = 0;
    });
    await _switchChoice(next);
  }

  Future<void> _switchChoice(EpisodeChoice choice) async {
    final sameEpisode = EpisodeChoice.isSameEpisode(_choice, choice);
    final position = sameEpisode ? _currentPosition : Duration.zero;
    await _saveProgress(completed: _completed);
    if (_disposed) return;
    _mediaReady = false;
    _setStateIfMounted(() {
      _choice = choice;
      _dock = null;
      _externalSubtitle = null;
      _secondarySubtitle = null;
      if (!sameEpisode) {
        _tools.comments = [];
        _tools.commentsEnabled = false;
        _tools.marks.clear();
        _tools.segmentStart = null;
      }
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffer = Duration.zero;
      _errorTitle = null;
      _errorDetail = null;
    });
    await _startPlayback(resumeAt: position);
  }

  Future<void> _seekRelative(int seconds) async {
    if (!_hasEngine) return;
    final targetMs = (_position.inMilliseconds + seconds * 1000).clamp(
      0,
      _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1 << 62,
    );
    await _seekEngine(Duration(milliseconds: targetMs));
    _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    _setStateIfMounted(() => _controlsVisible = true);
    _armHideControls();
  }

  void _armHideControls() {
    _hideControlsTimer?.cancel();
    if (_errorTitle != null ||
        _loading ||
        _nextChoice != null ||
        _menuOpen ||
        _dock != null ||
        _locked ||
        _boosted) {
      return;
    }
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playing) setState(() => _controlsVisible = false);
    });
  }

  void _cancelOverlays() {
    _hideControlsTimer?.cancel();
    _bufferTimer?.cancel();
    _prepareTimer?.cancel();
    _nextTimer?.cancel();
    _nextChoice = null;
    _nextCountdown = 0;
  }

  Future<void> _togglePlay() async {
    if (!_hasEngine) return;
    if (_completed) {
      await _replay();
      return;
    }
    if (_playing) {
      await _pauseEngine();
    } else {
      await _playEngine();
    }
    _showControlsTemporarily();
  }

  Future<void> _selectRate(double value) async {
    await _rateEngine(value);
    _setStateIfMounted(() => _rate = value);
    _showControlsTemporarily();
  }

  Future<void> _openRatePanel() async {
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = false);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => _Panel(
        title: '播放速度',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final value in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              _PillButton(
                label: value == 1.0 ? '1.0× 原速' : '$value×',
                selected: _rate == value,
                onTap: () {
                  Navigator.of(context).pop();
                  _selectRate(value);
                },
              ),
          ],
        ),
      ),
    );
    if (mounted) _showControlsTemporarily();
  }

  Future<void> _openFitPanel() async {
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = false);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => _Panel(
        title: '画面比例',
        child: Column(
          children: [
            for (final option in const [
              (BoxFit.contain, '适应画面', '保留原画完整画面，不做裁切'),
              (BoxFit.cover, '铺满屏幕', '可能裁切边缘，不改变画面几何比例'),
              (BoxFit.fill, '拉伸填满', '铺满屏幕，可能改变画面比例'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(option.$2),
                subtitle: Text(option.$3),
                trailing: _fit == option.$1
                    ? const Icon(Icons.check_rounded, color: CinemaColors.red)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => _fit = option.$1);
                  _showControlsTemporarily();
                },
              ),
          ],
        ),
      ),
    );
    if (mounted) _showControlsTemporarily();
  }

  Future<void> _openTrackPanel() async {
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _Panel(
              title: '音轨与字幕',
              child: DefaultTextStyle(
                style: const TextStyle(color: CinemaColors.text),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '音轨',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    if (_tracks.audio
                        .where((t) => t.id != 'auto' && t.id != 'no')
                        .isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          '没有可切换的内嵌音轨',
                          style: TextStyle(color: CinemaColors.faint),
                        ),
                      ),
                    for (final audio in _tracks.audio.where(
                      (t) => t.id != 'auto' && t.id != 'no',
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _trackLabel(audio.title, audio.language, audio.codec),
                        ),
                        subtitle: Text(_audioDetail(audio)),
                        trailing: _track.audio.id == audio.id
                            ? const Icon(
                                Icons.check_rounded,
                                color: CinemaColors.red,
                              )
                            : null,
                        onTap: () async {
                          await _player?.setAudioTrack(audio);
                          setSheetState(() {});
                        },
                      ),
                    const Divider(height: 24),
                    const Text(
                      '字幕',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('关闭字幕'),
                      trailing: _track.subtitle.id == 'no'
                          ? const Icon(
                              Icons.check_rounded,
                              color: CinemaColors.red,
                            )
                          : null,
                      onTap: () async {
                        await _player?.setSubtitleTrack(SubtitleTrack.no());
                        setSheetState(() {});
                      },
                    ),
                    if (_tracks.subtitle
                        .where((t) => t.id != 'auto' && t.id != 'no')
                        .isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          '没有检测到内嵌字幕',
                          style: TextStyle(color: CinemaColors.faint),
                        ),
                      ),
                    for (final subtitle in _tracks.subtitle.where(
                      (t) => t.id != 'auto' && t.id != 'no',
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _trackLabel(
                            subtitle.title,
                            subtitle.language,
                            subtitle.codec,
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (subtitle.codec != null) subtitle.codec!,
                            if (subtitle.image == true) '图形字幕',
                          ].join(' · '),
                        ),
                        trailing: _track.subtitle.id == subtitle.id
                            ? const Icon(
                                Icons.check_rounded,
                                color: CinemaColors.red,
                              )
                            : null,
                        onTap: () async {
                          await _player?.setSubtitleTrack(subtitle);
                          setSheetState(() {});
                        },
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('导入外挂字幕'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _importSubtitle();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) _showControlsTemporarily();
  }

  Future<void> _importSubtitle() async {
    final generation = _generation;
    try {
      const type = XTypeGroup(
        label: '字幕',
        extensions: SubtitleFiles.extensions,
        uniformTypeIdentifiers: ['public.data'],
      );
      final file = await openFile(acceptedTypeGroups: [type]);
      if (file == null || _disposed || generation != _generation) return;
      if (await file.length() > SubtitleFiles.maxBytes) {
        throw const FormatException('字幕文件超过 16 MB。');
      }
      final bytes = await file.readAsBytes();
      if (_disposed || generation != _generation) return;
      final subtitles = _subtitleFiles ??= SubtitleFiles(
        Directory('${_services.quark.supportDirectory.path}/subtitles'),
      );
      final imported = await subtitles.importFile(file.name, bytes);
      if (_disposed) {
        await subtitles.dispose();
        return;
      }
      if (generation != _generation) return;
      await _player?.setSubtitleTrack(
        SubtitleTrack.uri(imported.path, title: file.name),
      );
      if (widget.rexStyle && mounted) {
        setState(() => _externalSubtitle = file.name);
      }
      _showControlsTemporarily();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException ? error.message : '字幕导入失败，请检查文件后重试。',
          ),
        ),
      );
    }
  }

  String _trackLabel(String? title, String? language, String? codec) {
    final values = [
      title,
      language,
      codec,
    ].whereType<String>().where((v) => v.trim().isNotEmpty);
    return values.isEmpty ? '未命名轨道' : values.join(' · ');
  }

  String _audioDetail(AudioTrack track) {
    final parts = <String>[
      if (track.channels != null) track.channels!,
      if (track.samplerate != null) '${track.samplerate} Hz',
    ];
    return parts.join(' · ');
  }

  Future<void> _openEpisodesPanel() async {
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = false);
    final episodes = EpisodeChoice.forLine(_choice.line);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _Panel(
        title: '选集 · ${_choice.line.group}',
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: ListView.separated(
            itemCount: episodes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final choice = episodes[index];
              final selected = choice.resource?.id == _choice.resource?.id;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selected
                      ? Icons.play_arrow_rounded
                      : Icons.play_arrow_outlined,
                  color: selected ? CinemaColors.red : CinemaColors.muted,
                ),
                title: Text(choice.episodeLabel),
                subtitle: Text(
                  choice.resource?.technicalSummary ?? '画质资料待补齐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: selected
                    ? const Text(
                        '当前播放',
                        style: TextStyle(color: CinemaColors.red, fontSize: 12),
                      )
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (!selected) _switchChoice(choice);
                },
              );
            },
          ),
        ),
      ),
    );
    if (mounted) _showControlsTemporarily();
  }

  Future<void> _openLinePanel() async {
    if (widget.rexStyle && !_loading && _errorTitle == null && !_ended) {
      _showDock(RexPlayerPanel.resources);
      return;
    }
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = false);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => _Panel(
        title: '切换线路',
        child: Column(
          children: [
            for (final line in _detail.playableLines)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(line.group),
                subtitle: Text('${line.entries.length} 个版本'),
                trailing: line.group == _choice.line.group
                    ? const Icon(Icons.check_rounded, color: CinemaColors.red)
                    : null,
                onTap: () {
                  final target = EpisodeChoice.sameEpisodeInLine(
                    _detail,
                    line,
                    _choice,
                  );
                  Navigator.of(context).pop();
                  if (target == null) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('这条线路没有当前集，请选择其他线路。')),
                    );
                    return;
                  }
                  if (target.resource?.id != _resource?.id) {
                    _switchChoice(target);
                  }
                },
              ),
          ],
        ),
      ),
    );
    if (mounted) _showControlsTemporarily();
  }

  void _showDock(RexPlayerPanel panel) {
    _hideControlsTimer?.cancel();
    setState(() {
      _dockSeason = _choice.season ?? 1;
      _controlsVisible = true;
      _dock = _dock == panel ? null : panel;
    });
    if (_dock == null) _armHideControls();
  }

  void _closeDock() {
    setState(() => _dock = null);
    _armHideControls();
  }

  Future<void> _openRexMenu(String name, BuildContext anchor) async {
    if (name == '选集' || name == '线路') {
      _showDock(
        name == '选集' ? RexPlayerPanel.episodes : RexPlayerPanel.resources,
      );
      return;
    }
    if (name == '画中画') {
      if (_apple == null) {
        _showHud('当前线路使用兼容内核，无法开启系统画中画');
      } else {
        try {
          await _apple!.send('pip');
        } on PlatformException {
          _showHud('当前设备或线路无法开启画中画');
        }
      }
      return;
    }
    final entries = <RexMenuEntry<String>>[];
    switch (name) {
      case '倍速':
        for (final rate in [2.0, 1.75, 1.5, 1.25, 1.0, .75, .5]) {
          entries.add(
            RexMenuEntry(
              'rate:$rate',
              '${rate.toString().replaceFirst(RegExp(r'\.0$'), '')}×',
              selected: rate == _rate,
            ),
          );
        }
      case '填充模式':
        for (final (fit, label) in [
          (BoxFit.contain, '适应屏幕'),
          (BoxFit.cover, '填满屏幕'),
          (BoxFit.fill, '拉伸填满'),
        ]) {
          entries.add(
            RexMenuEntry(
              'fit:${fit.name}',
              label,
              selected: _fit == fit && _aspect == null,
            ),
          );
        }
        entries.addAll([
          RexMenuEntry(
            'aspect:1.7777777778',
            '画面比例 · 16:9',
            selected: _aspect == 1.7777777778,
          ),
          RexMenuEntry(
            'aspect:1.3333333333',
            '画面比例 · 4:3',
            selected: _aspect == 1.3333333333,
          ),
        ]);
        if (_apple != null) entries.add(const RexMenuEntry('compat', '使用兼容内核'));
        if (_apple == null &&
            ApplePlayback.canOpen(_resource?.fileName ?? '')) {
          entries.add(const RexMenuEntry('apple', '尝试 Apple 原生内核'));
        }
      case '音轨':
        for (final audio in _tracks.audio.where(
          (v) => v.id != 'auto' && v.id != 'no',
        )) {
          entries.add(
            RexMenuEntry(
              'audio:${audio.id}',
              _trackLabel(audio.title, audio.language, audio.codec),
              selected: audio.id == _track.audio.id,
            ),
          );
        }
        if (_apple == null) {
          entries.add(
            RexMenuEntry(
              'audio-delay',
              '音频延迟 · ${_audioDelay.toStringAsFixed(1)}s',
            ),
          );
        }
      case '字幕':
        entries.add(
          RexMenuEntry(
            'subtitle:no',
            '关闭字幕',
            selected: _track.subtitle.id == 'no',
          ),
        );
        for (final subtitle in _tracks.subtitle.where(
          (v) => v.id != 'auto' && v.id != 'no',
        )) {
          entries.add(
            RexMenuEntry(
              'subtitle:${subtitle.id}',
              _trackLabel(subtitle.title, subtitle.language, subtitle.codec),
              selected: subtitle.id == _track.subtitle.id,
            ),
          );
        }
        if (_apple == null) {
          entries.addAll([
            RexMenuEntry(
              'secondary',
              '副字幕${_secondarySubtitle == null ? '' : ' · 已开启'}',
              icon: CupertinoIcons.text_bubble,
            ),
            RexMenuEntry(
              'import-subtitle',
              _externalSubtitle == null ? '导入字幕' : '外挂字幕 · $_externalSubtitle',
              icon: CupertinoIcons.folder,
            ),
          ]);
        } else {
          entries.add(const RexMenuEntry('compat', '外挂字幕 · 切换兼容内核'));
        }
      case '片段':
        final native = _player?.platform;
        if (_apple == null && native is NativePlayer) {
          try {
            final count =
                int.tryParse(await native.getProperty('chapter-list/count')) ??
                0;
            for (var i = 0; i < count.clamp(0, 100); i++) {
              final seconds = double.tryParse(
                await native.getProperty('chapter-list/$i/time'),
              );
              if (seconds == null || !seconds.isFinite || seconds < 0) continue;
              final at = (seconds * 1000).round();
              final label = await native.getProperty('chapter-list/$i/title');
              entries.add(
                RexMenuEntry(
                  'jump:$at',
                  '${playbackClock(Duration(milliseconds: at))} · ${label.isEmpty ? '片段 ${i + 1}' : label}',
                ),
              );
            }
          } on Object {
            /* This source has no readable chapter list. */
          }
        }
        for (final mark in _tools.marks.entries) {
          entries.add(
            RexMenuEntry(
              'jump:${mark.key}',
              '${playbackClock(Duration(milliseconds: mark.key))} · ${mark.value}',
            ),
          );
        }
        entries.addAll([
          const RexMenuEntry(
            'intro-mark',
            '标记片头',
            icon: CupertinoIcons.backward_end,
          ),
          RexMenuEntry(
            'segment',
            _tools.segmentStart == null ? '创建片段' : '保存片段结束时间',
            icon: CupertinoIcons.recordingtape,
          ),
        ]);
      case '弹幕':
        entries.addAll([
          const RexMenuEntry(
            'import-comments',
            '导入弹幕',
            icon: CupertinoIcons.folder,
          ),
          const RexMenuEntry(
            'comments-style',
            '显示设置',
            icon: CupertinoIcons.gear,
          ),
          const RexMenuEntry(
            'keywords',
            '过滤关键词',
            icon: CupertinoIcons.line_horizontal_3_decrease,
          ),
          RexMenuEntry(
            'toggle-comments',
            _tools.commentsEnabled ? '关闭弹幕' : '开启弹幕',
          ),
        ]);
      case '投屏':
        _showHud('AirPlay 需要支持的原生播放线路与接收设备');
        return;
    }
    if (!mounted || !anchor.mounted) return;
    if (entries.isEmpty) {
      _showHud('当前片源没有可切换的$name');
      return;
    }
    _hideControlsTimer?.cancel();
    _menuOpen = true;
    final value = await showRexMenu(context, anchor: anchor, entries: entries);
    if (!mounted) return;
    _menuOpen = false;
    if (value != null) await _applyRexMenu(value);
    if (mounted) _showControlsTemporarily();
  }

  Future<void> _applyRexMenu(String value) async {
    final parts = value.split(':');
    final parameter = parts.length > 1 ? parts.sublist(1).join(':') : '';
    switch (parts.first) {
      case 'rate':
        await _selectRate(double.parse(parameter));
      case 'fit':
        setState(() {
          _fit = BoxFit.values.byName(parameter);
          _aspect = null;
        });
        await _apple?.send('fit', parameter);
      case 'aspect':
        setState(() => _aspect = double.parse(parameter));
      case 'audio':
        if (_apple != null) {
          await _apple!.send('audio', parameter);
        } else {
          final audio = _tracks.audio
              .where((v) => v.id == parameter)
              .firstOrNull;
          if (audio != null) await _player?.setAudioTrack(audio);
        }
      case 'subtitle':
        if (_apple != null) {
          await _apple!.send('subtitle', parameter);
        } else {
          final sub = _tracks.subtitle
              .where((v) => v.id == parameter)
              .firstOrNull;
          if (parameter == 'no' || sub != null) {
            await _player?.setSubtitleTrack(sub ?? SubtitleTrack.no());
          }
        }
      case 'audio-delay':
        await _showAdjustment(audio: true);
      case 'secondary':
        await _chooseSecondarySubtitle();
      case 'import-subtitle':
        await _importSubtitle();
      case 'compat':
      case 'apple':
        _preferApple = value == 'apple';
        await _retryPlayback();
      case 'jump':
        await _seekEngine(Duration(milliseconds: int.parse(parameter)));
      case 'intro-mark':
        _tools.marks[_currentPosition.inMilliseconds] = '片头结束';
        _showHud('已标记片头结束');
      case 'segment':
        final now = _currentPosition.inMilliseconds;
        final start = _tools.segmentStart;
        if (start == null) {
          _tools.segmentStart = now;
          _showHud('已记录片段起点');
        } else if (now > start) {
          _tools.marks[start] =
              '片段 · ${playbackClock(Duration(milliseconds: now - start))}';
          _tools.segmentStart = null;
          _showHud('已保存片段');
        } else {
          _showHud('请在起点之后选择结束时间');
        }
      case 'toggle-comments':
        if (_tools.comments.isEmpty) {
          _showHud('请先导入弹幕文件');
        } else {
          setState(() => _tools.commentsEnabled = !_tools.commentsEnabled);
        }
      case 'import-comments':
        await _importComments();
      case 'comments-style':
        await _showAdjustment(audio: false);
      case 'keywords':
        await _editKeywords();
    }
  }

  Future<void> _chooseSecondarySubtitle() async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('副字幕'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'no'),
            child: const Text('关闭副字幕'),
          ),
          for (final track in _tracks.subtitle.where(
            (v) => int.tryParse(v.id) != null && v.id != _track.subtitle.id,
          ))
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, track.id),
              child: Text(
                _trackLabel(track.title, track.language, track.codec),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final native = _player?.platform;
    if (native is NativePlayer) {
      await native.setProperty('secondary-sid', selected);
      if (mounted) {
        setState(() => _secondarySubtitle = selected == 'no' ? null : selected);
      }
    }
  }

  Future<void> _importComments() async {
    final generation = _generation;
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '弹幕',
            extensions: ['xml', 'json'],
            uniformTypeIdentifiers: ['public.xml', 'public.json'],
          ),
        ],
      );
      if (file == null || !mounted || generation != _generation) return;
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('弹幕文件超过 4 MB');
      }
      final raw = await file.readAsString();
      if (!mounted || generation != _generation) return;
      _tools.loadComments(raw);
      setState(() {});
      _showHud('已导入 ${_tools.comments.length} 条弹幕');
    } on Object {
      if (mounted) _showHud('无法导入弹幕，请检查 XML 或 JSON 格式');
    }
  }

  Future<void> _editKeywords() async {
    var value = _tools.keywords;
    final selected = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('过滤关键词'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextFormFieldRow(
            initialValue: value,
            padding: EdgeInsets.zero,
            placeholder: '用逗号分隔关键词',
            onChanged: (text) => value = text,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (mounted && selected != null) setState(() => _tools.keywords = selected);
  }

  Future<void> _showAdjustment({required bool audio}) async {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: '关闭设置',
      barrierDismissible: true,
      barrierColor: const Color(0x22000000),
      pageBuilder: (context, _, _) => SafeArea(
        child: Align(
          alignment: Alignment.centerRight,
          child: Material(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xEF3C373E),
            child: SizedBox(
              width: 315,
              child: StatefulBuilder(
                builder: (context, refresh) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(audio ? '音频延迟' : '弹幕显示设置'),
                      trailing: IconButton(
                        icon: const Icon(CupertinoIcons.xmark),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    ListTile(
                      title: Text(
                        '${audio ? '音频延迟' : '延迟显示'} · ${(audio ? _audioDelay : _tools.delay).toStringAsFixed(1)}s',
                      ),
                      subtitle: Slider(
                        min: -5,
                        max: 5,
                        divisions: 100,
                        value: audio ? _audioDelay : _tools.delay,
                        onChanged: (v) {
                          refresh(() {
                            if (audio) {
                              _audioDelay = v;
                            } else {
                              _tools.delay = v;
                            }
                          });
                          if (mounted) setState(() {});
                        },
                        onChangeEnd: (v) {
                          final native = _player?.platform;
                          if (audio && native is NativePlayer) {
                            unawaited(native.setProperty('audio-delay', '$v'));
                          }
                        },
                      ),
                    ),
                    if (!audio)
                      ListTile(
                        title: const Text('透明度'),
                        subtitle: Slider(
                          min: .1,
                          max: 1,
                          value: _tools.opacity,
                          onChanged: (v) {
                            refresh(() => _tools.opacity = v);
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showHud(String text) {
    if (!mounted || _disposed) return;
    _hudTimer?.cancel();
    setState(() => _hud = text);
    _hudTimer = Timer(
      const Duration(milliseconds: 1500),
      () => _setStateIfMounted(() => _hud = null),
    );
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      _dock = null;
      _controlsVisible = true;
    });
    if (_locked) {
      _hideControlsTimer?.cancel();
    } else {
      _armHideControls();
    }
  }

  Future<void> _adjustVertical(double delta) async {
    if (_locked || !_gestureStarted) return;
    final value = (_gestureValue - delta / 250).clamp(0.0, 1.0);
    _gestureValue = value;
    if (_leftGesture && defaultTargetPlatform == TargetPlatform.iOS) {
      _brightness = value;
      try {
        await _device.invokeMethod<double>('brightness', value);
      } on PlatformException {
        return;
      }
      _showHud('亮度 ${(value * 100).round()}%');
    } else {
      _volume = value * 100;
      if (_apple != null) {
        await _apple!.send('volume', _volume);
      } else {
        await _player?.setVolume(_volume);
      }
      _showHud('音量 ${_volume.round()}%');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _nextTimer?.cancel();
      unawaited(_saveProgress());
      if (state == AppLifecycleState.paused && _apple?.pip == false) {
        unawaited(_pauseEngine());
      }
    } else if (state == AppLifecycleState.resumed && _nextChoice != null) {
      _showNextPrompt(_nextChoice!);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _cancelOverlays();
    _hudTimer?.cancel();
    unawaited(_saveProgress());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    final lease = _lease;
    _lease = null;
    final player = _player;
    unawaited(() async {
      try {
        await _closeApple();
        await player?.dispose();
      } finally {
        await _subtitleFiles?.dispose();
        try {
          await lease?.release();
        } catch (error) {
          AppLog.error('playback-release', error);
        }
      }
    }());
    _leavePlayerMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final controller = _videoController;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 650;
    final apple = _apple;
    final position = _dragPositionMs == null
        ? _position
        : Duration(milliseconds: _dragPositionMs!.round());
    final next = EpisodeChoice.nextEpisode(_detail, _choice);
    final episodeInfo = _detail.item.episodeInfo(
      _choice.season ?? 1,
      _choice.episode ?? 1,
    );
    final episodeName = episodeInfo?['name']?.toString();
    final video =
        apple?.view ??
        (player != null && controller != null
            ? Video(
                controller: controller,
                controls: NoVideoControls,
                fit: _fit,
                wakelock: true,
                pauseUponEnteringBackgroundMode: true,
                resumeUponEnteringForegroundMode: false,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: TextStyle(
                    fontSize: compact ? 22 : 28,
                    height: 1.35,
                    color: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: .66),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    widget.rexStyle ? 35 : 104,
                  ),
                ),
              )
            : const SizedBox.shrink());
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.space &&
                node.hasPrimaryFocus) {
              unawaited(_togglePlay());
              return KeyEventResult.handled;
            }
            if ((event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter) &&
                node.hasPrimaryFocus) {
              _showControlsTemporarily();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) FocusScope.of(context).nextFocus();
              });
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                node.hasPrimaryFocus) {
              unawaited(_seekRelative(-10));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                node.hasPrimaryFocus) {
              unawaited(_seekRelative(10));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: _hasEngine
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_nextChoice != null) return;
                          if (_locked) {
                            setState(
                              () => _controlsVisible = !_controlsVisible,
                            );
                            return;
                          }
                          if (_dock != null) {
                            _closeDock();
                            return;
                          }
                          if (_controlsVisible) {
                            setState(() => _controlsVisible = false);
                          } else {
                            _showControlsTemporarily();
                          }
                        },
                        onDoubleTapDown: (details) =>
                            _doubleTapX = details.localPosition.dx,
                        onDoubleTap: () {
                          if (_locked) return;
                          if (widget.rexStyle &&
                              _doubleTapX > width * .33 &&
                              _doubleTapX < width * .67) {
                            unawaited(_togglePlay());
                          } else {
                            final seconds = widget.rexStyle ? 15 : 10;
                            unawaited(
                              _seekRelative(
                                _doubleTapX < width / 2 ? -seconds : seconds,
                              ),
                            );
                          }
                        },
                        onLongPressStart: (_) async {
                          if (_locked || !_mediaReady) return;
                          _hideControlsTimer?.cancel();
                          _boosted = true;
                          await _rateEngine(2);
                          if (widget.rexStyle) _showHud('2× 快进');
                          _setStateIfMounted(() => _controlsVisible = true);
                        },
                        onLongPressEnd: (_) => _endBoost(),
                        onLongPressCancel: _endBoost,
                        onVerticalDragStart: widget.rexStyle
                            ? (details) {
                                _leftGesture =
                                    details.localPosition.dx < width / 2;
                                _gestureValue =
                                    _leftGesture &&
                                        defaultTargetPlatform ==
                                            TargetPlatform.iOS
                                    ? _brightness
                                    : _volume / 100;
                                _gestureStarted = true;
                              }
                            : null,
                        onVerticalDragUpdate: widget.rexStyle
                            ? (details) =>
                                  unawaited(_adjustVertical(details.delta.dy))
                            : null,
                        onVerticalDragEnd: (_) => _gestureStarted = false,
                        onVerticalDragCancel: () => _gestureStarted = false,
                        child: _aspect == null
                            ? video
                            : Center(
                                child: AspectRatio(
                                  aspectRatio: _aspect!,
                                  child: video,
                                ),
                              ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (_loading) _buildLoading(compact),
              if (widget.rexStyle &&
                  _tools.commentsEnabled &&
                  !_loading &&
                  _errorTitle == null)
                RexComments(tools: _tools, position: position),
              if (_errorTitle != null) _buildError(compact),
              if (!_loading && _errorTitle == null && _buffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (!_loading && _errorTitle == null && widget.rexStyle)
                RexPlayerControls(
                  visible: _controlsVisible,
                  title: [
                    _detail.item.name,
                    if (_detail.isSeries) _choice.fullLabel,
                    if (episodeName?.isNotEmpty == true) episodeName!,
                  ].join(' · '),
                  position: position,
                  duration: _duration,
                  buffer: _buffer,
                  playing: _playing,
                  rate: _rate,
                  quality: playbackQuality(_resource),
                  locked: _locked,
                  hasEpisodes: _detail.isSeries,
                  airPlay: apple == null
                      ? null
                      : const UiKitView(viewType: 'cinema/apple-route'),
                  onBack: () => Navigator.of(context).maybePop(),
                  onPlay: _togglePlay,
                  onNext: next == null ? null : () => _switchChoice(next),
                  onSeekStart: (value) {
                    _hideControlsTimer?.cancel();
                    setState(() => _dragPositionMs = value);
                  },
                  onSeekChanged: (value) =>
                      setState(() => _dragPositionMs = value),
                  onSeekEnd: _finishSeek,
                  onMenu: _openRexMenu,
                  onLock: _toggleLock,
                  panel: _dock == null
                      ? null
                      : RexPlayerDock(
                          panel: _dock!,
                          detail: _detail,
                          current: _choice,
                          season: _dockSeason,
                          onSeason: (season) =>
                              setState(() => _dockSeason = season),
                          onClose: _closeDock,
                          onChoice: (choice) {
                            _closeDock();
                            if (choice.resource?.id != _resource?.id) {
                              unawaited(_switchChoice(choice));
                            }
                          },
                        ),
                ),
              if (!_loading && _errorTitle == null && !widget.rexStyle)
                PlaybackControls(
                  visible: _controlsVisible,
                  title: _detail.item.name,
                  subtitle: _choice.fullLabel,
                  position: _dragPositionMs == null
                      ? _position
                      : Duration(milliseconds: _dragPositionMs!.round()),
                  duration: _duration,
                  buffer: _buffer,
                  playing: _playing,
                  rate: _rate,
                  compact: compact,
                  onBack: () => Navigator.of(context).maybePop(),
                  onToggleControls: () {
                    if (_controlsVisible) {
                      setState(() => _controlsVisible = false);
                    } else {
                      _showControlsTemporarily();
                    }
                  },
                  onTogglePlay: _togglePlay,
                  onSeekRelative: _seekRelative,
                  onSeekStart: (value) {
                    _hideControlsTimer?.cancel();
                    setState(() => _dragPositionMs = value);
                  },
                  onSeekChanged: (value) =>
                      setState(() => _dragPositionMs = value),
                  onSeekEnd: _finishSeek,
                  onRate: _openRatePanel,
                  onEpisodes: _detail.isSeries ? _openEpisodesPanel : null,
                  onTracks: _openTrackPanel,
                  onFit: _openFitPanel,
                  onLines: _detail.playableLines.length > 1
                      ? _openLinePanel
                      : null,
                ),
              if (_nextChoice != null)
                _NextEpisodePrompt(
                  title: _nextChoice!.episodeLabel,
                  countdown: _nextCountdown,
                  onPlay: _playNext,
                  onCancel: _cancelNextPrompt,
                ),
              if (_ended)
                _EndedPrompt(
                  isSeries: _detail.isSeries,
                  canSwitchLine: _detail.playableLines.length > 1,
                  onReplay: _replay,
                  onSwitchLine: _openLinePanel,
                  onExit: () => Navigator.of(context).maybePop(),
                ),
              if (_hud != null)
                Positioned(
                  top: MediaQuery.viewPaddingOf(context).top + 9,
                  left: 20,
                  right: 20,
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xEB39363C),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 20,
                          ),
                          child: Text(
                            _hud!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _doubleTapX = 0;
  Future<void> _finishSeek(double value) async {
    await _seekEngine(Duration(milliseconds: value.round()));
    _setStateIfMounted(() => _dragPositionMs = null);
    _showControlsTemporarily();
  }

  void _endBoost() {
    if (!_boosted) return;
    _boosted = false;
    unawaited(_rateEngine(_rate));
    _showControlsTemporarily();
  }

  Widget _buildLoading(bool compact) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 18),
            Text(
              _stage,
              style: TextStyle(
                color: CinemaColors.text,
                fontSize: compact ? 14 : 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '只会转存到本应用的专用目录，退出播放后清理。',
              style: TextStyle(color: CinemaColors.faint, fontSize: 12),
            ),
            const SizedBox(height: 20),
            TextButton(onPressed: _cancelLoading, child: const Text('取消加载')),
          ],
        ),
      ),
    );
  }

  Widget _buildError(bool compact) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 26 : 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _needsAccount
                        ? Icons.lock_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 42,
                    color: CinemaColors.muted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _errorTitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 21 : 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _errorDetail ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CinemaColors.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      if (_needsAccount)
                        FilledButton(
                          onPressed: _connectAccount,
                          child: const Text('连接夸克账号'),
                        )
                      else
                        FilledButton(
                          onPressed: _retryPlayback,
                          child: const Text('重新获取地址'),
                        ),
                      if (!_needsAccount &&
                          _detail.playableLines.length > 1 &&
                          _errorTitle != '本集已播完')
                        OutlinedButton(
                          onPressed: _openLinePanel,
                          child: const Text('切换线路'),
                        ),
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('退出播放'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.playing,
    required this.rate,
    required this.compact,
    required this.onBack,
    required this.onToggleControls,
    required this.onTogglePlay,
    required this.onSeekRelative,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onRate,
    required this.onEpisodes,
    required this.onTracks,
    required this.onFit,
    required this.onLines,
  });

  final bool visible;
  final String title;
  final String subtitle;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool playing;
  final double rate;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onToggleControls;
  final Future<void> Function() onTogglePlay;
  final Future<void> Function(int) onSeekRelative;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onRate;
  final VoidCallback? onEpisodes;
  final VoidCallback onTracks;
  final VoidCallback onFit;
  final VoidCallback? onLines;

  String _format(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final max = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final value = position.inMilliseconds.clamp(0, max.round()).toDouble();
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleControls,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 24,
                        8,
                        compact ? 12 : 24,
                        30,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: '返回',
                            onPressed: onBack,
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: CinemaColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (rate != 1)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x55E50914),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('$rate×'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CenterControl(
                      icon: Icons.replay_10_rounded,
                      label: '后退 10 秒',
                      onTap: () => onSeekRelative(-10),
                      size: compact ? 46 : 56,
                    ),
                    SizedBox(width: compact ? 26 : 44),
                    _CenterControl(
                      icon: playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      label: playing ? '暂停' : '播放',
                      onTap: onTogglePlay,
                      size: compact ? 68 : 82,
                      emphasized: true,
                    ),
                    SizedBox(width: compact ? 26 : 44),
                    _CenterControl(
                      icon: Icons.forward_10_rounded,
                      label: '前进 10 秒',
                      onTap: () => onSeekRelative(10),
                      size: compact ? 46 : 56,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xE6000000), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 14 : 26,
                        32,
                        compact ? 14 : 26,
                        10,
                      ),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderThemeData(
                              trackShape: const RoundedRectSliderTrackShape(),
                              secondaryActiveTrackColor: Colors.white30,
                              activeTickMarkColor: Colors.transparent,
                              inactiveTickMarkColor: Colors.transparent,
                            ),
                            child: Slider(
                              value: value.clamp(0, max),
                              max: max,
                              secondaryTrackValue: buffer.inMilliseconds
                                  .clamp(0, max.round())
                                  .toDouble(),
                              onChangeStart: onSeekStart,
                              onChanged: onSeekChanged,
                              onChangeEnd: onSeekEnd,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Row(
                              children: [
                                Text(
                                  _format(position),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                const Spacer(),
                                Text(
                                  _format(duration),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: CinemaColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _ControlAction(
                                icon: Icons.speed_rounded,
                                label: rate == 1 ? '倍速' : '$rate×',
                                onTap: onRate,
                              ),
                              if (onEpisodes != null)
                                _ControlAction(
                                  icon: Icons.playlist_play_rounded,
                                  label: '选集',
                                  onTap: onEpisodes!,
                                ),
                              _ControlAction(
                                icon: Icons.subtitles_outlined,
                                label: '音轨与字幕',
                                onTap: onTracks,
                              ),
                              _ControlAction(
                                icon: Icons.aspect_ratio_rounded,
                                label: '画面',
                                onTap: onFit,
                              ),
                              if (onLines != null)
                                _ControlAction(
                                  icon: Icons.alt_route_rounded,
                                  label: '线路',
                                  onTap: onLines!,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlAction extends StatelessWidget {
  const _ControlAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: CinemaColors.text,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterControl extends StatelessWidget {
  const _CenterControl({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.size,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        autofocus: emphasized,
        radius: size * 0.65,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: emphasized ? const Color(0x55FFFFFF) : Colors.transparent,
            border: emphasized
                ? Border.all(color: const Color(0x99FFFFFF))
                : null,
          ),
          child: Icon(icon, size: emphasized ? size * 0.5 : size * 0.55),
        ),
      ),
    );
  }
}

class _NextEpisodePrompt extends StatelessWidget {
  const _NextEpisodePrompt({
    required this.title,
    required this.countdown,
    required this.onPlay,
    required this.onCancel,
  });

  final String title;
  final int countdown;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 24,
      bottom: 28,
      child: SafeArea(
        child: Material(
          color: const Color(0xEE15181F),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 290,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '即将播放 $title',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$countdown 秒后自动开始',
                  style: const TextStyle(
                    color: CinemaColors.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    FilledButton(onPressed: onPlay, child: const Text('立即播放')),
                    const SizedBox(width: 8),
                    TextButton(onPressed: onCancel, child: const Text('取消')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndedPrompt extends StatelessWidget {
  const _EndedPrompt({
    required this.isSeries,
    required this.canSwitchLine,
    required this.onReplay,
    required this.onSwitchLine,
    required this.onExit,
  });

  final bool isSeries;
  final bool canSwitchLine;
  final VoidCallback onReplay;
  final VoidCallback onSwitchLine;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x8C000000),
      child: Center(
        child: Container(
          width: 330,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xF215181F),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: CinemaColors.muted,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                isSeries ? '当前线路的剧集已播放完毕' : '影片已播放完毕',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isSeries && !canSwitchLine ? '没有更多剧集。' : '进度已保存。',
                style: const TextStyle(color: CinemaColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(onPressed: onReplay, child: const Text('重新播放')),
                  if (canSwitchLine)
                    OutlinedButton(
                      onPressed: onSwitchLine,
                      child: const Text('切换线路'),
                    ),
                  TextButton(onPressed: onExit, child: const Text('退出')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: CinemaColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? CinemaColors.red : CinemaColors.elevatedHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label),
      ),
    );
  }
}
