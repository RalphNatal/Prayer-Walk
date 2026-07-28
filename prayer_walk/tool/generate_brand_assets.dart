// Draws the brand mark and writes the PNGs the launcher icon and native splash
// are generated from.
//
//   dart run tool/generate_brand_assets.dart
//
// This exists so the artwork has provenance. Everything below is computed from
// the same geometry `BrandTrailMark` paints at runtime — the same two cubics,
// the same three waypoints, the same amber→pine gradient — so the icon on the
// home screen is literally the mark the app draws on its own splash, not a
// lookalike traced from somewhere else. No third-party artwork, no clip art,
// nothing lifted.
//
// Rendering is done by hand rather than through `dart:ui`, because that would
// need a Flutter runtime and a device. Each pixel is coloured by its distance
// to the path: inside the stroke width it takes the gradient, outside it takes
// a Gaussian falloff for the glow. Supersampled 3× and box-filtered down, which
// is where the edge quality comes from.
//
// The distance field comes from an exact Euclidean distance transform
// (Felzenszwalb & Huttenlocher's two-pass parabola envelope), not from testing
// every pixel against every segment — the glow reaches a quarter of the canvas,
// and the naive form is millions of pixels times a thousand segments.
//
// Outputs (assets/brand/):
//   icon.png             1024²  RGB, no alpha channel  — iOS + Android legacy
//   icon_foreground.png  1024²  RGBA, mark in the adaptive safe zone
//   splash.png           1024²  RGBA, mark only, for flutter_native_splash
//
// Re-run after changing the geometry, then `dart run flutter_launcher_icons`
// and `dart run flutter_native_splash:create`.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// ------------------------------------------------------------------ palette ---

/// Pine — the ground the mark sits on, straight from `AppColors.pine`.
const _pine = _Rgb(0x22, 0x3D, 0x30);

/// The trail gradient, bottom-left to top-right: the tail in moss, kindling
/// through to an amber head.
///
/// This is `AppTrailTheme.dark.trailColors` reversed, with one deliberate
/// change: the darkest stop (#2F5540) is replaced by moss (#3E6B4F). On screen
/// that stop sits over map tiles and needs to recede; here it sits on solid
/// pine, and at 48 px the tail would simply disappear into the ground.
const _trail = <_Rgb>[
  _Rgb(0x3E, 0x6B, 0x4F), // moss
  _Rgb(0x6F, 0xA5, 0x7F), // mossLight
  _Rgb(0xC9, 0x8F, 0x45),
  _Rgb(0xE3, 0xA2, 0x4A), // amber
];
const _trailStops = <double>[0.0, 0.32, 0.68, 1.0];

/// `AppTrailTheme.dark.waypointCore` and `waypointHalo`.
const _waypointCore = _Rgb(0xFF, 0xEA, 0xCA);
const _waypointHalo = _Rgb(0xE3, 0xA2, 0x4A);

void main() {
  final out = Directory('assets/brand')..createSync(recursive: true);

  // Full bleed on pine. Written without an alpha channel at all, which is the
  // App Store's requirement for an icon — not merely opaque pixels.
  _write(
    '${out.path}/icon.png',
    _render(1024, markWidthFraction: 0.72, ground: _pine),
    alpha: false,
  );

  // The adaptive foreground. Android masks this to a circle, squircle or
  // teardrop and can parallax it, so only the central 66% of the 108dp canvas
  // is guaranteed visible. 0.58 keeps the mark and its glow comfortably inside
  // that, with room for the mask to breathe.
  _write(
    '${out.path}/icon_foreground.png',
    _render(1024, markWidthFraction: 0.58, ground: null),
    alpha: true,
  );

  // The splash mark. The ground is a flat colour set in flutter_native_splash
  // (pine in light, near-black forest in dark), so this is the mark alone.
  _write(
    '${out.path}/splash.png',
    _render(1024, markWidthFraction: 0.62, ground: null),
    alpha: true,
  );

  stdout.writeln('Wrote icon.png, icon_foreground.png, splash.png to ${out.path}');
}

// ------------------------------------------------------------------- render ---

/// Straight-alpha RGBA pixels, [size]×[size].
Uint8List _render(int size, {required double markWidthFraction, _Rgb? ground}) {
  const ss = 3; // supersample factor
  final big = size * ss;
  final acc = Float64List(size * size * 4);

  // The mark's own box, centred. `BrandTrailMark` uses a 1 : 0.72 box; keeping
  // that ratio is what makes this the same drawing rather than a squashed one.
  final markW = big * markWidthFraction;
  final markH = markW * 0.72;
  final originX = (big - markW) / 2;
  final originY = (big - markH) / 2;

  double px(double u) => originX + u * markW;
  double py(double v) => originY + v * markH;

  // The two cubics, sampled densely enough that the polyline is
  // indistinguishable from the curve at this resolution.
  final path = <_P>[];
  void cubic(_P a, _P b, _P c, _P d) {
    const steps = 600;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final mt = 1 - t;
      path.add(
        _P(
          mt * mt * mt * a.x + 3 * mt * mt * t * b.x + 3 * mt * t * t * c.x + t * t * t * d.x,
          mt * mt * mt * a.y + 3 * mt * mt * t * b.y + 3 * mt * t * t * c.y + t * t * t * d.y,
        ),
      );
    }
  }

  cubic(
    _P(px(0.06), py(0.92)),
    _P(px(0.30), py(0.86)),
    _P(px(0.18), py(0.46)),
    _P(px(0.46), py(0.44)),
  );
  cubic(
    _P(px(0.46), py(0.44)),
    _P(px(0.74), py(0.42)),
    _P(px(0.62), py(0.16)),
    _P(px(0.94), py(0.08)),
  );

  // Arc length, so the waypoints land where they do on screen.
  final cumulative = <double>[0];
  for (var i = 1; i < path.length; i++) {
    cumulative.add(cumulative[i - 1] + path[i].distanceTo(path[i - 1]));
  }
  final total = cumulative.last;
  _P at(double fraction) {
    final target = total * fraction;
    var lo = 0, hi = cumulative.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (cumulative[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return path[lo];
  }

  final waypoints = [for (final f in const [0.22, 0.55, 0.88]) at(f)];

  // Widths, in the same proportions BrandTrailMark uses against its 168px box.
  //
  // The glow is the one place this deviates. On screen it is a `MaskFilter`
  // blur, which normalises as it spreads; a plain Gaussian on distance at the
  // same sigma reads much broader, and at 48 px turned the mark into an olive
  // smudge. 6.5 rather than 12 puts the falloff where the rendered blur
  // actually sits — close to the line, kindling it rather than fogging it.
  final stroke = markW * 7 / 168 / 2;
  final glow = markW * 18 / 168 / 2;
  final glowSigma = markW * 6.5 / 168;
  final haloR = markW * 11 / 168;
  final coreR = markW * 4.5 / 168;

  // Only the rows the mark can touch are scanned; the rest stay ground.
  final pad = (glow + glowSigma * 3 + haloR).ceil();
  final minY = math.max(0, (originY - pad).floor());
  final maxY = math.min(big - 1, (originY + markH + pad).ceil());
  final minX = math.max(0, (originX - pad).floor());
  final maxX = math.min(big - 1, (originX + markW + pad).ceil());

  // Distance to the centreline, for every pixel in the scan box at once.
  final field = _distanceField(path, minX, minY, maxX, maxY);
  final fieldW = maxX - minX + 1;

  // The gradient runs bottom-left → top-right across the mark box, matching
  // `LinearGradient(begin: bottomLeft, end: topRight)`.
  final axis = _P(markW, -markH);
  final axisLen2 = axis.x * axis.x + axis.y * axis.y;

  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final p = _P(x + 0.5, y + 0.5);
      final d = field[(y - minY) * fieldW + (x - minX)];

      // Glow first, then the stroke over it, then the candles.
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;

      final glowFall = d <= glow
          ? 1.0
          : math.exp(-((d - glow) * (d - glow)) / (2 * glowSigma * glowSigma));
      if (glowFall > 0.004) {
        final ga = 0.40 * glowFall;
        r = _waypointHalo.r * ga;
        g = _waypointHalo.g * ga;
        b = _waypointHalo.b * ga;
        a = ga;
      }

      final strokeA = _coverage(d, stroke);
      if (strokeA > 0) {
        final rel = ((p.x - originX) * axis.x + (p.y - (originY + markH)) * axis.y) / axisLen2;
        final c = _sample(rel.clamp(0.0, 1.0));
        (r, g, b, a) = _over(c.r, c.g, c.b, strokeA, r, g, b, a);
      }

      for (final w in waypoints) {
        final wd = p.distanceTo(w);
        final halo = math.exp(-(wd * wd) / (2 * (haloR * 0.5) * (haloR * 0.5)));
        if (halo > 0.004) {
          (r, g, b, a) = _over(
            _waypointHalo.r,
            _waypointHalo.g,
            _waypointHalo.b,
            0.55 * halo,
            r,
            g,
            b,
            a,
          );
        }
        final core = _coverage(wd, coreR);
        if (core > 0) {
          (r, g, b, a) = _over(
            _waypointCore.r,
            _waypointCore.g,
            _waypointCore.b,
            core,
            r,
            g,
            b,
            a,
          );
        }
      }

      if (a <= 0) continue;
      final di = ((y ~/ ss) * size + (x ~/ ss)) * 4;
      acc[di] += r;
      acc[di + 1] += g;
      acc[di + 2] += b;
      acc[di + 3] += a;
    }
  }

  // Box-filter the supersamples down and, if there is a ground, composite onto
  // it here so the output is a flat opaque image.
  final n = ss * ss;
  final pixels = Uint8List(size * size * 4);
  for (var i = 0; i < size * size; i++) {
    final a = (acc[i * 4 + 3] / n).clamp(0.0, 1.0);
    final r = acc[i * 4] / n;
    final g = acc[i * 4 + 1] / n;
    final b = acc[i * 4 + 2] / n;
    if (ground == null) {
      // Straight alpha: un-premultiply so the mark keeps its colour where it
      // is semi-transparent.
      pixels[i * 4] = a == 0 ? 0 : (r / a).clamp(0, 255).round();
      pixels[i * 4 + 1] = a == 0 ? 0 : (g / a).clamp(0, 255).round();
      pixels[i * 4 + 2] = a == 0 ? 0 : (b / a).clamp(0, 255).round();
      pixels[i * 4 + 3] = (a * 255).round();
    } else {
      pixels[i * 4] = (r + ground.r * (1 - a)).clamp(0, 255).round();
      pixels[i * 4 + 1] = (g + ground.g * (1 - a)).clamp(0, 255).round();
      pixels[i * 4 + 2] = (b + ground.b * (1 - a)).clamp(0, 255).round();
      pixels[i * 4 + 3] = 255;
    }
  }
  return pixels;
}

/// Source-over, both sides premultiplied. Channels are `num` so the palette's
/// integer components can be passed straight in.
(double, double, double, double) _over(
  num sr,
  num sg,
  num sb,
  double sa,
  double dr,
  double dg,
  double db,
  double da,
) => (
  sr * sa + dr * (1 - sa),
  sg * sa + dg * (1 - sa),
  sb * sa + db * (1 - sa),
  sa + da * (1 - sa),
);

/// Antialiased coverage for a shape of radius [radius] at distance [d].
double _coverage(double d, double radius) {
  const aa = 0.7;
  if (d <= radius - aa) return 1;
  if (d >= radius + aa) return 0;
  return (radius + aa - d) / (2 * aa);
}

_Rgb _sample(double t) {
  for (var i = 1; i < _trailStops.length; i++) {
    if (t <= _trailStops[i]) {
      final span = _trailStops[i] - _trailStops[i - 1];
      final f = span == 0 ? 0.0 : (t - _trailStops[i - 1]) / span;
      final a = _trail[i - 1], b = _trail[i];
      return _Rgb(
        (a.r + (b.r - a.r) * f).round(),
        (a.g + (b.g - a.g) * f).round(),
        (a.b + (b.b - a.b) * f).round(),
      );
    }
  }
  return _trail.last;
}

/// Distance from every pixel in the box to the nearest point on [path].
///
/// Felzenszwalb & Huttenlocher: seed the centreline at zero, then take the
/// lower envelope of parabolas along each row and each column in turn. Two
/// linear passes for an exact Euclidean transform, instead of testing every
/// pixel against every segment.
///
/// The centreline is seeded by its containing pixel, so the field is quantised
/// to the supersampled grid — a third of an output pixel here, which the box
/// filter absorbs.
Float64List _distanceField(
  List<_P> path,
  int minX,
  int minY,
  int maxX,
  int maxY,
) {
  final w = maxX - minX + 1;
  final h = maxY - minY + 1;
  const inf = 1e20;
  final f = Float64List(w * h)..fillRange(0, w * h, inf);

  for (final p in path) {
    final x = p.x.floor() - minX;
    final y = p.y.floor() - minY;
    if (x < 0 || y < 0 || x >= w || y >= h) continue;
    f[y * w + x] = 0;
  }

  // 1-D squared-distance transform of one row of samples.
  Float64List transform1d(Float64List src) {
    final n = src.length;
    final d = Float64List(n);
    final v = Int32List(n);
    final z = Float64List(n + 1);
    var k = 0;
    v[0] = 0;
    z[0] = -inf;
    z[1] = inf;
    for (var q = 1; q < n; q++) {
      var s = ((src[q] + q * q) - (src[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      while (s <= z[k]) {
        k--;
        s = ((src[q] + q * q) - (src[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = inf;
    }
    k = 0;
    for (var q = 0; q < n; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final dx = q - v[k];
      d[q] = dx * dx + src[v[k]];
    }
    return d;
  }

  final column = Float64List(h);
  final row = Float64List(w);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      row[x] = f[y * w + x];
    }
    final d = transform1d(row);
    for (var x = 0; x < w; x++) {
      f[y * w + x] = d[x];
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      column[y] = f[y * w + x];
    }
    final d = transform1d(column);
    for (var y = 0; y < h; y++) {
      f[y * w + x] = d[y];
    }
  }

  for (var i = 0; i < f.length; i++) {
    f[i] = math.sqrt(f[i]);
  }
  return f;
}

class _P {
  const _P(this.x, this.y);
  final double x, y;
  double distanceTo(_P o) {
    final dx = x - o.x, dy = y - o.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final int r, g, b;
}

// ---------------------------------------------------------------- PNG output ---
//
// Written by hand rather than pulled from `package:image`, so generating the
// brand assets adds no dependency to a shipped app.

void _write(String path, Uint8List rgba, {required bool alpha}) {
  final size = math.sqrt(rgba.length / 4).round();
  final channels = alpha ? 4 : 3;

  // Filter type 0 (none) on every scanline. The mark is smooth gradients on a
  // flat ground; deflate handles it well enough that a filter search would buy
  // little for a build-time asset.
  final raw = Uint8List(size * (1 + size * channels));
  var o = 0;
  for (var y = 0; y < size; y++) {
    raw[o++] = 0;
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      raw[o++] = rgba[i];
      raw[o++] = rgba[i + 1];
      raw[o++] = rgba[i + 2];
      if (alpha) raw[o++] = rgba[i + 3];
    }
  }

  final png = BytesBuilder()
    ..add(const [137, 80, 78, 71, 13, 10, 26, 10])
    ..add(
      _chunk('IHDR', (BytesBuilder()
            ..add(_u32(size))
            ..add(_u32(size))
            // bit depth 8; colour type 6 = RGBA, 2 = RGB (no alpha channel).
            ..add([8, alpha ? 6 : 2, 0, 0, 0]))
          .toBytes()),
    )
    ..add(_chunk('IDAT', ZLibCodec(level: 9).encode(raw) as Uint8List))
    ..add(_chunk('IEND', Uint8List(0)));

  File(path).writeAsBytesSync(png.toBytes());
  stdout.writeln(
    '  ${path.split('/').last.padRight(22)} $size×$size  '
    '${alpha ? 'RGBA' : 'RGB (no alpha channel)'}  '
    '${(File(path).lengthSync() / 1024).toStringAsFixed(1)} KB',
  );
}

Uint8List _chunk(String tag, Uint8List data) {
  final body = BytesBuilder()
    ..add(tag.codeUnits)
    ..add(data);
  final bytes = body.toBytes();
  return (BytesBuilder()
        ..add(_u32(data.length))
        ..add(bytes)
        ..add(_u32(_crc32(bytes))))
      .toBytes();
}

Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
