#!/usr/bin/env python3
"""Inspect an app without executing it. This does not establish signing or approval."""
import argparse
import plistlib
import subprocess
from urllib.parse import urlparse
from pathlib import Path


def check(app: Path, require_revision: bool = False, submission_ready: bool = False) -> None:
    def require(condition, message):
        if not condition:
            raise ValueError(message)

    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == 'io.github.krisjanci.FocusFix', 'Not the production app identifier')
    require(info.get('FocusFixBuildChannel') == 'release', 'Not a Release build')
    require(info.get('LSMinimumSystemVersion') == '14.0', 'Unexpected minimum macOS version; review compatibility')
    require(info.get('LSApplicationCategoryType') == 'public.app-category.productivity', 'Missing store category')
    require(info.get('CFBundleShortVersionString') and info.get('CFBundleVersion'), 'Missing version/build')
    if submission_ready:
        policy = urlparse(info.get('FocusFixPrivacyPolicyURL', ''))
        require(policy.scheme == 'https' and policy.hostname and not policy.username and not policy.password,
                'App Store submission requires a published HTTPS privacy-policy URL')
    if require_revision:
        revision = info.get('FocusFixSourceRevision', '')
        require(len(revision) == 40 and all(c in '0123456789abcdef' for c in revision), 'Archive needs an exact source commit')
    resources = app / 'Contents/Resources'
    license_text = (resources / 'GPL-3.0.txt').read_bytes()
    repo = Path(__file__).resolve().parent.parent
    require(license_text == (repo / 'LICENSE').read_bytes(), 'Bundled license differs from repository license')
    require((resources / 'AppIcon macOS.icns').is_file(), 'Missing Mac app icon')
    privacy = plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes())
    require(privacy.get('NSPrivacyTracking') is False, 'Release must not declare advertising tracking')
    declared = {v['NSPrivacyCollectedDataType']: v for v in privacy.get('NSPrivacyCollectedDataTypes', [])}
    account_enabled = bool(info.get('FocusFixAccountURL') and info.get('FocusFixAccountPublicKey'))
    required = {'NSPrivacyCollectedDataType' + t for t in ('EmailAddress', 'Name', 'PhotosorVideos', 'UserID', 'OtherUsageData', 'OtherUserContent')} if account_enabled else set()
    if info.get('FocusFixResearchSharingEnabled'):
        required |= {'NSPrivacyCollectedDataTypeOtherUsageData', 'NSPrivacyCollectedDataTypeOtherUserContent', 'NSPrivacyCollectedDataTypeHealth'}
        require(str(info.get('FocusFixStudyInformationURL', '')).startswith('https://'), 'Missing study information URL')
    require(required <= declared.keys(), 'Privacy manifest omits configured off-device collection')
    require(all(v.get('NSPrivacyCollectedDataTypeTracking') is False for v in declared.values()), 'Unexpected tracking declaration')
    reasons = {v['NSPrivacyAccessedAPIType']: v['NSPrivacyAccessedAPITypeReasons'] for v in privacy['NSPrivacyAccessedAPITypes']}
    require('CA92.1' in reasons.get('NSPrivacyAccessedAPICategoryUserDefaults', []), 'Missing preferences API reason')
    require('C617.1' in reasons.get('NSPrivacyAccessedAPICategoryFileTimestamp', []), 'Missing app-container timestamp API reason')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(executable)], text=True).split()
    require({'arm64', 'x86_64'} <= set(architectures), 'Expected Apple Silicon and Intel slices')
    require(b'focusfix-uploads.focusfix-research.workers.dev' not in executable.read_bytes(), 'Development receiver found in Release binary')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--require-revision', action='store_true')
    parser.add_argument('--submission-ready', action='store_true')
    args = parser.parse_args()
    try:
        check(args.app, args.require_revision, args.submission_ready)
    except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Not ready: {error}\n')
    print('Release content passed: identity, privacy manifest, license, icon, architectures and no development endpoint.')
    print('This is not a signature, notarization, runtime-compatibility or App Review result.')
