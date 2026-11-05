"""Build `appcast.xml` — the feed WinSparkle reads to decide there is an update.

    python tools/generate_appcast.py
    python tools/generate_appcast.py --notes "Fixes the ICT OTP resend"

WHAT IT DOES
------------
  1. reads the version from pubspec.yaml            (1.2.0+3 -> 1.2.0)
  2. finds installer/output/SLCustoms-SR-Setup-<version>.exe
  3. writes installer/output/appcast.xml pointing at the Supabase URL

⚠️ THE VERSION IN THE FEED IS WHAT DECIDES AN UPDATE, not the file name and
not the date. WinSparkle compares the running app's version against
`sparkle:version` here; if the feed says 1.2.0 and the officer is running
1.2.0, nothing happens however new the .exe is. So this script reads the
version from pubspec.yaml rather than letting anyone type it twice.

⚠️ AND IT MUST MATCH THE VERSION COMPILED INTO THE .exe. Flutter writes
pubspec's version into the binary; Inno Setup writes `#define AppVersion`
from installer/setup.iss into the installer. Those are two different files
that must say the same thing, so this script CHECKS them and refuses to
write a feed when they disagree -- a silent mismatch means officers are
either never offered the update or offered it forever.
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Where the published files live. The enclosure URL must resolve to the .exe
# itself, not to a listing page.
BUCKET_BASE = ('https://knqpwufqpcoevjaxuihp.supabase.co'
               '/storage/v1/object/public/updates')

OUT_DIR = os.path.join(ROOT, 'installer', 'output')


def fail(msg):
    print('ERROR: ' + msg, file=sys.stderr)
    sys.exit(1)


def read_pubspec_version():
    """`version: 1.2.0+3` -> ('1.2.0', '3')."""
    p = os.path.join(ROOT, 'pubspec.yaml')
    with open(p, encoding='utf-8') as f:
        m = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
                      f.read(), re.M)
    if not m:
        fail('no `version: X.Y.Z+N` line in pubspec.yaml')
    return m.group(1), m.group(2)


def read_installer_version():
    """`#define AppVersion "1.2.0"` from installer/setup.iss."""
    p = os.path.join(ROOT, 'installer', 'setup.iss')
    with open(p, encoding='utf-8-sig') as f:
        m = re.search(r'^#define\s+AppVersion\s+"([^"]+)"', f.read(), re.M)
    if not m:
        fail('no `#define AppVersion "..."` in installer/setup.iss')
    return m.group(1)


def _notes_to_html(notes):
    """Turn the release note into a small HTML body.

    ⚠️ ESCAPED FIRST, always. The note is typed on the command line and
    goes into a page the updater renders; an unescaped `&` or `<` would
    either vanish or break the rest of the pane.

    A line starting with `-` or `*` becomes a bullet, so a multi-line note
    reads as a list rather than one run-on paragraph. Everything else
    becomes a paragraph.
    """
    lines = [l.rstrip() for l in notes.splitlines()]
    out = []
    bullets = []

    def flush():
        if bullets:
            out.append('<ul>%s</ul>'
                       % ''.join('<li>%s</li>' % b for b in bullets))
            del bullets[:]

    for line in lines:
        s = line.strip()
        if not s:
            flush()
            continue
        if s[0] in '-*•':
            bullets.append(escape(s[1:].strip()))
        else:
            flush()
            out.append('<p>%s</p>' % escape(s))
    flush()
    return ''.join(out) or '<p>%s</p>' % escape(notes.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--notes', default='',
                    help='one line describing this release, shown in the '
                         'update prompt')
    ap.add_argument('--exe', default=None,
                    help='override the installer path (default: the one '
                         'named after the pubspec version)')
    ap.add_argument('--channel', default='',
                    help='write an isolated feed under this channel name')
    args = ap.parse_args()

    version, build = read_pubspec_version()
    iss_version = read_installer_version()

    # ⚠️ Refuse rather than guess. See the module docstring.
    if iss_version != version:
        fail('version mismatch:\n'
             '    pubspec.yaml        %s\n'
             '    installer/setup.iss %s\n'
             'Set both to the same version before building the feed.'
             % (version, iss_version))

    exe = args.exe or os.path.join(
        OUT_DIR, 'SLCustoms-SR-Setup-%s.exe' % version)
    if not os.path.isfile(exe):
        fail('installer not found:\n    %s\n'
             'Build it first:\n'
             '    tool\\publish_release.ps1' % exe)

    size = os.path.getsize(exe)
    if size < 1024 * 1024:
        fail('%s is only %d bytes - that is not a full installer'
             % (os.path.basename(exe), size))

    # RFC-822, which is what the appcast format requires. Built from an
    # aware UTC datetime so the offset is always written explicitly.
    pub_date = format_datetime(datetime.now(timezone.utc))

    channel = re.sub(r'[^a-z0-9._-]+', '-', args.channel.lower()).strip('-')
    base_url = BUCKET_BASE + (('/' + channel) if channel else '')
    channel_out = os.path.join(OUT_DIR, channel) if channel else OUT_DIR
    url = '%s/%s' % (base_url, os.path.basename(exe))
    notes = args.notes.strip() or ('Version %s of the SR Management System.'
                                   % version)

    # ⚠️ `sparkle:version` MUST BE THE STRING WINDOWS READS OFF THE .exe,
    # character for character. Flutter stamps pubspec's full `1.3.0+4` into
    # the binary's FileVersion, so WinSparkle's "you have ..." is `1.3.0+4`.
    # Writing just the build number (`4`) here made the comparison
    #
    #     "4"  vs  "1.3.0+4"
    #
    # which is never equal -- so the officer installed the update, restarted,
    # and was told about the SAME version again, for ever. Reported exactly
    # that way: "එක පාරක් අප්ඩේට් එක කරා. ආයි පාරක් ඒත් පෙන්වනවනේ".
    exe_version = '%s+%s' % (version, build)

    # ⚠️ THE NOTES ARE RENDERED AS HTML, IN AN EMBEDDED BROWSER.
    #
    # Handing WinSparkle a bare line of text leaves that pane with no styling
    # at all: it came out as white-on-black with the whole line selected, so
    # the release note was barely readable -- reported as "රිලීස් නෝටිස්
    # එකේ කලුවටනේ පෙන්වන්නේ".
    #
    # So the description carries a full little document: explicit background
    # and text colours, a readable UI font, and a ::selection that keeps text
    # dark when the pane opens with the line highlighted. Colours are stated
    # outright rather than inherited, because there is nothing to inherit
    # from inside that control.
    notes_html = (
        '<html><head><meta charset="utf-8"><style>'
        'html,body{margin:0;padding:12px 14px;'
        'background:#ffffff;color:#1a1a1a;'
        "font-family:'Segoe UI',system-ui,sans-serif;"
        'font-size:13px;line-height:1.55;}'
        'h1,h2,h3{font-size:14px;margin:0 0 8px;color:#111111;}'
        'ul{margin:6px 0 0 18px;padding:0;}'
        'li{margin:3px 0;}'
        'p{margin:0 0 8px;}'
        'a{color:#0b5cad;}'
        '::selection{background:#cfe3f7;color:#1a1a1a;}'
        '</style></head><body>'
        + _notes_to_html(notes) +
        '</body></html>')

    xml = '''<?xml version="1.0" encoding="utf-8"?>
<!--
  Generated by tools/generate_appcast.py - do not edit by hand.

  WinSparkle downloads THIS file, compares sparkle:version against the
  running app, and only then offers the enclosure below. Upload this file
  and the .exe together: a feed naming an installer that is not there yet
  turns every officer's update into a failed download.
-->
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sri Lanka Customs SR Management System</title>
    <link>%(base)s/appcast.xml</link>
    <description>Updates for the SR Management System</description>
    <language>en</language>
    <item>
      <title>Version %(version)s</title>
      <description><![CDATA[%(notes_html)s]]></description>
      <pubDate>%(pub_date)s</pubDate>
      <enclosure url="%(url)s"
                 sparkle:version="%(exe_version)s"
                 sparkle:shortVersionString="%(version)s"
                 length="%(size)d"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
''' % {
        'base': BUCKET_BASE,
        'version': escape(version),
        'build': escape(build),
        'exe_version': escape(exe_version),
        'notes_html': notes_html,
        'pub_date': pub_date,
        'url': escape(url),
        'size': size,
    }

    out = os.path.join(channel_out, 'appcast.xml')
    os.makedirs(channel_out, exist_ok=True)
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(xml)

    # ── latest.json, for the in-app banner ────────────────────────────────
    #
    # ⚠️ TWO FEEDS, ON PURPOSE. The app has two independent update paths and
    # they read different formats:
    #
    #   lib/core/update_check.dart  -> JSON, drives the in-app UpdateBanner
    #   lib/core/app_updater.dart   -> appcast.xml, drives WinSparkle
    #
    # update_check.dart was written against the GitHub Releases API, so this
    # file copies that exact shape -- tag_name, assets[], draft, prerelease.
    # Keeping the shape means neither the Dart nor test/update_check_test.dart
    # has to change, and the banner works from Supabase with no rewrite.
    #
    # ⚠️ The GitHub URL it defaults to points at a PRIVATE repo, which answers
    # 404 to an officer's PC, so the banner could never have fired in the
    # field. Build with:
    #     --dart-define=UPDATE_MANIFEST_URL=<this file's public URL>
    latest = {
        'tag_name': 'v%s' % version,
        'name': version,
        'draft': False,
        'prerelease': False,
        'body': notes,
        'published_at': datetime.now(timezone.utc)
                                .strftime('%Y-%m-%dT%H:%M:%SZ'),
        'assets': [
            {
                'name': os.path.basename(exe),
                'size': size,
                'browser_download_url': url,
                'content_type': 'application/octet-stream',
            }
        ],
    }
    out_json = os.path.join(channel_out, 'latest.json')
    with open(out_json, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(latest, f, indent=2)
        f.write('\n')

    mb = size / (1024.0 * 1024.0)
    print('feeds written')
    print('  version   : %s (build %s)' % (version, build))
    print('  installer : %s  (%.1f MB)' % (os.path.basename(exe), mb))
    print('  published : %s' % pub_date)
    print('  appcast   : %s' % out)
    print('  json      : %s' % out_json)


if __name__ == '__main__':
    main()
