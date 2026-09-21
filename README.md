# SpotSoon technical spike

Native SwiftUI + Supabase Swift 2.55.2. Anonymous session restoration, signal publishing, and a live list only. No additional dependencies.

## Local configuration

From the repository root:

```sh
cp Configuration/Supabase.example.plist SpotSoon/Supabase.local.plist
```

Edit the local plist with your project's HTTPS `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (`sb_publishable_…`). Use the publishable key from the project's API Keys settings; never a secret or service-role key. The real plist is Git-ignored. Xcode's synchronized SpotSoon folder automatically bundles it; rebuild after changing it. The example stays outside the app folder. Missing/placeholder configuration produces a visible development error; builds and unit tests need no credentials. Configuration is excluded from source control, but a client publishable key is necessarily included in the installed app. RLS protects the data.

## Supabase dashboard setup (manual)

1. In Authentication → Sign In / Providers, enable anonymous sign-ins and allow new sign-ups. See [Anonymous Sign-Ins](https://supabase.com/docs/guides/auth/auth-anonymous).
2. Run `supabase/parking_signals.sql` once in the SQL Editor of a fresh project. It creates the table, constraints, SELECT/INSERT permissions, owner-checked RLS, and adds the table to `supabase_realtime`. If the table already exists, compare its schema and policies before applying the script.
3. Verify Database → Publications → `supabase_realtime` includes `public.parking_signals`. See [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes).
4. Copy the project URL and publishable key into the local plist. This spike has no CAPTCHA UI; use a development project whose Auth settings do not require CAPTCHA.

Authenticated users (including anonymous Auth users) can read rows and insert only their own active signals. The app does not grant update/delete permissions. Dashboard changes can exercise those Realtime events. Expiry is a timestamp filter; no scheduled database job or status mutation is needed.

## Build and all tests

Open `SpotSoon.xcodeproj`, select the shared `SpotSoon` scheme and an iOS 26.5 simulator. Run Product → Build, then Product → Test. CLI equivalent:

```sh
xcodebuild -project SpotSoon.xcodeproj -scheme SpotSoon \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/SpotSoonDerivedData build test
```

Keep normal simulator code signing enabled. Supabase stores the anonymous session in Keychain;
an unsigned installed build cannot persist that session and its database requests will fall back
to the publishable key without an authenticated user.

Tests use a fake repository and never contact Supabase. They cover active/status/expiry filtering (including the exact expiry boundary), chronological order, all three leaving/expiry calculations, authenticated ownership, and visible failures.

## Two-simulator smoke test

1. Complete the dashboard and local configuration steps, then build the app using the command above.
2. Open Simulator. Boot **iPhone 17 Pro** and **iPhone 17 Pro Max** via File → Open Simulator. These must be distinct devices, not clones sharing app state.
3. Install and launch the same configured build on both devices (IDs below match this machine):

```sh
xcrun simctl boot 7E930A73-EACC-4157-899F-F8069044342E
xcrun simctl boot F4C1A649-783D-4890-A772-FB4053BBDF59
# If already booted, skip the corresponding boot command.
xcrun simctl install 7E930A73-EACC-4157-899F-F8069044342E /tmp/SpotSoonDerivedData/Build/Products/Debug-iphonesimulator/SpotSoon.app
xcrun simctl install F4C1A649-783D-4890-A772-FB4053BBDF59 /tmp/SpotSoonDerivedData/Build/Products/Debug-iphonesimulator/SpotSoon.app
xcrun simctl launch 7E930A73-EACC-4157-899F-F8069044342E com.zainab.SpotSoon
xcrun simctl launch F4C1A649-783D-4890-A772-FB4053BBDF59 com.zainab.SpotSoon
```

4. Both should finish anonymous authentication with no login screen and show an empty list for a fresh database.
5. On Pro, choose Create leaving signal → Campus A → A1 → 2 minutes → Publish. The sheet closes on success. Both devices should show the signal automatically; only Pro should say “Your signal.”
6. On Pro Max, publish Campus B / B2 / 5 minutes. Both lists should show the earlier departure first, with ownership reversed for the second signal.
7. Terminate and relaunch Pro. Its existing signal should still say “Your signal,” confirming session persistence.
8. In the dashboard Table Editor, change the first row's status to `cancelled`. Both lists should remove it without refresh. Delete the second row; both should remove it. Publish another 2-minute signal and leave the app visible for 7 minutes: it should disappear at expiry with no database event.
9. Background and foreground each app repeatedly. Live updates should recover without duplicate subscriptions. Disable the Mac's network briefly: requests/connection failures should appear visibly. Restore networking and use Refresh / Retry live updates if necessary.
10. To check publish failure, disable networking before Publish: an error should remain in the sheet and the sheet should not dismiss. A transport failure can have an uncertain server outcome; inspect/refresh the list before retrying.

The two-device network smoke test requires your configured Supabase project and is separate from offline unit tests.
