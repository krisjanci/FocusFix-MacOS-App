# FocusFix release checklist

Updated November 10, 2026. The public app is a personal product, separate from the developer’s N-of-1 study. This repository does not contain a signed or notarized public release. The website download remains disabled.

## Before distributing a build

- Keep `FocusFixResearchSharingEnabled` off. The research pipeline is not qualified for this app release.
- Publish and review the [privacy page](https://krisjanci.github.io/FocusFix-Website/privacy.html). Match App Store Connect privacy answers to the app’s actual account, profile, group, and optional detailed-recording sharing behavior.
- Deploy and test the development-sharing migration and both deletion functions in the correct order. The server starts with collection off and no approved accounts. Follow [development sharing operations](supabase/DEVELOPMENT-SHARING.md).
- Use only the Supabase publishable key in the app. Keep service-role credentials and Apple signing material out of the app and repository. Scan the exported bundle and verify its entitlements.
- Run `bash scripts/test.sh`, `npm test`, and `npm run test:database` in `supabase`. Build the exact release revision and run the release content check.
- Test a signed build on a fresh Mac, including first-launch consent, Input Monitoring, automatic and manual recording, pause, sleep/lock/idle, local review/export/deletion, account sign-in, approved sharing, withdrawal, and hosted deletion. Use synthetic recordings and a disposable service for the cloud path. See [manual qualification](MANUAL-QUALIFICATION.md).
- Confirm source/license rights, accessibility, privacy language, support flow, system requirements, screenshots, and final install instructions.

## Website distribution

1. Create a clean source commit and signed archive with `bash scripts/archive-release.sh TEAM_ID /absolute/path/FocusFix.xcarchive`.
2. Export a **Developer ID Application** build with hardened runtime and secure timestamp. Notarize it and staple the ticket.
3. Run `bash scripts/verify-release.sh /absolute/path/FocusFix.app website`. This checks bundle content, source revision, signature, entitlements, ticket, and Gatekeeper.
4. After fresh-Mac qualification, run `bash scripts/package-website.sh /absolute/path/FocusFix.app /absolute/new/output-folder`. It packages the app, matching source, GPL license, and checksums.
5. Review the exact package, then add the download and instructions to the website. A package should not be presented as ready before these checks pass.

## Mac App Store

Use an App Store distribution certificate and provisioning profile. Run `bash scripts/verify-release.sh /absolute/path/FocusFix.app app-store`, complete App Store Connect privacy and metadata, upload the signed app, and wait for Apple review. Developer ID notarization alone is not an App Store submission.

An unsigned local build and synthetic tests show that code compiles and policies behave in those tests. They do not prove a signed build works on a fresh Mac, that live Supabase is deployed correctly, or that Apple will approve the app. Historical release planning was preserved in the local `CS 600/FocusFix-App-Archive-2026-11-10` folder.
