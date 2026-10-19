"""Run only on a disposable macOS CI host with Xcode and Flutter."""
import json
import platform
from pathlib import Path
import subprocess
import zipfile


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available',
                             '--json', capture_output=True).stdout)
    candidates = [device for runtime, group in devices['devices'].items()
                  if '.iOS-' in runtime for device in group
                  if 'iPad Pro' in device['name'] and
                  ('13-inch' in device['name'] or '12.9-inch' in device['name'])]
    if not candidates:
        raise SystemExit('No 13-inch or 12.9-inch iPad Pro simulator installed. '
                         'Check the Xcode image and installed runtimes.')
    candidates.sort(key=lambda device: ('13-inch' in device['name'], device['name']),
                    reverse=True)
    device = candidates[0]
    udid = device['udid']
    print(f"Using {device['name']} ({udid})", flush=True)
    if device['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', udid)
    try:
        run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
        run('xcrun', 'simctl', 'ui', udid, 'appearance', 'light')
        run('xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41',
            '--batteryState', 'charged', '--batteryLevel', '100')
        run('flutter', 'drive', '--debug', '-d', udid,
            '--driver=test_driver/store_screenshots.dart',
            '--target=integration_test/store_screenshots_test.dart', timeout=1800)
        output = Path('/tmp/sensatrace-ipad-screenshots')
        images = sorted(output.glob('*.png'))
        if len(images) != 4:
            raise SystemExit(f'Expected 4 screenshots, found {len(images)}')
        # JPEG export removes the alpha channel without changing pixel dimensions.
        upload_images = []
        for image in images:
            jpeg = image.with_suffix('.jpg')
            run('sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '95',
                str(image), '--out', str(jpeg))
            upload_images.append(jpeg)
        with zipfile.ZipFile(output / 'SensaTrace-iPad-screenshots.zip', 'w',
                             zipfile.ZIP_DEFLATED) as archive:
            for image in upload_images:
                archive.write(image, image.name)
        print('Screenshots ready. Review all four images before store upload.')
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False)


if __name__ == '__main__':
    if platform.system() != 'Darwin':
        raise SystemExit('This script requires macOS and Xcode.')
    main()
