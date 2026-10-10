import 'package:flutter/material.dart';

import '../core/security_policy.dart';
import '../core/theme.dart';

/// The requirements a password must meet, shown ABOVE the field.
///
/// ⚠️ Built from [PasswordPolicy.rules], never from hand-written text. Four
/// login screens carried a `helperText: 'Minimum 8 characters'` while
/// `violation()` rejected anything under 12 — so the form told the officer to
/// do one thing and then refused it. A checklist that is generated from the
/// same list the validator walks cannot drift that way.
///
/// Each line ticks green as its rule is satisfied, so the reader can see
/// exactly which one is still missing rather than being told one at a time.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({
    super.key,
    required this.password,
    this.accent,
  });

  final String password;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ok = colors.successGreen;
    final rules = PasswordPolicy.rules;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.textMuted.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your password needs:',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary)),
          const SizedBox(height: 6),
          // Two columns, so six rules do not push the form off a laptop
          // screen. Wrap rather than a grid: the labels differ in length and
          // a fixed grid would strand the short ones.
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final rule in rules)
                _RuleLine(
                  label: rule.label,
                  met: rule.isMet(password),
                  okColor: ok,
                  pendingColor: colors.textMuted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({
    required this.label,
    required this.met,
    required this.okColor,
    required this.pendingColor,
  });

  final String label;
  final bool met;
  final Color okColor;
  final Color pendingColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 180),
      style: TextStyle(
        fontSize: 11.5,
        height: 1.35,
        color: met ? okColor : pendingColor,
        fontWeight: met ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // The icon carries the state as well as the colour: a red/green pair
        // alone is unreadable to the most common form of colour blindness.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            key: ValueKey(met),
            size: 13,
            color: met ? okColor : pendingColor,
          ),
        ),
        const SizedBox(width: 5),
        Text(label),
      ]),
    );
  }
}

/// The bar under a password field: red while rules are outstanding, filling
/// as they are met, and green across the full width once the password passes.
///
/// ⚠️ Driven by how many of [PasswordPolicy.rules] are satisfied, not by
/// `PasswordPolicy.strength` — strength is a 0-4 opinion about how good a
/// password is, while this bar is a promise that the form will accept it.
/// Filling a bar to the end and then rejecting the password would be worse
/// than showing no bar at all.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = PasswordPolicy.rules.length;
    final met = PasswordPolicy.metCount(password);
    final complete = PasswordPolicy.allRulesMet(password);
    final fraction = total == 0 ? 0.0 : met / total;

    // Empty field: no bar at all. A red bar before a single keystroke reads
    // as an error the user has not had a chance to make yet.
    final show = password.isNotEmpty;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: show
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(children: [
                      Container(
                          height: 5, color: colors.textMuted.withOpacity(0.18)),
                      LayoutBuilder(
                        builder: (context, c) => AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                          height: 5,
                          width: c.maxWidth * fraction,
                          decoration: BoxDecoration(
                            color:
                                complete ? colors.successGreen : colors.dangerRed,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          complete ? colors.successGreen : colors.dangerRed,
                    ),
                    child: Text(complete
                        ? 'Password meets every requirement'
                        : '$met of $total requirements met'),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// The bar under a CONFIRM field: fills green only when the two match.
///
/// ⚠️ Says nothing until the confirmation has been typed into. Marking an
/// empty confirm box as "does not match" is technically true and useless.
class PasswordMatchBar extends StatelessWidget {
  const PasswordMatchBar({
    super.key,
    required this.password,
    required this.confirm,
  });

  final String password;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final matches = confirm.isNotEmpty && confirm == password;
    final show = confirm.isNotEmpty;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: show
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(children: [
                      Container(
                          height: 5, color: colors.textMuted.withOpacity(0.18)),
                      LayoutBuilder(
                        builder: (context, c) => AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                          height: 5,
                          // Nothing in between: the passwords either match or
                          // they do not, and a half-filled bar would suggest
                          // being partly right counts for something.
                          width: matches ? c.maxWidth : 0,
                          decoration: BoxDecoration(
                            color: colors.successGreen,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      matches
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      size: 13,
                      color:
                          matches ? colors.successGreen : colors.dangerRed,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      matches ? 'Passwords match' : 'Passwords do not match',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            matches ? colors.successGreen : colors.dangerRed,
                      ),
                    ),
                  ]),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
