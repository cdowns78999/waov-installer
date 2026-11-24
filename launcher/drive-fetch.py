#!/usr/bin/env python3
"""drive-fetch.py  -  We Are One Voice launcher kit 2.0

Downloads a Google Drive file or folder link, unzips each WAOV asset into the buyer's
Documents\\WAOV assets folders, and makes one feature image per asset.

  python drive-fetch.py --link <drive link> --assets <Documents\\WAOV assets> --status <status.json> --kit 2.0

Layout it writes (same as the widget GET + UNPACK path, install.txt section 5 and unpack.txt):
  WAOV avatars\\NAME\\NAME.zip       the downloaded store zip
  WAOV avatars\\NAME\\asset\\         the inner {NAME}-asset.zip, unzipped
  WAOV avatars\\NAME\\item.json      copied when the asset carries one (items)
  WAOV avatars\\NAME\\unpacked.json  what was unpacked, by which kit
  WAOV avatars\\NAME\\feature.png    the asset's own feature image, or a generated card

It never signs in anywhere, never asks for a password, and only talks to Google Drive.
Status codes it writes into the status file line: WAOV-E80 .. E86, I63 .. I66.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
import zipfile
from datetime import datetime

NAME_RE = re.compile(r'^(AVI|ITE|WOR)-\d{5}-\d{8}-\d{4}')
FOLDERS = {'AVI': 'WAOV avatars', 'ITE': 'WAOV items', 'WOR': 'WAOV worlds'}
KINDS = {'AVI': 'avatar', 'ITE': 'item', 'WOR': 'world'}
TYPES = {'AVI': 'avi', 'ITE': 'item', 'WOR': 'world'}
LINK_RE = re.compile(r'^https://drive\.google\.com/[A-Za-z0-9/_\-?=&%.#]+$')

STATUS = {'stage': 'start', 'pct': 0.0, 'line': 'starting ...', 'done': False, 'ok': None, 'items': []}
STATUS_PATH = None


def write_status(**kw):
    STATUS.update(kw)
    if not STATUS_PATH:
        return
    tmp = STATUS_PATH + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(STATUS, f)
    os.replace(tmp, STATUS_PATH)


def fail(code, text):
    write_status(done=True, ok=False, line='%s (%s)' % (' '.join(str(text).split())[:160], code))
    sys.exit(1)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def drive_ids(link):
    """returns ('folder'|'file', id)"""
    m = re.search(r'/folders/([-\w]{10,})', link)
    if m:
        return 'folder', m.group(1)
    m = re.search(r'/d/([-\w]{10,})', link) or re.search(r'[?&]id=([-\w]{10,})', link)
    if m:
        return 'file', m.group(1)
    return None, None


def download(link, tmp):
    try:
        import gdown
    except Exception:
        fail('WAOV-E80', 'gdown is not installed. Go to 1 CHECKS and press GO')
    kind, ident = drive_ids(link)
    if not kind:
        fail('WAOV-E81', 'That does not look like a Drive file or folder link')
    got = []
    try:
        if kind == 'folder':
            write_status(stage='download', pct=0.08, line='reading the Drive folder ...')
            res = gdown.download_folder(id=ident, output=tmp, quiet=True, use_cookies=False, remaining_ok=True)
            got = [r if isinstance(r, str) else getattr(r, 'local_path', None) for r in (res or [])]
        else:
            write_status(stage='download', pct=0.08, line='downloading the file ...')
            out = gdown.download(id=ident, output=tmp + os.sep, quiet=True, use_cookies=False)
            got = [out] if out else []
    except Exception as e:  # network, quota, private link
        fail('WAOV-E82', 'Drive refused the download (is the link shared with anyone who has it?) %s' % str(e)[:80])
    zips = []
    for root, _dirs, files in os.walk(tmp):
        for fn in files:
            if fn.lower().endswith('.zip'):
                zips.append(os.path.join(root, fn))
    if not zips:
        fail('WAOV-E83', 'No zip files came down from that link')
    return sorted(zips)


def make_card(path, name, kind):
    """generated feature card (kit blue, cyan border) when the asset ships none"""
    from PIL import Image, ImageDraw, ImageFont
    w, h = 640, 360
    im = Image.new('RGB', (w, h), (0, 0, 170))
    d = ImageDraw.Draw(im)
    d.rectangle([4, 4, w - 5, h - 5], outline=(85, 255, 255), width=4)
    try:
        big = ImageFont.truetype('C:/Windows/Fonts/consolab.ttf', 40)
        small = ImageFont.truetype('C:/Windows/Fonts/consolab.ttf', 26)
    except Exception:
        big = small = ImageFont.load_default()
    d.text((w // 2, 70), 'WE ARE ONE VOICE', font=small, fill=(255, 255, 85), anchor='mm')
    d.text((w // 2, h // 2), kind.upper(), font=big, fill=(255, 255, 255), anchor='mm')
    d.text((w // 2, h - 80), name, font=small, fill=(170, 170, 170), anchor='mm')
    im.save(path, 'PNG')


def feature_for(asset_dir, dest_png, name, kind):
    """prefer the asset's own feature image; else a render; else a generated card"""
    from PIL import Image
    best = None
    pngs = []
    for root, _d, files in os.walk(asset_dir):
        for fn in files:
            if fn.lower().endswith(('.png', '.jpg', '.jpeg')):
                pngs.append(os.path.join(root, fn))
    for key in ('feature', 'render', 'front', 'preview', 'thumb', 'cover'):
        for p in pngs:
            if key in os.path.basename(p).lower():
                best = p
                break
        if best:
            break
    if best:
        try:
            im = Image.open(best).convert('RGB')
            im.thumbnail((640, 640))
            im.save(dest_png, 'PNG')
            return 'asset'
        except Exception:
            pass
    make_card(dest_png, name, kind)
    return 'card'


def safe_extract(zpath, dest):
    """zipfile.extractall already strips absolute and .. parts; refuse anything that still escapes"""
    dest_real = os.path.realpath(dest)
    with zipfile.ZipFile(zpath) as z:
        for info in z.infolist():
            target = os.path.realpath(os.path.join(dest, info.filename))
            if not (target == dest_real or target.startswith(dest_real + os.sep)):
                raise ValueError('unsafe path in zip: ' + info.filename)
        z.extractall(dest)


def file_asset(zpath, assets_root, kit, step_pct, step_w):
    base = re.sub(r'\s*\(\d+\)$', '', os.path.splitext(os.path.basename(zpath))[0])
    m = NAME_RE.match(base)
    if not m:
        return None, 'not a WAOV asset: %s' % os.path.basename(zpath)
    prefix = m.group(1)
    folder = FOLDERS[prefix]
    d = os.path.join(assets_root, folder, base)
    again = os.path.exists(os.path.join(d, 'unpacked.json'))
    if not again:
        os.makedirs(d, exist_ok=True)
        write_status(stage='copy', pct=step_pct + step_w * 0.2, line='filing %s into %s ...' % (base, folder))
        dest_zip = os.path.join(d, base + '.zip')
        shutil.copy2(zpath, dest_zip)
        write_status(stage='unzip', pct=step_pct + step_w * 0.45, line='unzipping %s ...' % base)
        stage = os.path.join(d, '_outer')
        asset = os.path.join(d, 'asset')
        safe_extract(dest_zip, stage)
        inner = None
        for root, _dd, files in os.walk(stage):
            for fn in files:
                if fn.endswith('-asset.zip'):
                    inner = os.path.join(root, fn)
                    break
            if inner:
                break
        if inner:
            safe_extract(inner, asset)
            shutil.rmtree(stage, ignore_errors=True)
        else:
            os.replace(stage, asset)
        for root, _dd, files in os.walk(asset):
            if 'item.json' in files:
                shutil.copy2(os.path.join(root, 'item.json'), os.path.join(d, 'item.json'))
                break
        listing = []
        for root, _dd, files in os.walk(asset):
            for fn in files:
                listing.append(os.path.relpath(os.path.join(root, fn), asset))
        with open(os.path.join(d, 'unpacked.json'), 'w', encoding='utf-8') as f:
            json.dump({'name': base, 'type': TYPES[prefix], 'sha256': sha256(dest_zip),
                       'at': datetime.now().strftime('%Y-%m-%dT%H:%M:%S'), 'kitVersion': kit, 'files': listing}, f, indent=2)
    write_status(stage='image', pct=step_pct + step_w * 0.8, line='making the feature image for %s ...' % base)
    feat = os.path.join(d, 'feature.png')
    source = 'existing'
    if not os.path.exists(feat):
        source = feature_for(os.path.join(d, 'asset'), feat, base, KINDS[prefix])
    return {'name': base, 'kind': KINDS[prefix], 'folder': folder, 'dir': d, 'feature': feat,
            'featureFrom': source, 'already': again}, None


def main():
    global STATUS_PATH
    ap = argparse.ArgumentParser()
    ap.add_argument('--link', required=True)
    ap.add_argument('--assets', required=True)
    ap.add_argument('--status', required=True)
    ap.add_argument('--kit', default='2.0')
    a = ap.parse_args()
    STATUS_PATH = a.status
    write_status(stage='start', pct=0.02, line='checking the link ...')
    if not LINK_RE.match(a.link):
        fail('WAOV-E75', 'That is not a Google Drive link')
    tmp = tempfile.mkdtemp(prefix='waov-fetch-')
    try:
        zips = download(a.link, tmp)
        items, notes = [], []
        n = len(zips)
        for i, z in enumerate(zips):
            base_pct = 0.3 + 0.65 * i / n
            try:
                item, note = file_asset(z, a.assets, a.kit, base_pct, 0.65 / n)
            except Exception as e:
                fail('WAOV-E84', 'Could not unzip %s: %s' % (os.path.basename(z), str(e)[:80]))
            if item:
                items.append(item)
            else:
                notes.append(note)
        if not items:
            fail('WAOV-E85', 'The zips in that link are not WAOV assets (' + '; '.join(notes)[:100] + ')')
        line = 'done: %d asset%s ready' % (len(items), '' if len(items) == 1 else 's')
        if notes:
            line += ', %d skipped' % len(notes)
        write_status(stage='done', pct=1.0, line=line, done=True, ok=True, items=items, skipped=notes)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()
