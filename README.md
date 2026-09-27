## SpotSoon

SpotSoon is a native iOS application that helps Bahrain Polytechnic students coordinate real-time parking handovers. A driver preparing to leave publishes a temporary signal for their campus parking zone. Another student can view and atomically claim it, then both users complete a guided handover.

The app verifies that publishing happens within a configured campus parking zone. It shares only the approximate zone publicly. Private details, including vehicle descriptions, the optional parking hint, and the matching visual handover pass, are available only to the signal owner and the successful claimant.

The project demonstrates anonymous authentication, atomic database operations, Row Level Security, Realtime synchronization, participant-only data, and temporary foreground location sharing.

## Features

- Automatic anonymous Supabase authentication with session restoration.
- MapKit campus map with GPS-verified parking zones for Campus A and Campus B.
- Temporary signals with selectable departure times and expiration filtering.
- Atomic claiming through protected PostgreSQL RPC functions, preventing double claims.
- Complete arrival, vacancy, completion, unavailability, cancellation, release, and expiration flows.
- Supabase Realtime signal and lifecycle updates across devices.
- My Garage, where users can save multiple vehicles and choose a Today’s Vehicle.
- Stable private owner and claimant vehicle snapshots, including optional plate suffixes.
- Participant-only parking hints and a matching visual pass, such as `PURPLE FOX · 27`, for safe curbside identification.
- Full-screen Live Handover screens with role-specific actions for the departing driver and claimant.
- Optional foreground-only Live Approach sharing with approximate distance bands.
- Restoration of an authenticated user’s active signal or claimed handover after relaunch.
- Light and dark appearance support using the device’s system setting.
- Row Level Security and authenticated RPC-based privacy controls.
- Push notifications are disabled in this submission; active updates use Realtime while the app is running.

## Technologies

- **Swift** for application models, services, concurrency, and business logic.
- **SwiftUI** for the native iOS interface.
- **MapKit** for campus maps, parking-zone overlays, and approach visualization.
- **Core Location** for foreground campus-zone verification and optional approach sharing.
- **Supabase Auth** for anonymous user sessions.
- **Supabase and PostgreSQL** for authentication, vehicles, signals, private handovers, and lifecycle rules.
- **Supabase Realtime** for cross-device signal and lifecycle synchronization.
- **Row Level Security and SECURITY DEFINER RPCs** for authorization, private participant data, and atomic state transitions.
- **XCTest** for model, store, repository, validation, lifecycle, privacy, and race-condition coverage.

## How to Run

1. Open `SpotSoon.xcodeproj` in Xcode.
2. Select the `SpotSoon` scheme.
3. Choose an iPhone Simulator.
4. Build and run with **Product → Run** or `⌘R`.
5. Complete onboarding and allow location access while using the app.
6. Add a vehicle in **Settings → My Garage** and select it as Today’s Vehicle.
7. Return to the map.

An internet connection is required. The app connects to the already-hosted Supabase project and signs in anonymously, so the evaluator needs no test account, Supabase credentials, or dashboard access. Use separate Simulator devices for multi-user demonstrations; each maintains its own anonymous session.

## Demo 1 — Publish a Signal

Set the Simulator to a verified Campus A location:

- Latitude: `26.164736`
- Longitude: `50.543676`

In Simulator, choose **Features → Location → Custom Location**, enter the coordinates, and return to SpotSoon.

1. Add and select a vehicle in My Garage.
2. Open the Map screen and select Campus A.
3. Tap the raised centre **Share your spot** action.
4. Choose a departure time.
5. Enter a private hint such as `Row 3, near shade canopy`.
6. Wait for the sheet to display **Verified in zone**.
7. Tap **Publish Signal**.

The app creates the public signal and private owner snapshot together. The owner enters the waiting state, and the signal appears for other authenticated users through Realtime. The optional hint is not included in the public signal or its Realtime payload.

To demonstrate Campus B instead, select Campus B and use:

- Latitude: `26.158319`
- Longitude: `50.546641`

## Demo 2 — Two-User Handover

1. Launch SpotSoon on two Simulators. Device A is the departing owner and Device B is the claimant.
2. Complete onboarding on both devices and give each user a different Today’s Vehicle.
3. On Device A, use the Campus A coordinates from Demo 1 and publish a signal.
4. On Device B, select Campus A and wait for the signal to appear in Nearby Parking.
5. Open the signal, confirm the selected arriving vehicle, and tap **Claim This Spot →**.
6. Confirm both devices show the private hint, opposite vehicle details, and matching pass. Device B shows **You’re heading there**; Device A shows **Someone is heading there**.
7. On Device B, tap **I’m Here — Waiting at the Parking Area**, then confirm **I’m Here**.
8. On Device A, visually verify the claimant while safely stopped, tap **I’ve Left — Space Is Vacant**, and confirm **I’ve Left**.
9. On Device B, tap **I Got the Spot**.
10. Confirm that the completed signal disappears from the active feed on both devices.

Before vacancy, the claimant can use **Release Claim** and the owner can use **Cancel Signal**. After vacancy, the claimant can choose **Spot Wasn’t Available**. Each action is authorized and atomic.

## Demo 3 — Live Approach Sharing

Start with an active two-user handover. Keep owner Device A at `26.164736, 50.543676`. On claimant Device B, tap **Share Live Approach**. While Live Handover remains open, change B’s custom location to each point below and wait at least five seconds after each change.

| Claimant latitude | Claimant longitude | Approximate distance | Expected band |
|---|---:|---:|---|
| `26.166200` | `50.543676` | 163 m | On the way |
| `26.165750` | `50.543676` | 113 m | Approaching |
| `26.165100` | `50.543676` | 41 m | Nearby |
| `26.164900` | `50.543676` | 18 m | Very close |

Device A should receive each approximate band through Realtime. Sharing is optional and foreground-only; tap **Pause Live Approach** to stop. It never marks arrival automatically. The claimant must still tap **I’m Here — Waiting at the Parking Area** and confirm **I’m Here**.

## Privacy

SpotSoon verifies an approximate campus parking area, not an exact bay. Vehicle snapshots, parking hints, and passes are separate from the public signal and are available only to its creator and current claimant. Unrelated users receive generic lifecycle states.

The Supabase URL and anon/publishable key are public client configuration; RLS and protected RPCs secure the data. Temporary approach locations are participant-only and deleted when the handover ends. No service-role key, database password, or private Apple credential is included.

Users should visually verify another vehicle only while safely stopped. SpotSoon must not be used to block traffic, confront another driver, or collect names and full licence plates.

## Known Limitations

- Authentication is anonymous; institutional Bahrain Polytechnic SSO is not implemented.
- An internet connection is required.
- GPS verifies an approximate parking area, not an exact bay, and device-level GPS spoofing cannot be completely prevented.
- Live Approach distance is approximate, opt-in, and foreground-only.
- Push notifications are disabled in this submission; live cross-device updates rely on Realtime while the app is open.
- Turn-by-turn directions, exact bay navigation, background tracking, and institutional SSO are not implemented.
