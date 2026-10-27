#!/usr/bin/env python3
"""Prepare local build settings and privacy declarations from reviewed study configuration.
Never deploys, approves a study, signs, uploads, or changes the live backend.
"""
import argparse
import json
import plistlib
from pathlib import Path
from urllib.parse import urlparse

REPO = Path(__file__).resolve().parent.parent
REQUIRED = ('version', 'determination_reference', 'eligibility_text', 'researcher_contact',
            'purpose', 'duration', 'retention_policy', 'risks', 'withdrawal_policy', 'information_url')
ACCOUNT_TYPES = ('EmailAddress', 'Name', 'PhotosorVideos', 'UserID')
RESEARCH_TYPES = ('OtherUsageData', 'OtherUserContent', 'Health')


def declarations(research):
    rows = []
    for name in ACCOUNT_TYPES + (RESEARCH_TYPES if research else ()):
        purposes = ['AppFunctionality'] if name in ACCOUNT_TYPES else ['Analytics', 'Other']
        if research and name == 'UserID':
            purposes += ['Analytics', 'Other']
        rows.append({'NSPrivacyCollectedDataType': 'NSPrivacyCollectedDataType' + name,
                     'NSPrivacyCollectedDataTypeLinked': True, 'NSPrivacyCollectedDataTypeTracking': False,
                     'NSPrivacyCollectedDataTypePurposes': ['NSPrivacyCollectedDataTypePurpose' + p for p in purposes]})
    return rows


def validate(study):
    if any(not isinstance(study.get(key), str) or not study[key].strip() for key in REQUIRED):
        raise ValueError('Complete the reviewed study details; empty fields cannot enable research')
    if any('REPLACE_' in study[key] for key in REQUIRED):
        raise ValueError('Replace draft placeholders with institution-reviewed study terms')
    parsed = urlparse(study['information_url'])
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('Study information must use a public HTTPS URL without credentials')
    if not study.get('recruitment_enabled') or not study.get('collection_enabled'):
        raise ValueError('Research configuration must explicitly enable recruitment and collection')
    if not isinstance(study.get('future_training'), bool) or not isinstance(study.get('allegheny_only'), bool):
        raise ValueError('Specify future_training and allegheny_only explicitly as booleans')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('study_json', type=Path)
    parser.add_argument('--write', action='store_true', help='Update local Info.plist and privacy manifest; default validates only')
    args = parser.parse_args()
    study = json.loads(args.study_json.read_text())
    validate(study)
    if args.write:
        info_path = REPO / 'FocusFix/Configuration/Info.plist'
        privacy_path = REPO / 'FocusFix/FocusFix/PrivacyInfo.xcprivacy'
        info = plistlib.loads(info_path.read_bytes())
        manifest = plistlib.loads(privacy_path.read_bytes())
        if not info.get('FocusFixAccountURL') or not info.get('FocusFixAccountPublicKey'):
            raise ValueError('Configure the account service before preparing research')
        info['FocusFixStudyInformationURL'] = study['information_url']
        info['FocusFixResearchSharingEnabled'] = True
        manifest['NSPrivacyCollectedDataTypes'] = declarations(True)
        # Write the manifest first: a partial failure must not enable undeclared collection.
        privacy_path.write_bytes(plistlib.dumps(manifest, sort_keys=False))
        info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
        print('Local research build prepared. Deploy the matching study configuration separately and test before distribution.')
    else:
        print('Study configuration validated. No local or live settings changed.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(f'Not ready: {error}')
