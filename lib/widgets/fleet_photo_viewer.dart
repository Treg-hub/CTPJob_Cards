import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Opens a fullscreen, swipeable, pinch-to-zoom viewer over [urls].
void showFleetPhotoViewer(
  BuildContext context,
  List<String> urls, {
  int initialIndex = 0,
}) {
  if (urls.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _FleetPhotoViewerScreen(
        urls: urls,
        initialIndex: initialIndex.clamp(0, urls.length - 1),
      ),
    ),
  );
}

/// Tappable photo thumbnail with a broken-image fallback.
/// Tapping opens the fullscreen viewer at this photo.
class FleetPhotoThumb extends StatelessWidget {
  const FleetPhotoThumb({
    super.key,
    required this.urls,
    required this.index,
    this.size = 100,
  });

  final List<String> urls;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).appColors.textMuted;
    return GestureDetector(
      onTap: () => showFleetPhotoViewer(context, urls, initialIndex: index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          urls[index],
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => Container(
            width: size,
            height: size,
            color: muted.withValues(alpha: 0.1),
            child: Icon(Icons.broken_image_outlined, color: muted),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: size,
              height: size,
              color: muted.withValues(alpha: 0.08),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FleetPhotoViewerScreen extends StatefulWidget {
  const _FleetPhotoViewerScreen({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FleetPhotoViewerScreen> createState() =>
      _FleetPhotoViewerScreenState();
}

class _FleetPhotoViewerScreenState extends State<_FleetPhotoViewerScreen> {
  late final PageController _pageCtrl =
      PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} of ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              errorBuilder: (context, _, __) => const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 48),
                  SizedBox(height: 8),
                  Text(
                    'Photo could not be loaded.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
