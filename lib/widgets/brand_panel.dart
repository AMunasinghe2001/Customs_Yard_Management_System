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

  /// How far the accent is held back even at the peak of the cycle.
  ///
  /// ⚠️ A BASE for every portal, plus more for a bright one.
  ///
  /// The panels are wallpaper behind a sign-in form, and none of them should
  /// reach its pure accent -- a corner of undiluted colour is what makes the
  /// gradient read as a shape rather than as light. 0.22 for every portal is
  /// the base; gold's extra 0.25 on top of it is what stops #D4A017 arriving
  /// at full strength, which is the state the two gold panels were being
  /// judged on.
  double get _accentFloor =>
      (0.22 + ((_accentLuminance - 0.17) * 0.9).clamp(0.0, 0.28))
          .clamp(0.0, 0.55);

  /// The colour at the accent corner, at animation position [t].
  ///
  /// ⚠️ Never the pure accent. A corner of undiluted colour is what
  /// makes a gradient read as a shape rather than as light -- and on gold,
  /// which is far brighter than the other five accents, it is the state the
  /// panel was being judged on.
  Color _corner(Color accent, [double t = 1.0]) => Color.lerp(
      accent,
      widget.deepColor,
      (_accentFloor + 0.35 * _accentDepth * (1 - t)).clamp(0.0, 0.75))!;

  /// The colour the crest, the title and the badge are drawn in.
  ///
  /// ⚠️ The accent, UNLESS the accent cannot be read on this panel.
  ///
  /// Every portal drew its branding in its own accent, which works while the
  /// accent is lighter than the panel behind it. Yard Access is #1A237E on
  /// #060D1F -- a contrast ratio of 1.46 -- and its crest and title all but
  /// disappeared. Measured against each panel's deep colour:
  ///
  ///     gold   #D4A017  8.15    Valuation, DC/SDDC
  ///     teal   #0E7C86  3.91    Top Management
  ///     green  #2E7D32  3.77    Central Disposal
  ///     maroon #8E3A5F  2.69    ICT
  ///     purple #7B1FA2  2.36    Appeal
  ///     navy   #1A237E  1.46    Yard Access   <- unreadable
  ///     white  #FFFFFF  19.4
  ///
  /// Below 1.9 the accent is dropped for white, which no panel can swallow.
  ///
  /// ⚠️ The threshold sits in the GAP, not next to a value. Yard
  /// Access is 1.46 and the dimmest of the others is Appeal at 2.29 -- a wide
  /// space with nothing in it, so 1.9 separates them without sitting close
  /// enough to either that a small palette change would flip a panel. Picking
  /// 2.2 would have left purple 0.09 from turning white, and a designer
  /// nudging that swatch would have restyled a portal by accident.
  ///
  /// The five that read correctly keep their own colour, because the branding
  /// being IN the portal's colour is the point of it. This is a floor, not a
  /// restyle.
  ///
  /// The panel keeps its accent either way -- the gradient corner, the badge
  /// fill and its border still carry it. Only the marks that have to be
  /// legible change.
  Color get _ink {
    final deep = _relativeLuminance(widget.deepColor);
    final accent = _accentLuminance;
    final contrast =
        (math.max(deep, accent) + 0.05) / (math.min(deep, accent) + 0.05);
    return contrast < 1.9 ? Colors.white : widget.accent;
  }

  /// Relative luminance of the accent, sRGB (WCAG).
  ///
  /// The channel weights are what make this about PERCEIVED brightness rather
  /// than raw numbers -- green counts for roughly ten times what blue does,
  /// which is why teal and green land together despite looking nothing alike.
  double get _accentLuminance => _relativeLuminance(widget.accent);

  /// Relative luminance of any colour, sRGB (WCAG).
  static double _relativeLuminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final ink = _ink;
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
              // ⚠️ SIX stops, EVENLY spaced. Both halves of that matter,
              // and the second half is the one that is easy to get wrong.
              //
              // The panel used three stops at 0.0, ~0.47 and 1.0, so the whole
              // colour change happened across the second half in one straight
              // line. On the dim portals that reads as a wash; on gold, where
              // the ends are far apart in brightness, the eye picks the ramp
              // out as an EDGE running across the panel.
              //
              // Adding stops is not enough on its own. Measured on the gold
              // panel -- biggest brightness step along the ramp divided by the
              // average step, where 1.0 would be perfectly even:
              //
              //     3 stops (before)            3.53
              //     5 stops, flat first third   6.15   <- worse
              //     4 stops                     3.95
              //     5 stops, even               2.77
              //     6 stops, even               2.16   <- this
              //     7 stops, even               2.95
              //
              // Holding the first third flat and then turning made it WORSE:
              // the same change squeezed into less room. Even spacing is what
              // removes the edge.
              colors: [
                widget.deepColor,
                Color.lerp(widget.deepColor, behind, 0.45)!,
                behind,
                Color.lerp(behind, _corner(accent), 0.38)!,
                Color.lerp(behind, _corner(accent), 0.72)!,
                // The corner itself. It brightens and dims, and this is the
                // movement the eye actually reads.
                _corner(accent, t),
              ],
              // ⚠️ The stops travel as one, which is what makes this look
              // like light MOVING across the panel rather than a colour fading
              // in place. Shifted together so the even spacing -- the thing
              // that removes the band -- is preserved at every moment.
              stops: [
                for (var i = 0; i < 6; i++) (i / 5) * (1 - 0.06 * t) + 0.06 * t,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ⚠️ Tinted with the INK, not the accent: on Yard Access
              // the accent is #1A237E on a #060D1F panel and the crest all but
              // disappeared. The knockout stays the colour actually BEHIND the
              // crest -- that is what keeps the ship and the plane looking
              // cut out, and it has nothing to do with the tint.
              _Crest(source: _source!, tint: ink, knockout: behind),
              const SizedBox(height: 36),
              Text('Sri Lanka Customs',
                  style: TextStyle(
                      color: ink,
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
                  // The badge keeps the ACCENT in its border and fill --
                  // this is where the portal's colour belongs, and neither is
                  // asked to be legible.
                  border: Border.all(color: accent.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(24),
                  color: accent.withOpacity(0.06),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.badgeIcon != null) ...[
                    Icon(widget.badgeIcon, color: ink, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Text(widget.badgeLabel,
                      style: TextStyle(
                          color: ink,
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
