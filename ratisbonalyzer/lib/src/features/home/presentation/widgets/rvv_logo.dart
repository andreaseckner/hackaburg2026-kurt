import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ratisbonalyzer/src/core/theme/dimens.dart';

class RvvLogo extends StatelessWidget {
  /// The SVG content containing only the "RVV" letters.
  /// The viewBox and path are scaled to make the letters fill more of the height.
  static const String _svgContent = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 1 110 39" fill="currentColor">
  <path d="M 28.3,13.2 C 28.3,5 22.6,1.4 15,1.4 H 0 V 39.8 H 10 V 25 h 0.1 l 9.5,14.8 H 32 L 19.9,24.1 c 5.5,-1 8.4,-5.6 8.4,-10.9 z m -10.4,0.6 c 0,4.2 -3.7,4.8 -6.9,4.8 H 10 V 9 h 1 c 3.2,0 6.9,0.7 6.9,4.8 z" />
  <path d="M 57.1,1.4 L 49.2,24.7 39.9,1.4 H 29 L 45.2,39.8 H 53 L 68,1.4 Z" />
  <path d="M 91.3,39.8 107.7,1.4 H 96.8 L 87.5,24.7 79.6,1.4 H 68.7 l 14.8,38.4 z" />
</svg>
''';

  const RvvLogo({
    super.key,
    this.height = Dimens.rvvLogoHeight,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svgContent,
      height: height,
      // Color is now handled via 'currentColor' in SVG and 'color' here
      // which uses the IconTheme or can be overridden.
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.primary,
        BlendMode.srcIn,
      ),
    );
  }
}
