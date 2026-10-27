import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
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
import 'subtitle_files.dart';
import 'native_player.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({
    super.key,
    required this.detail,
    required this.initialChoice,
    this.updatedDetail,
  });

  final VodDetail detail;
  final EpisodeChoice initialChoice;
  final Future<VodDetail>? updatedDetail;

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
              _player?.state.completed == true &&
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
      await _ensurePlayer();
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
        cancellation.whenCancelled.then((_) => cancellation.throwIfCancelled()),
      ]).timeout(const Duration(seconds: 40));
      if (_disposed || generation != _generation) {
        if (!identical(_lease, lease)) await lease.release();
        return;
      }
      _prepareTimer?.cancel();
      _mediaReady = true;
      _setStateIfMounted(() {
        _loading = false;
        _buffering = _player!.state.buffering;
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
    unawaited(_player?.pause());
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
      unawaited(_player?.pause());
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
    final position = _player?.state.position ?? _position;
    await _saveProgress();
    if (_disposed) return;
    await _startPlayback(resumeAt: position, refreshLease: _lease != null);
  }

  Future<void> _saveProgress({bool completed = false}) async {
    final player = _player;
    final resource = _resource;
    if (!_mediaReady ||
        player == null ||
        resource == null ||
        resource.id.isEmpty ||
        _savingProgress) {
      return;
    }
    final duration = _duration.inMilliseconds > 0
        ? _duration
        : player.state.duration;
    final position = player.state.position;
    if (duration.inMilliseconds <= 0 && position.inMilliseconds <= 0) return;
    _savingProgress = true;
    try {
      await _services.store.saveProgress(
        item: _detail.item,
        resource: resource,
        position: position,
        duration: duration,
        lineGroup: _choice.line.group,
        completed: completed || player.state.completed,
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
    final player = _player;
    if (player == null) return;
    _cancelOverlays();
    await player.seek(Duration.zero);
    await player.play();
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
    final position = sameEpisode
        ? (_player?.state.position ?? _position)
        : Duration.zero;
    await _saveProgress(completed: _player?.state.completed == true);
    if (_disposed) return;
    _mediaReady = false;
    _setStateIfMounted(() {
      _choice = choice;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffer = Duration.zero;
      _errorTitle = null;
      _errorDetail = null;
    });
    await _startPlayback(resumeAt: position);
  }

  Future<void> _seekRelative(int seconds) async {
    final player = _player;
    if (player == null) return;
    final targetMs = (_position.inMilliseconds + seconds * 1000).clamp(
      0,
      _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1 << 62,
    );
    await player.seek(Duration(milliseconds: targetMs));
    _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    _setStateIfMounted(() => _controlsVisible = true);
    _armHideControls();
  }

  void _armHideControls() {
    _hideControlsTimer?.cancel();
    if (_errorTitle != null || _loading || _nextChoice != null) return;
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
    final player = _player;
    if (player == null) return;
    if (player.state.completed) {
      await _replay();
      return;
    }
    if (_playing) {
      await player.pause();
    } else {
      await player.play();
    }
    _showControlsTemporarily();
  }

  Future<void> _selectRate(double value) async {
    await _player?.setRate(value);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _nextTimer?.cancel();
      unawaited(_saveProgress());
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
    unawaited(_saveProgress());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    final lease = _lease;
    _lease = null;
    final player = _player;
    unawaited(() async {
      try {
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
                child: player != null && controller != null
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_nextChoice != null) return;
                          if (_controlsVisible) {
                            setState(() => _controlsVisible = false);
                          } else {
                            _showControlsTemporarily();
                          }
                        },
                        onDoubleTapDown: (details) {
                          final left = details.localPosition.dx < width / 2;
                          unawaited(_seekRelative(left ? -10 : 10));
                        },
                        onDoubleTap: () {},
                        onLongPressStart: (_) async {
                          _hideControlsTimer?.cancel();
                          await _player?.setRate(2);
                          _setStateIfMounted(() => _controlsVisible = true);
                        },
                        onLongPressEnd: (_) async {
                          await _player?.setRate(_rate);
                          _showControlsTemporarily();
                        },
                        child: Video(
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
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.66,
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (_loading) _buildLoading(compact),
              if (_errorTitle != null) _buildError(compact),
              if (!_loading && _errorTitle == null && _buffering)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (!_loading && _errorTitle == null)
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
                  onSeekEnd: (value) async {
                    await _player?.seek(Duration(milliseconds: value.round()));
                    _setStateIfMounted(() => _dragPositionMs = null);
                    _showControlsTemporarily();
                  },
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
            ],
          ),
        ),
      ),
    );
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
