import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Decode dimension in **pixels** for an image shown at [logical] dp/dips, at [dpr].
/// Matches on-screen sharpness without arbitrary downscale caps (CMS assets stay small on disk).
int decodePixelsAlong(double logical, double dpr) {
  if (!logical.isFinite || logical <= 0) {
    return 1;
  }
  final double safeDpr = (!dpr.isFinite || dpr <= 0) ? 1.0 : dpr;
  return math.max(1, (logical * safeDpr).round());
}

/// Convenience: [MediaQuery.devicePixelRatio] with fallback.
double displayPixelRatioOf(BuildContext context) {
  final double dpr = MediaQuery.devicePixelRatioOf(context);
  return (!dpr.isFinite || dpr <= 0) ? 1.0 : dpr;
}
