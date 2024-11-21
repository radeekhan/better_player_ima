import 'dart:async';
import 'package:flutter/material.dart';
import 'package:interactive_media_ads/interactive_media_ads.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWithAds extends StatefulWidget {
  final String contentVideoUrl;
  final String adTagUrl;

  const VideoPlayerWithAds({
    super.key,
    required this.contentVideoUrl,
    required this.adTagUrl,
  });

  @override
  State<VideoPlayerWithAds> createState() => _VideoPlayerWithAdsState();
}

class _VideoPlayerWithAdsState extends State<VideoPlayerWithAds> with WidgetsBindingObserver {
  // Ad-related controllers
  late final AdsLoader _adsLoader;
  AdsManager? _adsManager;
  late final AdDisplayContainer _adDisplayContainer;

  // Video content controller
  late final VideoPlayerController _contentVideoController;

  // State management
  bool _isShowingContent = false;
  Timer? _contentProgressTimer;
  final _contentProgressProvider = ContentProgressProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeVideoPlayer();
    _setupAdDisplayContainer();
  }

  void _initializeVideoPlayer() {
    _contentVideoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.contentVideoUrl),
    )
      ..addListener(_onVideoStateChanged)
      ..initialize().then((_) => setState(() {}));
  }

  void _onVideoStateChanged() {
    if (_contentVideoController.value.isCompleted) {
      _adsLoader.contentComplete();
    }
    setState(() {});
  }

  void _setupAdDisplayContainer() {
    _adDisplayContainer = AdDisplayContainer(
      onContainerAdded: (container) {
        _initializeAdsLoader(container);
        _requestAds(container);
      },
    );
  }

  void _initializeAdsLoader(AdDisplayContainer container) {
    _adsLoader = AdsLoader(
      container: container,
      onAdsLoaded: _handleAdsLoaded,
      onAdsLoadError: _handleAdsLoadError,
    );
  }

  void _handleAdsLoaded(OnAdsLoadedData data) {
    _adsManager = data.manager;
    _adsManager!.setAdsManagerDelegate(AdsManagerDelegate(
      onAdEvent: _handleAdEvent,
      onAdErrorEvent: _handleAdError,
    ));
    _adsManager!.init();
  }

  void _handleAdEvent(AdEvent event) {
    switch (event.type) {
      case AdEventType.loaded:
        _adsManager?.start();
      case AdEventType.contentPauseRequested:
        _pauseContent();
      case AdEventType.contentResumeRequested:
        _resumeContent();
      case AdEventType.allAdsCompleted:
        _cleanupAdsManager();
      default:
        break;
    }
  }

  void _handleAdError(AdErrorEvent event) {
    debugPrint('Ad Error: ${event.error.message}');
    _resumeContent();
  }

  void _handleAdsLoadError(AdsLoadErrorData data) {
    debugPrint('Ads Load Error: ${data.error.message}');
    _resumeContent();
  }

  Future<void> _requestAds(AdDisplayContainer container) async {
    await _adsLoader.requestAds(AdsRequest(
      adTagUrl: widget.adTagUrl,
      contentProgressProvider: _contentProgressProvider,
    ));
  }

  Future<void> _resumeContent() async {
    setState(() => _isShowingContent = true);
    _startContentProgressTracking();
    await _contentVideoController.play();
  }

  Future<void> _pauseContent() async {
    setState(() => _isShowingContent = false);
    _stopContentProgressTracking();
    await _contentVideoController.pause();
  }

  void _startContentProgressTracking() {
    _contentProgressTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      _updateContentProgress,
    );
  }

  void _updateContentProgress(Timer timer) async {
    if (_contentVideoController.value.isInitialized) {
      final progress = await _contentVideoController.position;
      if (progress != null) {
        await _contentProgressProvider.setProgress(
          progress: progress,
          duration: _contentVideoController.value.duration,
        );
      }
    }
  }

  void _stopContentProgressTracking() {
    _contentProgressTimer?.cancel();
    _contentProgressTimer = null;
  }

  void _cleanupAdsManager() {
    _adsManager?.destroy();
    _adsManager = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isShowingContent) {
      _adsManager?.resume();
    } else if (state == AppLifecycleState.inactive && !_isShowingContent) {
      _adsManager?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopContentProgressTracking();
    _contentVideoController.dispose();
    _cleanupAdsManager();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_contentVideoController.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return AspectRatio(
      aspectRatio: _contentVideoController.value.aspectRatio,
      child: Stack(
        children: [
          _adDisplayContainer,
          if (_isShowingContent) VideoPlayer(_contentVideoController),
          if (_isShowingContent) _buildPlayPauseButton(),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FloatingActionButton(
        onPressed: () {
          setState(() {
            _contentVideoController.value.isPlaying
                ? _contentVideoController.pause()
                : _contentVideoController.play();
          });
        },
        child: Icon(
          _contentVideoController.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}