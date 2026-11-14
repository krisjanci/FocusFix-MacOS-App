# Group sync and Build 5

Verified November 14, 2026.

The running Xcode Debug app loaded groups but its declared-work batch failed with PostgreSQL P0001, `Recording bounds cannot move backwards`. Individual retries isolated one finalized rotated segment. Its saved display start omitted 0.5156989097595215 seconds; reconciliation consequently changed the immutable bounds already accepted by the service. Other ready summaries were accepted.

SavedSession now reads the exact segment start from the bounded, ID-matched local capture manifest. This existing metadata preserves fractional seconds across rotation. Reconciliation also detects a different start even when day totals are unchanged, so previously staged rounded summaries are rebuilt with a new revision. Original recording files and server bounds validation are preserved.

After the user explicitly approved summary retries to the configured Supabase project, a diagnostic compiled from the updated SavedSession, coverage, and SocialLedger code rebuilt the pending summaries without changing the running app's cache. The service returned HTTP 200, version 1, acknowledging all three ready summaries. Credentials and recording files were not included in logs or release artifacts. Older incomplete day-only outbox entries remain local until their detailed coverage can be recovered; they are not sent to the legacy increment-only endpoint.

Regression checks cover fractional starts, rotated segments whose continuing context began earlier, and re-staging when precise start bounds differ despite unchanged totals. This verifies the live summary endpoint and local reconstruction; a two-Mac end-to-end test was not performed. The currently running old Debug process requires rebuilding/relaunching to use the fix.
