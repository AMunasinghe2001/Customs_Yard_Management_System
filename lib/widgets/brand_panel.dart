import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme.dart';

/// The colour the crest's ship and plane are painted in the shipped asset.
///
/// Public so a test can assert the swap actually happened, rather than trusting
/// that a colour handed correctly around the widget tree reached the SVG.
const String kCrestKnockoutHex = '#1a1764';

/// Repaints the crest's knockout to [behind] -- the colour the crest is drawn
/// over -- so the ship and plane keep reading as holes.
///
/// ⚠️ Alpha is dropped: the SVG `fill:` takes `#rrggbb`, and a
/// translucent knockout would let the filled disc beneath show through and stop
/// looking like a hole at all.
String crestWithKnockout(String svgSource, Color behind) {
  final hex =
      '#${behind.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  return svgSource.replaceAll('fill:$kCrestKnockoutHex', 'fill:$hex');
}

/// The dark half of every sign-in and sign-up screen: the crest, the name, and
/// a badge naming the portal.
///
/// ## The knockout problem this exists to solve
///
/// The ship and the aeroplane in the middle of the crest are not transparent.
/// They are painted a flat `#1a1764` -- the app's own dark navy -- because a
/// real transparent knockout does not survive flutter_svg: the shapes sit on
/// top of a filled disc, and cutting them out needs an even-odd path or a mask
/// the renderer drops. Painting them the background colour was the way to make
/// them read as holes.
///
/// That trick only holds while the background behind them IS that colour. The
/// panel is a three-stop gradient, so it already only just holds -- and the
/// moment the gradient MOVES, the two shapes stop matching what is behind them
/// and the crest looks like it has two navy stickers on it.
///
/// So this widget does not animate the background alone. Every frame it works
/// out the colour actually behind the crest and re-paints the knockout to
/// match, by swapping the literal in the SVG source before handing it to
/// [SvgPicture.string]. The holes stay holes for the whole animation.
///
/// ⚠️ If the crest is ever re-exported with real transparency, delete
/// [kCrestKnockoutHex] and [crestWithKnockout] with it -- not the animation.
class BrandPanel extends StatefulWidget {
  /// The accent this portal is themed with -- green for Disposal, gold for
  /// DC/SDDC, and so on. The gradient's third stop and the crest's tint.
  final Color accent;

  /// The darkest corner, top-left. Each portal picks its own near-black.
  final Color deepColor;

  /// Portal name for the badge under the title.
  final String badgeLabel;

  /// Optional mark beside it. ⚠️ Nullable because one screen's badge has
  /// never had an icon, and inventing one for it would be a design change
  /// smuggled in under a refactor.
  final IconData? badgeIcon;

  /// Shown under "Sri Lanka Customs".
  final String subtitle;

  const BrandPanel({
    super.key,
    required this.accent,
    required this.deepColor,
    required this.badgeLabel,
    this.badgeIcon,
    this.subtitle = 'SR Management System',
  });

  @override
  State<BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<BrandPanel>
    with SingleTickerProviderStateMixin {
  /// The asset, read once and cached for the process. Every sign-in screen
  /// mounts one of these, and re-reading it per screen is wasted work.
  static Future<String>? _source;

  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // ⚠️ Slow on purpose. This sits behind a password field, and a background
    // that moves quickly enough to notice is a background that competes with
    // the thing the person came here to do. Nine seconds a cycle reads as
    // light shifting rather than as an animation playing.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
    _source ??= rootBundle.loadString('Sri_Lanka_Customs_logo_tinted.svg');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// The colour behind the crest at animation position [t].
  ///
  /// The crest sits at the middle of the panel, so what is behind it is the
  /// gradient's middle -- which is [AppColors.primaryNavy] leaning towards the
  /// accent by however much the animation has pulled it.
  Color _behindCrest(BuildContext context, double t) {
    // A small lean, not a wash: at full strength the accent would tint the
    // whole middle of the panel and the crest would lose its contrast.
    //
    // ⚠️ Scaled by how BRIGHT the accent is, for the same reason
    // [_accentDepth] is. Gold leans much harder than teal at the same factor.
    return Color.lerp(context.colors.primaryNavy, widget.accent,
        0.10 * t * _accentDepth)!;
  }

  /// How far the accent corner is pulled back towards the deep colour.
  ///
  /// ⚠️ NOT a constant, which is what made the two GOLD portals look
  /// wrong beside the others.
  ///
  /// The panels all mixed the accent with the deep colour by a fixed 0.35, so
  /// how bright the corner ended up was entirely the accent's own brightness
  /// -- and gold is far brighter than the rest. Relative luminance, on the
  /// live palette:
  ///
  ///     gold   #D4A017  0.392      <- both gold portals
  ///     teal   #0E7C86  0.162
  ///     green  #2E7D32  0.155
  ///     maroon #9E2A54  0.096
  ///     purple #7B1FA2  0.078
  ///
  /// Gold is 2.4x the next brightest and 5x the dimmest, so at one factor its
  /// corner reads as a lamp while purple's reads as a tint.
  ///
  /// Pulling the mix in proportion to luminance evens that out: a bright
  /// accent is taken further back, a dark one is left nearly as it was. The
  /// numbers below hold the DIM end where it already looked right -- 0.35 at
  /// luminance 0.08 -- and take gold to about 0.62.
  ///
  /// This is a correction for BRIGHTNESS, not for hue: it says nothing about
  /// which colour a portal uses, only how much light it throws.
  double get _accentDepth {
    // 0.08 -> 1.0 (unchanged), 0.40 -> ~1.8. Clamped so a future accent
    // brighter than gold cannot wash the corner out entirely, and a black one
    // cannot make it brighter than it was.
    return (1.0 + (_accentLuminance - 0.08) * 2.5).clamp(1.0, 1.8);
  }

  /// How far a bright accent is held back even at the peak of the cycle.
  ///
  /// ⚠️ Zero for the dim accents, so the four portals that already
  /// looked right are untouched. Gold gets about 0.25, which is what stops its
  /// corner reaching pure #D4A017 -- the state the two gold panels were being
  /// judged on.
  double get _accentFloor =>
      ((_accentLuminance - 0.17) * 0.9).clamp(0.0, 0.28);

  /// Relative luminance of the accent, sRGB (WCAG).
  ///
  /// The channel weights are what make this about PERCEIVED brightness rather
  /// than raw numbers -- green counts for roughly ten times what blue does,
  /// which is why teal and green land together despite looking nothing alike.
  double get _accentLuminance {
    double channel(double c) =>
        c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(widget.accent.r) +
        0.7152 * channel(widget.accent.g) +
        0.0722 * channel(widget.accent.b);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Eased, so the turn at each end is soft rather than a bounce off a
        // wall -- the giveaway that something is on a loop.
        final t = Curves.easeInOut.transform(_c.value);
        final behind = _behindCrest(context, t);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.deepColor,
                behind,
                // The accent corner brightens and dims. This is the movement
                // the eye actually reads.
                //
                // ⚠️ Towards the DEEP colour, not towards transparency. Fading
                // the accent's alpha leaves its red, green and blue untouched,
                // so on an opaque panel the only thing that changes is how
                // much of the widget behind shows through -- which here is
                // nothing. It looked static. Mixing in the deep colour is a
                // real change of colour.
                // ⚠️ A FLOOR as well as a swing. `(1 - t)` reaches zero
                // at the top of the cycle, which means the corner hits the
                // pure accent -- and pure gold there is the brightest thing on
                // any of the six panels. The floor is what a bright accent is
                // held back BY; the swing is the movement on top of it.
                Color.lerp(
                    accent,
                    widget.deepColor,
                    (_accentFloor + 0.35 * _accentDepth * (1 - t))
                        .clamp(0.0, 0.75))!,
              ],
              // ⚠️ The stops travel too, which is what makes this look like
              // light moving across the panel rather than a colour fading in
              // place. Kept well apart so no two ever cross.
              stops: [0.0, 0.42 + 0.10 * t, 1.0],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Crest(source: _source!, tint: accent, knockout: behind),
              const SizedBox(height: 36),
              Text('Sri Lanka Customs',
                  style: TextStyle(
                      color: accent,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
              Text(widget.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFFB0BEC5), fontSize: 16, height: 1.2)),
              const SizedBox(height: 28),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: accent.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(24),
                  color: accent.withOpacity(0.06),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.badgeIcon != null) ...[
                    Icon(widget.badgeIcon, color: accent, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Text(widget.badgeLabel,
                      style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The crest, with its knockout repainted to whatever is behind it.
class _Crest extends StatelessWidget {
  final Future<String> source;
  final Color tint;
  final Color knockout;

  const _Crest(
      {required this.source, required this.tint, required this.knockout});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: source,
      builder: (context, snap) {
        if (!snap.hasData) {
          // ⚠️ Reserve the space. Without this the title and badge jump up
          // while the asset loads, which is more noticeable than the crest
          // arriving a frame late.
          return const SizedBox(width: 200, height: 200);
        }
        final svg = crestWithKnockout(snap.data!, knockout);
        return SvgPicture.string(
          svg,
          width: 200,
          height: 200,
          theme: SvgTheme(currentColor: tint),
        );
      },
    );
  }
}
