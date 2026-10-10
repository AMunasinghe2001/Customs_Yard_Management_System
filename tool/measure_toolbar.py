"""Measure the ICT toolbar's PAINTED edges from the golden image.

This exists because every layout measurement disagreed with the screen, and the
layout measurements were the ones that were wrong.

An InputDecorator does not stretch its border to the box it is given. With
`isDense`, it sizes its own container to the content plus contentPadding and
CENTRES that inside the box. So a field in a SizedBox(40) with 8px padding laid
out at 40 and PAINTED at 34, while the button's fill ran the whole 40 -- and
`tester.getRect` reported 40 for both, because 40 is what the layout said. Four
rounds of "but they measure the same" followed.

So this reads the pixels instead.

Run:  flutter test test/ict_toolbar_golden_test.dart --update-goldens
      python tool/measure_toolbar.py
"""

import sys
from PIL import Image

PNG = "test/goldens/ict_toolbar.png"

# A column through each control, and what its edge looks like there:
#   fields -- the 1px border stroke against the card fill
#   button -- its own solid fill
FIELD_BORDER = (221, 227, 236)
BUTTON_FILL = (142, 58, 95)
COLUMNS = {"search": 300, "filter": 700}
BUTTON_X = (1000, 1180)


def near(px, target, tol=25):
    return max(abs(a - b) for a, b in zip(px[:3], target)) <= tol


def main():
    img = Image.open(PNG).convert("RGB")
    h = img.size[1]
    spans = {}

    # The CARD draws a rule of the same colour top and bottom, and it is the
    # outermost such row in every column -- so taking the first and last match
    # measures the card, not the control. Its two rows are dropped.
    for name, x in COLUMNS.items():
        rows = [y for y in range(h) if near(img.getpixel((x, y)), FIELD_BORDER)]
        if len(rows) < 4:
            print(f"{name}: expected the card's two rules and the field's two, "
                  f"found {len(rows)}")
            return 1
        spans[name] = (rows[1], rows[-2])

    rows = [
        y for y in range(h)
        if any(near(img.getpixel((x, y)), BUTTON_FILL) for x in range(*BUTTON_X))
    ]
    if not rows:
        print("button: no fill found")
        return 1
    spans["button"] = (rows[0], rows[-1])

    for name, (top, bottom) in spans.items():
        print(f"  {name:7s} top={top:3d}  bottom={bottom:3d}  "
              f"height={bottom - top + 1:3d}")

    tops = [t for t, _ in spans.values()]
    bots = [b for _, b in spans.values()]
    print()
    print(f"  top spread    : {max(tops) - min(tops)} px")
    print(f"  bottom spread : {max(bots) - min(bots)} px")
    if max(tops) - min(tops) > 1 or max(bots) - min(bots) > 1:
        print("  FAIL: draw a line above and below and something sticks out")
        return 1
    print("  OK: every control's ink begins and ends on the same row")
    return 0


if __name__ == "__main__":
    sys.exit(main())
