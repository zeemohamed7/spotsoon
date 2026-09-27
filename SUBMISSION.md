# SpotSoon university submission

## Project

SpotSoon is a native SwiftUI campus parking-handover application backed by an existing hosted Supabase project. The evaluator does not need Supabase dashboard access, a Supabase account, or an app username and password. On first launch, Supabase anonymous authentication creates a separate authenticated app user automatically; later launches restore that local session when available.

The submitted `SpotSoon/Supabase.client.plist` contains only the hosted project URL and publishable mobile-client key. Supabase Row Level Security and authenticated RPC authorization protect user data. The submission contains no service-role key, database password, management token, APNs private key, signing private key, or push dispatch secret.

## Requirements

- Xcode 26.6 (verified) with the iOS Simulator platform installed.
- Minimum deployment target: iOS 18.6.
- An internet connection for authentication, Realtime updates, Garage data, and multi-user handovers.
- An iPhone Simulator is sufficient for marking. A physical-device build may require the evaluator to select their own development team.
- Location permission is required only when publishing and when a claimant explicitly enables optional live approach sharing. Browsing and Garage remain available without location permission.

## Build and run

1. Open `SpotSoon.xcodeproj`.
2. Select the shared **SpotSoon** scheme.
3. Select an iPhone Simulator or an eligible iPhone.
4. Build and run.
5. Complete the onboarding screens.
6. Open **Garage** and add a vehicle.
7. To demonstrate publishing in Simulator, choose **Features → Location → Custom Location** and use one of these parking-zone centres:
   - Campus A: `26.164736, 50.543676`
   - Campus B: `26.158319, 50.546641`

These coordinates are demonstration centres for the configured parking zones. They are not personal-location data.

## Two-user demonstration

1. Launch the project on two distinct Simulator devices so each installation creates its own anonymous session.
2. Complete onboarding and add a different Garage vehicle on each device.
3. On device A, set a custom location to one of the campus coordinates above and publish a departure signal.
4. On device B, open the same campus feed and claim A’s signal.
5. Verify the matching private pass and participant-only vehicle information.
6. On B tap **I’m Here**; on A tap **I’ve Left**; on B finish with **I Got the Spot** or **Spot Wasn’t Available**.

## Hosted backend

The submitted app connects to the author’s already-hosted Supabase project. Evaluators should not run SQL migrations during normal marking. The `supabase/migrations` directory is included as implementation evidence and disaster-recovery documentation. `supabase/parking_signals.sql` provisions a fresh project and must never be run against the hosted project. The hosted backend and internet access must remain available for authentication and multi-user features.

Campus A and Campus B zone rows are readable by authenticated anonymous sessions. Garage ownership, private handover details, lifecycle transitions, and approach locations are authorized using `auth.uid()`; the application does not depend on the author’s existing anonymous user ID.

## Current limitations

- GPS verifies an approximate parking-zone perimeter, not an exact parking bay.
- Live approach tracking is approximate, temporary, opt-in, and foreground-only.
- Anonymous identity depends on the locally restored Supabase session; reinstalling can create a new anonymous identity.
- Push notifications are disabled in this university build. Realtime synchronization remains active while the application is running.
- Internet access is required for authentication and multi-user features.

## Security model

The project URL and publishable key are intentionally included public client configuration. They identify the backend but do not bypass authorization. Supabase RLS limits table access, and `SECURITY DEFINER` RPCs use `auth.uid()` to authorize atomic lifecycle operations. Private handover, vehicle, hint, pass, and approach information remains restricted to the appropriate participants. No privileged credential is required by or included in the iOS application.

## Submission contents

Include:

- `SpotSoon.xcodeproj`, including the shared scheme and Swift package resolution file
- `SpotSoon` Swift source, assets, `PrivacyInfo.xcprivacy`, and `Supabase.client.plist`
- `SpotSoonTests`
- `Configuration/Supabase.example.plist`
- `supabase` migrations, bootstrap SQL, static tests, and Edge Function source
- `README.md` and `SUBMISSION.md`

Exclude:

- `.git`
- `DerivedData` and build products
- `.DS_Store`
- all `xcuserdata` and `*.xcuserstate`
- private `.env` files and ignored `SpotSoon/Supabase.local.plist`
- APNs `.p8` keys, signing certificates/private keys, provisioning profiles, database credentials, and management tokens
- temporary screenshots and generated files not referenced by the Xcode project

No final submission archive is created by this preparation step.
