import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

double interpolateDriverBearing(double from, double to, double progress) {
  var delta = (to - from) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return (from + delta * progress) % 360;
}

double stableDriverBearing({
  required double previous,
  required double incoming,
  required double speedKmh,
}) =>
    speedKmh < 2 || !incoming.isFinite ? previous : incoming;

Duration driverMotionDuration(DateTime previous, DateTime incoming) {
  final milliseconds = incoming.difference(previous).inMilliseconds;
  return Duration(milliseconds: math.max(600, math.min(3000, milliseconds)));
}

/// Follows the ordered EVIK route only when both GPS fixes agree with it.
/// A null result tells the map to preserve the raw measurement instead of
/// pulling a vehicle in a yard onto a nearby or parallel road.
LatLng? interpolateDriverPositionOnRoute({
  required LatLng start,
  required LatLng end,
  required List<LatLng> route,
  required double progress,
  required double accuracyM,
  required double bearing,
  required double speedKmh,
}) {
  if (route.length < 2) return null;
  final projectedStart = _projectOnRoute(start, route);
  final projectedEnd = _projectOnRoute(end, route);
  final tolerance = (accuracyM.isFinite ? accuracyM * 1.5 : 15.0)
      .clamp(12.0, 35.0)
      .toDouble();
  if (projectedStart.distanceM > tolerance ||
      projectedEnd.distanceM > tolerance ||
      projectedEnd.offsetM + 3 < projectedStart.offsetM) {
    return null;
  }
  if (speedKmh >= 5 &&
      bearing.isFinite &&
      _bearingDelta(bearing, projectedEnd.segmentBearing) > 70) {
    return null;
  }
  final offset = projectedStart.offsetM +
      (projectedEnd.offsetM - projectedStart.offsetM) *
          progress.clamp(0.0, 1.0);
  return _pointAtOffset(route, offset);
}

class _RouteProjection {
  const _RouteProjection(this.offsetM, this.distanceM, this.segmentBearing);

  final double offsetM;
  final double distanceM;
  final double segmentBearing;
}

_RouteProjection _projectOnRoute(LatLng point, List<LatLng> route) {
  const distance = Distance();
  var bestDistance = double.infinity;
  var bestOffset = 0.0;
  var bestBearing = 0.0;
  var walked = 0.0;
  for (var index = 0; index < route.length - 1; index++) {
    final a = route[index];
    final b = route[index + 1];
    final segmentLength = distance.as(LengthUnit.Meter, a, b);
    if (segmentLength <= 0) continue;
    final longitudeScale = math
        .cos(((a.latitude + b.latitude + point.latitude) / 3) * math.pi / 180);
    final ax = a.longitude * longitudeScale;
    final bx = b.longitude * longitudeScale;
    final px = point.longitude * longitudeScale;
    final dx = bx - ax;
    final dy = b.latitude - a.latitude;
    final denominator = dx * dx + dy * dy;
    final fraction = denominator == 0
        ? 0.0
        : (((px - ax) * dx + (point.latitude - a.latitude) * dy) / denominator)
            .clamp(0.0, 1.0)
            .toDouble();
    final projected = LatLng(
      a.latitude + (b.latitude - a.latitude) * fraction,
      a.longitude + (b.longitude - a.longitude) * fraction,
    );
    final gap = distance.as(LengthUnit.Meter, point, projected);
    if (gap < bestDistance) {
      bestDistance = gap;
      bestOffset = walked + segmentLength * fraction;
      bestBearing = distance.bearing(a, b);
    }
    walked += segmentLength;
  }
  return _RouteProjection(bestOffset, bestDistance, bestBearing);
}

LatLng _pointAtOffset(List<LatLng> route, double requestedOffset) {
  const distance = Distance();
  var walked = 0.0;
  for (var index = 0; index < route.length - 1; index++) {
    final a = route[index];
    final b = route[index + 1];
    final length = distance.as(LengthUnit.Meter, a, b);
    if (requestedOffset <= walked + length || index == route.length - 2) {
      final fraction = length <= 0
          ? 0.0
          : ((requestedOffset - walked) / length).clamp(0.0, 1.0);
      return LatLng(
        a.latitude + (b.latitude - a.latitude) * fraction,
        a.longitude + (b.longitude - a.longitude) * fraction,
      );
    }
    walked += length;
  }
  return route.last;
}

double _bearingDelta(double first, double second) =>
    ((((first - second + 540) % 360) - 180) as num).abs().toDouble();
