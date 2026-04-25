import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:marquee/marquee.dart';
import '../core/services/rss_service.dart';

/// Where and how the ticker is laid out relative to [screenType] / poster orientation.
enum NewsTickerLayout {
  /// Full width, horizontal scroll — bottom bar (LANDSCAPE screen).
  landscapeBottomBar,

  /// Narrow strip on the **left**; date + news use horizontal layout rotated 90° (PORTRAIT).
  portraitPosterLeftRail,
}

class NewsTickerOverlay extends StatefulWidget {
  const NewsTickerOverlay({
    super.key,
    this.layout = NewsTickerLayout.landscapeBottomBar,
  });

  final NewsTickerLayout layout;

  @override
  State<NewsTickerOverlay> createState() => _NewsTickerOverlayState();
}

class _NewsTickerOverlayState extends State<NewsTickerOverlay> {
  final RssService _rssService = RssService();
  String _newsText = '';
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchNewsBackground();

    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _fetchNewsBackground();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchNewsBackground() async {
    final news = await _rssService.fetchNews();
    if (mounted) {
      setState(() {
        _newsText = news;
        _isLoading = false;
      });
    }
  }

  static const Color _barColor = Color(0xFF6D0000);

  @override
  Widget build(BuildContext context) {
    if (widget.layout == NewsTickerLayout.portraitPosterLeftRail) {
      return _buildPortraitLeftRail(context);
    }
    return _buildLandscapeBottomBar(context);
  }

  Widget _buildLandscapeBottomBar(BuildContext context) {
    final Widget scrollingContent = _scrollingSection(
      scrollAxis: Axis.horizontal,
      fontSize: 30,
      blankSpace: 200,
      velocity: 40,
      startPadding: 8,
    );

    return Container(
      height: 62,
      color: _barColor,
      child: Row(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: _DateTimeDisplay(compact: false, denseSpacing: false),
          ),
          Container(width: 1, height: 36, color: Colors.white30),
          Expanded(child: scrollingContent),
        ],
      ),
    );
  }

  /// Left rail: horizontal marquee rotated 90° (same idea as portrait posters).
  Widget _buildPortraitLeftRail(BuildContext context) {
    const double railWidth = 70;
    const double rotatedStripHeight = 66;

    return SizedBox(
      width: railWidth,
      child: ColoredBox(
        color: _barColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              flex: 1,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double runLength = constraints.maxHeight;
                  if (runLength <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Center(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: SizedBox(
                        width: runLength,
                        height: 46,
                        child: const Center(
                          child: _DateTimeDisplay(
                            compact: true,
                            denseSpacing: true,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(height: 1, color: Colors.white30),
            Expanded(
              flex: 4,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double runLength = constraints.maxHeight;
                  if (runLength <= 0) {
                    return const SizedBox.shrink();
                  }
                  return Center(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: SizedBox(
                        width: runLength,
                        height: rotatedStripHeight,
                        child: _scrollingSection(
                          scrollAxis: Axis.horizontal,
                          fontSize: 22,
                          blankSpace: 160,
                          velocity: 40,
                          startPadding: 6,
                          useSmoothTicker: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrollingSection({
    required Axis scrollAxis,
    required double fontSize,
    required double blankSpace,
    required double velocity,
    required double startPadding,
    bool useSmoothTicker = false,
  }) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            color: Colors.white70,
            strokeWidth: 3,
          ),
        ),
      );
    }
    if (_newsText.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Failed to load news ticker.',
            textAlign: scrollAxis == Axis.vertical ? TextAlign.center : TextAlign.start,
            style: TextStyle(color: Colors.white, fontSize: fontSize * 0.65),
          ),
        ),
      );
    }
    final TextStyle tickerStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
    );
    if (useSmoothTicker && scrollAxis == Axis.horizontal) {
      return RepaintBoundary(
        child: _SmoothHorizontalTicker(
          text: _newsText,
          style: tickerStyle,
          velocity: velocity,
          blankSpace: blankSpace,
          startPadding: startPadding,
        ),
      );
    }
    return Marquee(
      text: _newsText,
      style: tickerStyle,
      scrollAxis: scrollAxis,
      crossAxisAlignment: CrossAxisAlignment.center,
      blankSpace: blankSpace,
      velocity: velocity,
      pauseAfterRound: const Duration(seconds: 1),
      startPadding: startPadding,
    );
  }
}

/// Constant-velocity ticker for narrow / transformed strips (e.g. portrait left rail).
/// Avoids [Marquee]'s per-round [ScrollController.jumpTo] + pause, which reads as judder under [RotatedBox].
class _SmoothHorizontalTicker extends StatefulWidget {
  const _SmoothHorizontalTicker({
    required this.text,
    required this.style,
    required this.velocity,
    required this.blankSpace,
    required this.startPadding,
  });

  final String text;
  final TextStyle style;
  final double velocity;
  final double blankSpace;
  final double startPadding;

  @override
  State<_SmoothHorizontalTicker> createState() => _SmoothHorizontalTickerState();
}

class _SmoothHorizontalTickerState extends State<_SmoothHorizontalTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// One cycle in logical pixels: [startPadding] + text + [blankSpace].
  double _loopPx = 0;

  Widget _segment = const SizedBox.shrink();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _syncMetricsAndSegment();
    if (_loopPx > 0) {
      _controller.repeat();
    }
  }

  void _syncMetricsAndSegment() {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);
    final double textW = tp.width;
    _loopPx = widget.startPadding + textW + widget.blankSpace;
    _segment = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(width: widget.startPadding),
        Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          softWrap: false,
        ),
        SizedBox(width: widget.blankSpace),
        Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          softWrap: false,
        ),
        SizedBox(width: widget.blankSpace),
      ],
    );
    if (_loopPx <= 0 || !widget.velocity.isFinite || widget.velocity.abs() < 1e-6) {
      _controller.duration = const Duration(days: 1);
      return;
    }
    final int ms = ((_loopPx / widget.velocity.abs()) * 1000).round().clamp(200, 86400000);
    _controller.duration = Duration(milliseconds: ms);
  }

  @override
  void didUpdateWidget(covariant _SmoothHorizontalTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.velocity != widget.velocity ||
        oldWidget.blankSpace != widget.blankSpace ||
        oldWidget.startPadding != widget.startPadding) {
      _syncMetricsAndSegment();
      if (_loopPx > 0) {
        _controller
          ..reset()
          ..repeat();
      } else {
        _controller.stop();
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loopPx <= 0) {
      return const SizedBox.shrink();
    }
    // Tight width from parent; content is far wider. [UnconstrainedBox] still
    // triggers overflow asserts (RenderConstraintsTransformBox). A horizontal
    // [SingleChildScrollView] gives the row unbounded max width on the scroll axis.
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        child: AnimatedBuilder(
          animation: _controller,
          child: _segment,
          builder: (BuildContext context, Widget? child) {
            return Transform.translate(
              offset: Offset(-_loopPx * _controller.value, 0),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class _DateTimeDisplay extends StatefulWidget {
  const _DateTimeDisplay({
    required this.compact,
    this.denseSpacing = false,
  });

  /// Narrow stacked time/date for the portrait left rail.
  final bool compact;

  /// Portrait rail: no extra gaps between time / AM-PM / date.
  final bool denseSpacing;

  @override
  State<_DateTimeDisplay> createState() => _DateTimeDisplayState();
}

class _DateTimeDisplayState extends State<_DateTimeDisplay> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String timeString = DateFormat('hh:mm').format(_now);
    final String amPmString = DateFormat('a').format(_now);
    final String dateString = DateFormat('MMM dd, yyyy').format(_now);

    if (widget.compact) {
      final Widget timeRow = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            timeString,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
          if (!widget.denseSpacing) const SizedBox(width: 2),
          Text(
            amPmString,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
      final Widget dateText = Text(
        dateString,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: TextStyle(
          color: Colors.white70,
          fontSize: 8,
          fontWeight: FontWeight.w500,
          height: widget.denseSpacing ? 1.0 : 1.12,
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          timeRow,
          if (!widget.denseSpacing) const SizedBox(height: 4),
          dateText,
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              timeString,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              amPmString,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          dateString,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
