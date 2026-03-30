import 'ad_content.dart';

/// Holds ads content prefetched during native splash so [HomeCubit] can use it
/// without refetching. Single-use: once consumed, the holder is cleared.
class PreloadedAdsHolder {
  PreloadedAdsHolder._();
  static final PreloadedAdsHolder instance = PreloadedAdsHolder._();

  AdContent? _content;

  void set(AdContent content) {
    _content = content;
  }

  AdContent? take() {
    final value = _content;
    _content = null;
    return value;
  }

  bool get hasContent => _content != null;
}
