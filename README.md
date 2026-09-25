# SpotSoon parking handover spike

SpotSoon is a native SwiftUI and Supabase app for short-lived campus parking handovers. It uses anonymous authentication, a public Realtime signal feed, a private saved garage, atomic lifecycle RPCs, and participant-only vehicle/pass snapshots. No service-role key or additional dependency is used by the client.

## Local configuration

From the repository root:

```sh
cp Configuration/Supabase.example.plist SpotSoon/Supabase.local.plist
```

Edit the local plist with the project HTTPS `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (`sb_publishable_…`). Obtain both from the Supabase project API settings. Never use the secret or service-role key. The real plist is ignored by Git; the safe example contains placeholders. Missing or placeholder values produce a visible development error.

## Manual Supabase setup

1. In Authentication → Sign In / Providers, enable anonymous sign-ins and new sign-ups.
2. For a fresh project, run [`supabase/parking_signals.sql`](supabase/parking_signals.sql) once in the SQL Editor.
3. For the existing SpotSoon project, run migrations in filename order. After the Garage migration, run [`202609250001_repair_current_vehicle_selection.sql`](supabase/migrations/202609250001_repair_current_vehicle_selection.sql), followed by [`202609250002_add_gps_verified_parking_zone.sql`](supabase/migrations/202609250002_add_gps_verified_parking_zone.sql). Apply `202609240001_add_garage_and_vehicle_snapshots.sql` when no handover is active because legacy signals have no trustworthy owner-vehicle snapshot; that migration closes those development rows.
4. In Database → Publications → `supabase_realtime`, confirm that `public.parking_signals` is included exactly once. Confirm that `public.parking_zones`, `public.vehicles`, and `public.parking_signal_handovers` are absent.
5. In Table Editor or SQL policies, confirm RLS is enabled on all four tables. `parking_zones` exposes only active rows to authenticated users and has no client write policy. `vehicles` must have owner-only SELECT/INSERT/UPDATE/DELETE policies. `parking_signal_handovers` must have only its participant SELECT policy and no client write policy.

The app can directly read the public signal feed, read active zone definitions, and manage only its own saved vehicle rows. Publishing, claiming, arrival, release, cancellation, vacancy, completion, unavailability, expiration cleanup, and Today’s Vehicle selection use authenticated `SECURITY DEFINER` functions with an empty `search_path`. Publishing validates the submitted coordinate against the trusted Campus A zone, then copies the caller-owned vehicle snapshot in the same transaction. The coordinate is used for that check and is not stored. The public Realtime payload never contains raw coordinates, saved vehicles, snapshots, or the visual pass.

Phone GPS plus server-side coordinate checks provide practical parking-area verification. They cannot prevent every form of device-level location spoofing.

## Build and tests

Open `SpotSoon.xcodeproj`, choose the shared `SpotSoon` scheme and an iOS Simulator, then run Product → Build and Product → Test. CLI equivalent:

```sh
xcodebuild -project SpotSoon.xcodeproj -scheme SpotSoon \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/SpotSoonDerivedData build test
```

Keep normal simulator code signing enabled for manual database testing so the anonymous session can persist in Keychain. Unit tests use in-memory repositories and require no credentials.

## One-device Garage test

1. Launch SpotSoon and open the profile button → My Garage. Verify the empty state.
2. Add a vehicle with nickname **My K5**, colour **Midnight grey**, type **Sedan**, make **Kia**, model **K5**, and plate suffix **404**. Leave “Use as Today’s Vehicle” on. Verify the badge and Settings summary.
3. Add a second vehicle without selecting it. Choose “Use Today” and verify only that row has the badge.
4. Edit its nickname or colour, cancel, and verify no saved value changes. Edit again and save; verify the new value appears.
5. Delete the current vehicle. Verify the most recently updated remaining vehicle becomes Today’s Vehicle. Delete the final vehicle and verify the empty state.
6. Open Create leaving signal. With an empty garage, verify Publish is blocked and Add Vehicle returns to the publish form with the new vehicle selected.

## Two-simulator publish and handover test

Use two distinct simulator devices so each has a different anonymous user.

1. Install and launch the configured build on both simulators. On device A, save **My K5 / Midnight grey / Sedan / Kia / K5 / 404**. On device B, save a different vehicle.
2. In Simulator A, choose Features → Location → Custom Location and enter latitude **26.164736**, longitude **50.543676**. Open Create leaving signal, allow location, select 10 minutes, verify A’s selected vehicle appears under “Vehicle you’re leaving in,” and publish from **Campus A Student Car Park**.
3. On B, verify the signal arrives through Realtime. Tap Claim, confirm B’s Today’s Vehicle under “Vehicle you’re arriving in,” then confirm the claim.
4. Verify A sees B’s arriving vehicle and B sees A’s leaving **Midnight grey Kia K5 Sedan · Plate ending 404**. Verify both show the same colour, animal symbol, and two-digit number. B can open the full-screen pass.
5. Edit or delete either saved vehicle in My Garage. Verify the active handover still shows the original snapshot.
6. On B, confirm “I’m Here.” On A, verify the arrived state, visually compare the pass while safely stopped, then confirm “I’ve Left.”
7. On B, choose “I Got the Spot.” Verify the row and private data disappear on both devices. Repeat and choose “Spot Wasn’t Available.”
8. Repeat with Release Claim from claimed and arrived states. Verify the owner snapshot remains, the claimant snapshot/pass disappear, and a new claim creates a newly generated pass and claimant snapshot.
9. Verify creator cancellation from active, claimed, and arrived states removes the signal on both devices.

## Simulator location verification

1. In Xcode, run SpotSoon on a simulator. Open the simulator’s Features → Location → Custom Location menu and enter latitude **26.164736**, longitude **50.543676**.
2. Open Create leaving signal. The first attempt presents “Verify the parking area”; tap Allow Location, then allow While Using App in the system prompt. With a valid vehicle and leaving time selected, verify the UI reports **Verified at Campus A Student Car Park** and enables Publish.
3. Publish and verify Supabase accepts the RPC. A second simulator should receive the new signal through Realtime.
4. Set the simulator location to latitude **26.167000**, longitude **50.543676**, then retry location. Verify **Outside parking zone** appears with an approximate distance and Publish stays disabled.
5. To verify the server independently, call `publish_parking_signal` from an authenticated client with that outside coordinate and an owned vehicle UUID. It must fail with `outside_parking_zone`; never use a service-role key for this check.
6. Reset Location permission in the simulator, choose Don’t Allow, and verify the feed remains usable, publishing is blocked, and Open Settings appears. Turn Location Services off temporarily to verify Location unavailable, then restore it and retry with the inside coordinate.
7. Poor accuracy is deterministic in `ParkingZoneTests`; Simulator custom locations do not reliably expose an accuracy control. Run the test suite to verify a mocked reading over 65 metres is rejected.
8. Relaunch with permission granted and the inside custom location. Verify the map, circle, current-location marker, saved vehicle, and publish flow return normally.

## Third-user privacy test

1. Launch a third distinct simulator or erase/install on another simulator to obtain a third anonymous user.
2. While A and B have a claimed, arrived, or vacated handover, open the feed on C. C may see only “Claimed” or “Handover in progress”; it must show no vehicle description and no pass.
3. In the Supabase SQL Editor, test as authenticated users with JWT claims or use three normal clients: C’s `select * from vehicles` must return only C’s rows, and C’s `select * from parking_signal_handovers` must return no A/B row. A and B must each receive the same authorized snapshot row.
4. Try `set_current_vehicle`, publish, and claim with a vehicle UUID owned by a different user. Each RPC must fail with `vehicle_unavailable`.
5. Confirm direct client UPDATE of `parking_signals` lifecycle columns and direct INSERT/UPDATE/DELETE of `parking_signal_handovers` are denied.

The service-role key bypasses RLS by design and therefore must remain outside the app and all client configuration.
