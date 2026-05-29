// dart format width=80

/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: deprecated_member_use,directives_ordering,implicit_dynamic_list_literal,unnecessary_import

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart' as _svg;
import 'package:vector_graphics/vector_graphics.dart' as _vg;

class $AssetsGtfsGen {
  const $AssetsGtfsGen();

  /// File path: assets/gtfs/routes.txt
  String get routes => 'assets/gtfs/routes.txt';

  /// File path: assets/gtfs/shapes.txt
  String get shapes => 'assets/gtfs/shapes.txt';

  /// File path: assets/gtfs/stop_times.txt
  String get stopTimes => 'assets/gtfs/stop_times.txt';

  /// File path: assets/gtfs/stops.txt
  String get stops => 'assets/gtfs/stops.txt';

  /// File path: assets/gtfs/trips.txt
  String get trips => 'assets/gtfs/trips.txt';

  /// List of all assets
  List<String> get values => [routes, shapes, stopTimes, stops, trips];
}

class $AssetsImgGen {
  const $AssetsImgGen();

  /// File path: assets/img/bus_stop.svg
  SvgGenImage get busStop => const SvgGenImage('assets/img/bus_stop.svg');

  /// File path: assets/img/kurt.jpg
  AssetGenImage get kurt => const AssetGenImage('assets/img/kurt.jpg');

  /// File path: assets/img/tofu.png
  AssetGenImage get tofu => const AssetGenImage('assets/img/tofu.png');

  /// List of all assets
  List<dynamic> get values => [busStop, kurt, tofu];
}

class $AssetsRecGen {
  const $AssetsRecGen();

  /// File path: assets/rec/.gitkeep
  String get aGitkeep => 'assets/rec/.gitkeep';

  /// File path: assets/rec/06.10.2024_19.10.2024_ITCS.csv
  String get a0610202419102024ITCS =>
      'assets/rec/06.10.2024_19.10.2024_ITCS.csv';

  /// File path: assets/rec/08.10.2023_21.10.2023_ITCS.csv
  String get a0810202321102023ITCS =>
      'assets/rec/08.10.2023_21.10.2023_ITCS.csv';

  /// List of all assets
  List<String> get values => [
    aGitkeep,
    a0610202419102024ITCS,
    a0810202321102023ITCS,
  ];
}

class $AssetsSoundsGen {
  const $AssetsSoundsGen();

  /// File path: assets/sounds/boing.mp3
  String get boing => 'assets/sounds/boing.mp3';

  /// List of all assets
  List<String> get values => [boing];
}

class $AssetsWeatherGen {
  const $AssetsWeatherGen();

  /// File path: assets/weather/weather_regensburg_all.csv
  String get weatherRegensburgAll =>
      'assets/weather/weather_regensburg_all.csv';

  /// List of all assets
  List<String> get values => [weatherRegensburgAll];
}

class Assets {
  const Assets._();

  static const $AssetsGtfsGen gtfs = $AssetsGtfsGen();
  static const $AssetsImgGen img = $AssetsImgGen();
  static const $AssetsRecGen rec = $AssetsRecGen();
  static const $AssetsSoundsGen sounds = $AssetsSoundsGen();
  static const $AssetsWeatherGen weather = $AssetsWeatherGen();
}

class AssetGenImage {
  const AssetGenImage(
    this._assetName, {
    this.size,
    this.flavors = const {},
    this.animation,
  });

  final String _assetName;

  final Size? size;
  final Set<String> flavors;
  final AssetGenImageAnimation? animation;

  Image image({
    Key? key,
    AssetBundle? bundle,
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? scale,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = true,
    bool isAntiAlias = false,
    String? package,
    FilterQuality filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return Image.asset(
      _assetName,
      key: key,
      bundle: bundle,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      scale: scale,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      package: package,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  ImageProvider provider({AssetBundle? bundle, String? package}) {
    return AssetImage(_assetName, bundle: bundle, package: package);
  }

  String get path => _assetName;

  String get keyName => _assetName;
}

class AssetGenImageAnimation {
  const AssetGenImageAnimation({
    required this.isAnimation,
    required this.duration,
    required this.frames,
  });

  final bool isAnimation;
  final Duration duration;
  final int frames;
}

class SvgGenImage {
  const SvgGenImage(this._assetName, {this.size, this.flavors = const {}})
    : _isVecFormat = false;

  const SvgGenImage.vec(this._assetName, {this.size, this.flavors = const {}})
    : _isVecFormat = true;

  final String _assetName;
  final Size? size;
  final Set<String> flavors;
  final bool _isVecFormat;

  _svg.SvgPicture svg({
    Key? key,
    bool matchTextDirection = false,
    AssetBundle? bundle,
    String? package,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    AlignmentGeometry alignment = Alignment.center,
    bool allowDrawingOutsideViewBox = false,
    WidgetBuilder? placeholderBuilder,
    String? semanticsLabel,
    bool excludeFromSemantics = false,
    _svg.SvgTheme? theme,
    _svg.ColorMapper? colorMapper,
    ColorFilter? colorFilter,
    Clip clipBehavior = Clip.hardEdge,
    @deprecated Color? color,
    @deprecated BlendMode colorBlendMode = BlendMode.srcIn,
    @deprecated bool cacheColorFilter = false,
  }) {
    final _svg.BytesLoader loader;
    if (_isVecFormat) {
      loader = _vg.AssetBytesLoader(
        _assetName,
        assetBundle: bundle,
        packageName: package,
      );
    } else {
      loader = _svg.SvgAssetLoader(
        _assetName,
        assetBundle: bundle,
        packageName: package,
        theme: theme,
        colorMapper: colorMapper,
      );
    }
    return _svg.SvgPicture(
      loader,
      key: key,
      matchTextDirection: matchTextDirection,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      allowDrawingOutsideViewBox: allowDrawingOutsideViewBox,
      placeholderBuilder: placeholderBuilder,
      semanticsLabel: semanticsLabel,
      excludeFromSemantics: excludeFromSemantics,
      colorFilter:
          colorFilter ??
          (color == null ? null : ColorFilter.mode(color, colorBlendMode)),
      clipBehavior: clipBehavior,
      cacheColorFilter: cacheColorFilter,
    );
  }

  String get path => _assetName;

  String get keyName => _assetName;
}
