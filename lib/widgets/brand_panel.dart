import 'dart:async';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

/// The colour the crest's ship and plane are painted in the shipped asset.
///
/// Public so a test can assert the swap actually happened, rather than trusting
/// that a colour handed correctly around the widget tree reached the SVG.
const String kCrestKnockoutHex = '#1a1764';

/// The ground every brand panel is built on.
///
/// ⚠️ ONE value for every portal, and a NEUTRAL one. The panels used to pick
/// their own near-black, and each was tinted towards its own team colour —
/// green-black for Disposal, navy for Valuation and Top Management, a second
/// navy for Yard Access. That put the team colour into the ground itself, so
/// the panels did not read as the same surface and the accent had nothing
/// neutral to be light against.
///
/// Not pure `#000000`: an absolute black takes no shading, so the gradient's
/// first third would be a dead flat patch and the orbs would have no ground to
/// fall off into. `#050505` is black to the eye and still has somewhere to go.
const Color kBrandPanelBlack = Color(0xFF050505);

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

  /// The darkest corner, top-left.
  ///
  /// ⚠️ Defaults to [kBrandPanelBlack] and every portal now takes that
  /// default. It used to be per-portal, and that was the bug: the five values
  /// in use were TINTED near-blacks, so the ground itself carried the team
  /// colour. Disposal's `#051A0F` is green-black, Valuation's `#0A0F2C` is
  /// navy, Yard Access had a third navy — side by side the panels looked like
  /// different surfaces rather than one surface lit six ways.
  ///
  /// Black is the base for all of them now, and the accent arrives only as
  /// the light moving over it. Still a parameter rather than a constant so a
  /// panel that genuinely needs another ground can say so, but nothing in the
  /// app passes one.
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
    this.deepColor = kBrandPanelBlack,
    required this.badgeLabel,
    this.badgeIcon,
    this.subtitle = 'SR Management System',
  });

  @override
  State<BrandPanel> createState() => _BrandPanelState();
}

class _BrandPanelState extends State<BrandPanel> with TickerProviderStateMixin {
  /// The asset, read once and cached for the process. Every sign-in screen
  /// mounts one of these, and re-reading it per screen is wasted work.
  static Future<String>? _source;

  late final AnimationController _c;

  /// A SECOND, slower cycle for the halo behind the crest.
  ///
  /// ⚠️ Deliberately not the same controller, and deliberately not a
  /// multiple of its period. Two movements on one clock read as a single
  /// pulse — the panel would breathe in and out as one object, which is the
  /// thing that draws the eye away from the form. At 9s and 14s the two
  /// drift in and out of phase over roughly two minutes and never repeat a
  /// pattern anyone can follow.
  late final AnimationController _glow;

  /// The orb field's own clock — the slowest of the three, and the only one
  /// that does NOT reverse.
  ///
  /// ⚠️ Reversing would send the orbs back along the path they just took,
  /// which the eye reads as a rewind. They travel on sine and cosine of this
  /// value instead, so the loop closes on itself and there is nothing to
  /// catch: at t=1 every orb is exactly where it was at t=0.
  late final AnimationController _orbs;

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
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
    // No `reverse`: the path is a closed loop, so it never snaps.
    _orbs = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    _source ??= rootBundle.loadString('Sri_Lanka_Customs_logo_tinted.svg');
  }

  @override
  void dispose() {
    _c.dispose();
    _glow.dispose();
    _orbs.dispose();
    super.dispose();
  }

  /// The colour behind the crest at animation position [t].
  ///
  /// The crest sits at the middle of the panel, so what is behind it is the
  /// gradient's middle.
  ///
  /// ⚠️ Built from [kBrandPanelBlack] and the panel's accent — nothing else.
  ///
  /// Two earlier versions of this got it wrong in the same way, by mixing in a
  /// colour that had nothing to do with this panel. First it returned a fixed
  /// `#1A1764`, so on a portal whose middle was `#0A0F2C` the ship and plane
  /// were painted a navy that matched nothing behind them and showed as two
  /// solid patches. Then it lifted the deep colour 35% towards `primaryNavy`,
  /// which matched the crest again but put navy into the middle of every
  /// panel — including the green one.
  ///
  /// The knockout only works while this returns *exactly* what the gradient
  /// paints at the centre, so the two are now derived from the same two
  /// values and no third colour is involved.
  ///
  /// ⚠️ The orbs are kept OFF the centre (see [_OrbFieldPainter]) so this
  /// stays true: a disc of light drifting behind the crest would change the
  /// colour there frame by frame, and no single value could match it.
  Color _behindCrest(double t) {
    // A small lean, not a wash: at full strength the accent would tint the
    // whole middle of the panel and the crest would lose its contrast.
    //
    // ⚠️ Scaled by how BRIGHT the accent is, for the same reason
    // [_accentDepth] is. Gold leans much harder than teal at the same factor.
    // ⚠️ The 0.35 lift towards `primaryNavy` is GONE. It was the second
    // source of the tint: whatever ground a panel was given, this pulled its
    // middle a third of the way to navy, so the green panel's centre was
    // green-navy and the crest sat on a different colour on every portal.
    // The lift is now towards the panel's OWN accent only, which is the one
    // colour that is supposed to differ between portals.
    //
    // Raised 0.10 → 0.16 because the lift now starts from black rather than
    // from a navy-mixed colour, and without it the middle is too dark for the
    // crest's knockout to read as a hole rather than as a black patch.
    //
    // ⚠️ The accent lean is much smaller (0.16 → 0.04). The orb pool
    // underneath is opaque black at the centre now, so a strong lean was
    // describing a colour that is no longer there — and this is the ONE
    // value that has to be right, because the ship and the plane are painted
    // with it. Overstate it and the two shapes read as gold patches on a
    // black disc, which is the exact failure the knockout exists to prevent.
    //
    // ⚠️ NOT zero, and not constant in `t`. A fixed colour here would freeze
    // the gradient's middle stops with it — this value is the ramp's middle
    // as well as the knockout — and the panel would stop moving altogether.
    // Small and still travelling keeps the holes honest AND keeps the light
    // alive; [_knockoutColor] is what the crest is actually painted with.
    final mid = Color.lerp(
        widget.deepColor, Colors.white, 0.06 * (1.8 - _accentDepth * 0.4))!;
    return Color.lerp(mid, widget.accent, 0.04 * t * _accentDepth)!;
  }

  /// The colour the crest's ship and plane are actually painted.
  ///
  /// ⚠️ Separate from [_behindCrest], and CONSTANT. Those two shapes are not
  /// transparent; they are filled with the colour expected behind them, so
  /// they read as holes only while that colour is what is really there.
  ///
  /// The orb pool is opaque `deepColor` under the crest now, so what is
  /// really there is the deep colour — no accent, no drift. It used to be
  /// [_behindCrest], which travels, and the knockout had to chase it frame by
  /// frame; the shapes were exact only at the moments the chase kept up.
  ///
  /// [_behindCrest] still moves, because it is also the gradient's middle
  /// stop and freezing it would stop the panel animating. Only the value the
  /// crest is painted with is pinned here.
  Color get _knockoutColor => Color.lerp(
      widget.deepColor, Colors.white, 0.06 * (1.8 - _accentDepth * 0.4))!;

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
  ///
  /// ⚠️ Raised again once the ORBS started carrying the light. The corner and
  /// the orbs are now two sources of the same colour on one panel, and on
  /// gold — much the brightest accent — the two together read as a yellow
  /// wash rather than as light on a dark ground. The base goes 0.22 → 0.34
  /// and gold's extra 0.28 → 0.34, so gold is held back roughly two-thirds of
  /// the way to its deep colour while the dim accents barely move.
  ///
  /// ⚠️ Raised a THIRD time, on the gold sign-in panels: "too much yellow,
  /// it needs more black". Measured, the previous values put gold's corner at
  /// 0.584 of the way to the deep colour, luminance 0.066.
  ///
  /// ⚠️ The BRIGHTNESS TERM carries the raise, not the base. Raising the base
  /// moves every portal equally, and the first attempt at this took navy's
  /// corner from 0.0148 down to 0.0110 — a panel nobody complained about,
  /// pushed towards flat black. Only the second term is luminance-scaled, so
  /// widening it (1.1 → 2.0, cap 0.34 → 0.52) leaves the five dim accents
  /// exactly where they were and moves gold alone.
  ///
  /// Gold's corner goes 0.584 → 0.706 and its luminance 0.066 → 0.035: about
  /// half as much light in the gold corner, which is the "more black" that
  /// was asked for. The trailing clamp rises 0.70 → 0.82 because at 0.70 it,
  /// not the formula, would have been the limit.
  double get _accentFloor =>
      (0.34 + ((_accentLuminance - 0.17) * 2.0).clamp(0.0, 0.52))
          .clamp(0.0, 0.82);

  /// The colour at the accent corner, at animation position [t].
  ///
  /// ⚠️ Never the pure accent. A corner of undiluted colour is what
  /// makes a gradient read as a shape rather than as light -- and on gold,
  /// which is far brighter than the other five accents, it is the state the
  /// panel was being judged on.
  /// ⚠️ The trailing clamp is the REAL ceiling, and it has to move with the
  /// floor. At 0.75 it sat below gold's new 0.70 floor plus anything `t`
  /// adds, so the corner would have stopped darkening partway through the
  /// cycle and the raise would have been half-applied.
  Color _corner(Color accent, [double t = 1.0]) => Color.lerp(
      accent,
      widget.deepColor,
      (_accentFloor + 0.35 * _accentDepth * (1 - t)).clamp(0.0, 0.88))!;

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
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
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
        final behind = _behindCrest(t);

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
              // ⚠️ Pulled towards the deep colour now that the ORBS carry the
              // light. Before, the gradient was the only thing moving, so it
              // had to do the work; two bright layers over each other just
              // muddied both, and the orbs had nothing dark to read against.
              // The ramp is now the ground and the orbs are the light on it.
              colors: [
                widget.deepColor,
                Color.lerp(widget.deepColor, behind, 0.50)!,
                // ⚠️ `behind` ITSELF, unmixed. This is the colour the crest's
                // knockout is painted with, and the crest sits at the middle
                // of the panel — if this stop is a blend of it rather than
                // the value itself, the ship and plane no longer match what
                // is actually behind them.
                behind,
                // ⚠️ The accent is confined to the LAST THIRD of the ramp.
                //
                // At 0.22 and 0.46 these two stops were already carrying most
                // of the accent, so the colour reached the middle of the
                // panel and the crest sat on gold rather than on the deep
                // colour. Held near `behind`, the accent only appears where
                // the gradient is genuinely at its corner.
                Color.lerp(behind, _corner(accent), 0.08)!,
                Color.lerp(behind, _corner(accent), 0.24)!,
                // The corner itself, held further back than it used to be —
                // the orbs are the movement the eye reads now, and a bright
                // corner competing with them is what made the old panel
                // read as a flat coloured wash.
                Color.lerp(widget.deepColor, _corner(accent, t), 0.58)!,
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
          // ⚠️ The ORBS are what the movement actually is now.
          //
          // The gradient beneath them still shifts, but a slow six-stop ramp
          // over near-black is a change nobody can see — which is exactly the
          // complaint. Three soft discs of light drifting across the panel
          // give the eye something with a SHAPE to follow, while staying far
          // enough down in brightness to sit behind a password field.
          //
          // Painted, not stacked as widgets: three blurred circles are one
          // canvas operation each, where three Containers with box shadows
          // would each allocate a layer and composite it every frame.
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _OrbFieldPainter(
                      t: _orbs.value,
                      accent: accent,
                      deep: widget.deepColor,
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ⚠️ Tinted with the INK, not the accent: on Yard Access
                    // the accent is #1A237E on a #060D1F panel and the crest all but
                    // disappeared. The knockout stays the colour actually BEHIND the
                    // crest -- that is what keeps the ship and the plane looking
                    // cut out, and it has nothing to do with the tint.
                    // ⚠️ The halo is painted BEHIND the crest, never over it.
                    //
                    // The crest's ship and plane are fake holes: they are filled
                    // with whatever colour is behind them. Anything drawn on TOP
                    // would tint the disc and the two shapes differently, and they
                    // would stop reading as holes — the one thing this widget
                    // exists to protect. Sitting underneath, the halo lights the
                    // crest without touching the trick.
                    _HaloedCrest(
                      source: _source!,
                      tint: ink,
                      // ⚠️ Not `behind`: that travels, and the crest must be
                      // painted the colour the pool actually puts there.
                      knockout: _knockoutColor,
                      accent: accent,
                      glow: _glow,
                    ),
                    const SizedBox(height: 34),
                    Text('Sri Lanka Customs',
                        style: TextStyle(
                            color: ink,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 2),
                    Text(widget.subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFB0BEC5),
                            fontSize: 16,
                            height: 1.2)),
                    const SizedBox(height: 22),
                    // A hairline above the portal badge: it separates the service's
                    // name from the door being used, which are two different
                    // things that were previously stacked with nothing between.
                    Container(
                      width: 54,
                      height: 1,
                      color: ink.withOpacity(0.28),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 10),
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
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The crest with a slow halo behind it.
///
/// ⚠️ The halo is UNDER the crest, and that is not a layout preference.
/// The ship and the plane are painted with the background colour to fake a
/// transparent hole; anything drawn on top would tint the disc and those two
/// shapes by different amounts and they would stop looking cut out. Beneath,
/// the glow lights the crest and leaves the trick intact.
class _HaloedCrest extends StatelessWidget {
  final Future<String> source;
  final Color tint;
  final Color knockout;
  final Color accent;
  final Animation<double> glow;

  const _HaloedCrest({
    required this.source,
    required this.tint,
    required this.knockout,
    required this.accent,
    required this.glow,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glow,
      builder: (context, child) {
        // Eased, so the halo swells and settles rather than ticking between
        // two sizes.
        final g = Curves.easeInOut.transform(glow.value);
        return SizedBox(
          width: 310,
          height: 310,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ⚠️ Opacity, not size. A halo that GROWS reads as something
              // approaching and pulls the eye; one that only brightens reads
              // as light changing, which is what a background should do
              // behind a password field.
              Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withOpacity(0.13 + 0.09 * g),
                      accent.withOpacity(0.05 + 0.04 * g),
                      accent.withOpacity(0.0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      // ⚠️ Passed as `child` so the HALO's own frames do not rebuild it.
      //
      // The crest still rebuilds when the gradient moves — it has to, since
      // the knockout tracks the colour behind it — but the two animations
      // run on separate clocks, and without this the slower halo would drag
      // an SVG string-replace and re-parse along with every one of its
      // frames as well.
      child: _Crest(source: source, tint: tint, knockout: knockout),
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
          return const SizedBox(width: 240, height: 240);
        }
        final svg = crestWithKnockout(snap.data!, knockout);
        return SvgPicture.string(
          svg,
          width: 240,
          height: 240,
          theme: SvgTheme(currentColor: tint),
        );
      },
    );
  }
}

/// Three soft discs of light drifting over the panel's near-black.
///
/// ⚠️ This is the movement the panel actually has. The gradient under it
/// still shifts, but a slow six-stop ramp between two near-blacks is a change
/// nobody can see — the eye needs something with a SHAPE to follow before it
/// registers as motion at all.
///
/// Painted rather than stacked as widgets: each orb is one `drawCircle` with a
/// blur, where a Container with a box-shadow would allocate its own layer and
/// composite it on every frame.
class _OrbFieldPainter extends CustomPainter {
  /// 0..1, looping. Never reversed — see [_BrandPanelState._orbs].
  final double t;
  final Color accent;
  final Color deep;

  const _OrbFieldPainter({
    required this.t,
    required this.accent,
    required this.deep,
  });

  /// Each orb: where its ellipse is centred, how big it is, how far it
  /// travels, how bright it gets, and how far around its own loop it starts.
  ///
  /// ⚠️ The three periods are 1, 0.61 and 1.37 — deliberately not whole
  /// multiples of each other. On matching periods the three would return to
  /// the same arrangement every cycle and the panel would visibly repeat;
  /// like this the pattern takes several minutes to come round.
  /// ⚠️ All three are kept AWAY from the middle, where the crest sits.
  ///
  /// The crest's ship and plane are painted with the colour expected behind
  /// them (`_behindCrest`). A disc of light drifting across that spot would
  /// change the real colour there frame by frame, no single value could match
  /// it, and the two shapes would show as patches on the crest — the exact
  /// failure the knockout exists to prevent. Their centres and their travel
  /// both stay out towards the corners.
  ///
  /// ⚠️ SMALLER than they look they should be. At r = 0.5..0.62 of the panel
  /// a disc centred at (0.18, 0.16) still reaches well past the middle, so
  /// three of them covered the whole panel and the accent stopped reading as
  /// light in the corners — it became the panel's colour. Pushed into the
  /// corners and cut to roughly a third, they light the edges and leave the
  /// crest on the deep colour, which is what the mark needs behind it.
  static const _orbs = <_Orb>[
    _Orb(
        cx: 0.08,
        cy: 0.06,
        r: 0.34,
        dx: 0.07,
        dy: 0.05,
        a: 0.30,
        speed: 1.00,
        phase: 0.0),
    _Orb(
        cx: 0.94,
        cy: 0.84,
        r: 0.32,
        dx: 0.06,
        dy: 0.07,
        a: 0.26,
        speed: 0.61,
        phase: 2.1),
    _Orb(
        cx: 0.06,
        cy: 0.97,
        r: 0.28,
        dx: 0.05,
        dy: 0.05,
        a: 0.18,
        speed: 1.37,
        phase: 4.3),
  ];

  /// How far every orb is dimmed, by how BRIGHT this portal's accent is.
  ///
  /// ⚠️ One opacity for six accents was wrong for the same reason
  /// `_accentDepth` exists. Gold (#D4A017) has roughly 2.4x the relative
  /// luminance of the next brightest and 5x the dimmest, so at a shared
  /// alpha its orbs read as lamps while purple's read as a tint — and the
  /// banding, which is a function of how much light is being ramped, showed
  /// on gold alone.
  ///
  /// Takes gold to about 0.55 of its old strength and leaves the dim accents
  /// nearly untouched.
  ///
  /// ⚠️ Trimmed further with the gradient corner, for the same report. The
  /// corner and the orbs are the two sources of gold on the panel; darkening
  /// only the corner would leave the orbs as the brightest thing on it and
  /// simply move the yellow rather than reduce it.
  ///
  /// ⚠️ The SLOPE, not the floor. Gold computes to ~0.548 here, a hair under
  /// the old 0.55 floor — so it was never actually pinned by it, and dropping
  /// that floor changed gold by 0.002. Steepening the slope 1.45 → 2.05 is
  /// what moves it: gold lands at ~0.36 while the dim accents, whose
  /// luminance is close to the 0.08 pivot, stay near 1.0.
  double get _brightnessTrim {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final l = 0.2126 * channel(accent.r) +
        0.7152 * channel(accent.g) +
        0.0722 * channel(accent.b);
    // ⚠️ Eased back 2.05 → 1.70 once the crest pool went opaque. The trim was
    // steepened to stop gold reaching the middle of the panel; the pool now
    // does that job properly and at the centre, so holding the orbs this far
    // down as well left the corners flat and took the movement with them.
    // The brief asks for black around the mark AND a soft moving colour
    // around that — the pool is the first half, these are the second.
    return (1.0 - (l - 0.08) * 1.70).clamp(0.30, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // The orbs are light ON the panel, so they are drawn additively over
    // whatever the gradient put down rather than blended with it.
    final shortest = size.shortestSide;
    final trim = _brightnessTrim;

    // ⚠️ A real blur over the whole field, on top of the softened falloff.
    //
    // The eight-stop ramp removed the hard rings, but a gradient still
    // quantises to the display's 256 levels per channel and on gold — the
    // brightest accent, so the widest ramp — the remaining steps read as
    // faint contour lines drifting across the panel. A blur of a few pixels
    // smears each step across its neighbours, which is what actually removes
    // them rather than making them finer.
    //
    // One saveLayer for all three orbs, not one each: the filter is the
    // expensive part, and it is the same filter.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
    );
    for (final o in _orbs) {
      final angle = (t * o.speed) * 2 * math.pi + o.phase;
      final cx = (o.cx + math.cos(angle) * o.dx) * size.width;
      final cy = (o.cy + math.sin(angle) * o.dy) * size.height;
      final radius = o.r * shortest;

      // ⚠️ A RADIAL gradient, not a blurred solid circle. A blur of this
      // size (hundreds of logical pixels) is an expensive filter to run every
      // frame on a panel that is half the window; a shader gives the same
      // soft edge for the cost of a fill.
      //
      // ⚠️ EIGHT stops on a squared falloff, not three on a straight line.
      //
      // Three stops made the alpha fall in two straight segments, and on a
      // near-black panel the eye picks the join out as a RING — the banding
      // that made the old field look like stripes running across the panel.
      // The display has only 256 levels per channel to spend, and a linear
      // ramp spends them evenly, so the wide dim outer half gets far too few
      // and each one covers enough pixels to be seen as an edge.
      //
      // `(1-x)^2` concentrates the change near the centre and leaves the
      // outer edge almost flat, which is both how light actually falls off
      // and where the banding was worst.
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
      const steps = 8;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            for (var i = 0; i < steps; i++)
              accent.withOpacity(o.a * trim * math.pow(1 - i / (steps - 1), 2)),
          ],
          stops: [for (var i = 0; i < steps; i++) i / (steps - 1)],
        ).createShader(rect);
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
    canvas.restore();

    // ⚠️ THE CONSTELLATION, drawn over the glow and UNDER the pool.
    //
    // The orbs alone were a soft wash with nothing to look at -- asked for
    // a design with some shape to it, on black and the team colour. A
    // network of nodes and the links between them is the one that means
    // something here: consignments moving between points is what this
    // system is a record of.
    //
    // ⚠️ Under the pool, never over it. The pool is what guarantees black
    // behind the crest, and a node drawn on top of it would put the accent
    // straight back where the ship and the plane have to read as holes.
    _paintConstellation(canvas, size, shortest, trim);

    // ⚠️ A pool of the DEEP colour over the middle, painted last.
    //
    // Keeping the orbs out at the corners is not enough on its own: they are
    // blurred by 18px and fade over hundreds more, so their light still
    // reaches the centre and the crest ends up sitting on the accent. The
    // mark needs dark behind it — both because that is what the crest is
    // drawn for, and because the ship and plane are painted with a single
    // expected colour (`_behindCrest`) that cannot track a drifting tint.
    //
    // Transparent at the rim, so it darkens the middle without drawing an
    // edge of its own.
    //
    // ⚠️ IT IS BLACK THAT SPREADS FROM THE LOGO, NOT GOLD — given directly,
    // and the reason is the crest itself: the ship and the plane are not
    // transparent. They are painted the colour expected behind them (see
    // [crestWithKnockout]), so they only read as holes while that colour is
    // what is actually there. Any accent reaching the middle turns the two
    // shapes into gold stickers on a gold disc.
    //
    // So the pool is now opaque at its centre (0.82 → 1.0) and reaches
    // further out (0.72 → 0.95 of the shorter side), with a gentler falloff
    // (1.6 → 1.35) so the black fades into the accent over a long distance
    // instead of ending in a visible ring. The colour lives out at the edges
    // of the panel, where the orbs and the gradient corner still carry it.
    final centre = Offset(size.width * 0.5, size.height * 0.42);
    final vignetteRadius = shortest * 0.95;
    final vignette = Rect.fromCircle(center: centre, radius: vignetteRadius);
    // ⚠️ More stops than before. The pool is deeper AND wider now, so it
    // ramps through more levels — at 7 stops the extra distance showed the
    // same contour banding the orbs needed eight stops to cure.
    const vSteps = 11;
    canvas.drawCircle(
      centre,
      vignetteRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            for (var i = 0; i < vSteps; i++)
              deep.withOpacity(1.0 * math.pow(1 - i / (vSteps - 1), 1.35)),
          ],
          stops: [for (var i = 0; i < vSteps; i++) i / (vSteps - 1)],
        ).createShader(vignette),
    );
  }

  /// The constellation's nodes, as fractions of the panel.
  ///
  /// ⚠️ NONE of them in the middle, for the same reason the orbs are not:
  /// the crest's ship and plane are painted the colour expected behind them,
  /// so anything drifting across that spot breaks the knockout. The centre
  /// of the panel is a hole in this layer too -- [_centreFade] enforces it
  /// per-node rather than trusting the table, so a later edit cannot quietly
  /// move one inward.
  ///
  /// ⚠️ Irrational-ish speeds again (see [_orbs]). Whole multiples would
  /// bring the whole figure back to the same arrangement every cycle, and a
  /// repeating background is exactly what the eye starts watching.
  static const _nodes = <_Node>[
    _Node(x: 0.13, y: 0.10, r: 2.2, dx: 0.035, dy: 0.028, speed: 1.00, phase: 0.0),
    _Node(x: 0.30, y: 0.06, r: 1.6, dx: 0.026, dy: 0.034, speed: 0.72, phase: 1.3),
    _Node(x: 0.06, y: 0.27, r: 1.9, dx: 0.030, dy: 0.024, speed: 1.23, phase: 2.6),
    _Node(x: 0.25, y: 0.30, r: 1.4, dx: 0.022, dy: 0.030, speed: 0.61, phase: 4.0),
    _Node(x: 0.88, y: 0.14, r: 2.0, dx: 0.032, dy: 0.026, speed: 0.87, phase: 0.8),
    _Node(x: 0.72, y: 0.28, r: 1.5, dx: 0.024, dy: 0.032, speed: 1.37, phase: 3.1),
    _Node(x: 0.94, y: 0.38, r: 1.7, dx: 0.028, dy: 0.022, speed: 0.66, phase: 5.2),
    _Node(x: 0.10, y: 0.72, r: 2.1, dx: 0.034, dy: 0.027, speed: 0.93, phase: 1.9),
    _Node(x: 0.28, y: 0.88, r: 1.5, dx: 0.025, dy: 0.031, speed: 1.16, phase: 4.7),
    _Node(x: 0.07, y: 0.93, r: 1.8, dx: 0.029, dy: 0.023, speed: 0.78, phase: 2.2),
    _Node(x: 0.86, y: 0.74, r: 2.0, dx: 0.031, dy: 0.029, speed: 1.08, phase: 0.4),
    _Node(x: 0.68, y: 0.91, r: 1.6, dx: 0.027, dy: 0.025, speed: 0.69, phase: 3.6),
    _Node(x: 0.95, y: 0.92, r: 1.4, dx: 0.023, dy: 0.033, speed: 1.29, phase: 5.8),
  ];

  /// How much of the constellation survives at a point, by how close it is
  /// to the crest.
  ///
  /// ⚠️ Enforced in the PAINTER, not in the table. The node list above
  /// keeps clear of the middle by hand, but the nodes drift and the links
  /// span between them, so a link can cross the centre even when both its
  /// ends are well outside it. This fades both to nothing across the crest's
  /// zone, so the black pool never has to clean up after this layer.
  static double _centreFade(Offset p, Size size, double shortest) {
    final centre = Offset(size.width * 0.5, size.height * 0.42);
    final d = (p - centre).distance / shortest;
    // Fully clear inside the crest, full strength once well past it.
    const inner = 0.34, outer = 0.62;
    if (d <= inner) return 0.0;
    if (d >= outer) return 1.0;
    final u = (d - inner) / (outer - inner);
    // Smoothstep, so there is no edge where the fade begins or ends.
    return u * u * (3 - 2 * u);
  }

  /// Nodes joined to their near neighbours, drifting on closed loops.
  void _paintConstellation(
      Canvas canvas, Size size, double shortest, double trim) {
    // Where every node is this frame, and how much of it shows.
    final pts = <Offset>[];
    final fades = <double>[];
    for (final n in _nodes) {
      final a = (t * n.speed) * 2 * math.pi + n.phase;
      final p = Offset(
        (n.x + math.cos(a) * n.dx) * size.width,
        (n.y + math.sin(a) * n.dy) * size.height,
      );
      pts.add(p);
      fades.add(_centreFade(p, size, shortest));
    }

    // ⚠️ The LINKS first, so a node always sits on top of the lines
    // meeting it rather than being cut in half by one.
    //
    // ⚠️ Only between NEAR neighbours, and the closer the pair the
    // brighter the link. Joining every pair would be a solid mesh -- the
    // shape people recognise as a constellation comes from most pairs NOT
    // being joined.
    final linkReach = shortest * 0.30;
    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        final d = (pts[i] - pts[j]).distance;
        if (d >= linkReach) continue;
        // Near the reach limit a link is invisible, so it fades IN and out
        // as the nodes drift instead of snapping on at a threshold.
        final closeness = 1 - d / linkReach;
        // ⚠️ The midpoint is faded too: two nodes either side of the
        // crest can both be clear of it while the line between them runs
        // straight across the mark.
        final mid = Offset.lerp(pts[i], pts[j], 0.5)!;
        final fade =
            math.min(fades[i] * fades[j], _centreFade(mid, size, shortest));
        final alpha = 0.30 * closeness * closeness * fade * trim;
        if (alpha <= 0.002) continue;
        linkPaint
          ..color = accent.withOpacity(alpha)
          ..strokeWidth = 0.9;
        canvas.drawLine(pts[i], pts[j], linkPaint);
      }
    }

    // The nodes themselves: a small bright core in a soft halo, so they read
    // as points of light rather than as dots painted on.
    for (var i = 0; i < pts.length; i++) {
      final fade = fades[i];
      if (fade <= 0.01) continue;
      final n = _nodes[i];
      // A slow individual breath, off the shared clock, so they do not all
      // brighten together.
      final pulse =
          0.78 + 0.22 * math.sin((t * n.speed * 2.0) * 2 * math.pi + n.phase);
      final r = n.r * (shortest / 420).clamp(0.75, 1.6);

      final halo = r * 4.2;
      canvas.drawCircle(
        pts[i],
        halo,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withOpacity(0.22 * pulse * fade * trim),
              accent.withOpacity(0.0),
            ],
          ).createShader(Rect.fromCircle(center: pts[i], radius: halo)),
      );
      canvas.drawCircle(
        pts[i],
        r,
        Paint()..color = accent.withOpacity(0.72 * pulse * fade * trim),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbFieldPainter old) =>
      old.t != t || old.accent != accent || old.deep != deep;
}

/// One drifting disc. See [_OrbFieldPainter._orbs].
class _Orb {
  /// Centre of the ellipse it travels, as a fraction of the panel.
  final double cx, cy;

  /// Radius, as a fraction of the panel's shorter side.
  final double r;

  /// How far it wanders from that centre, as a fraction of the panel.
  final double dx, dy;

  /// Peak opacity of its brightest point.
  final double a;

  /// Multiplier on the shared clock, and where in its own loop it begins.
  final double speed, phase;

  const _Orb({
    required this.cx,
    required this.cy,
    required this.r,
    required this.dx,
    required this.dy,
    required this.a,
    required this.speed,
    required this.phase,
  });
}

/// One point of the constellation. See [_OrbFieldPainter._nodes].
class _Node {
  /// Where it sits, as a fraction of the panel.
  final double x, y;

  /// Core radius in logical pixels at a 420px panel, scaled from there.
  final double r;

  /// How far it drifts from that spot, as a fraction of the panel.
  final double dx, dy;

  /// Multiplier on the shared clock, and where in its own loop it starts.
  final double speed, phase;

  const _Node({
    required this.x,
    required this.y,
    required this.r,
    required this.dx,
    required this.dy,
    required this.speed,
    required this.phase,
  });
}
