# SpotSoon

Finding parking at Bahrain Polytechnic can take time, even while other students are preparing to leave. SpotSoon connects departing drivers with students looking for a space, helping them coordinate a quick and private parking handover.

A departing student shares a temporary signal with a departure time and an optional bay or landmark hint. Another student can claim it and follow the handover steps. GPS checks that the signal is published from the selected campus parking area. Private vehicle details, partial plate suffixes, and a matching visual pass help the two drivers identify each other safely.

## Features

- Parking maps for Campus A and Campus B.
- GPS checks before a parking signal can be published.
- A saved Garage with one vehicle selected as Today’s Vehicle.
- A choice of departure times.
- An optional private bay or landmark hint.
- Parking signals that update across devices in real time.
- A claim system that prevents two students from claiming the same signal.
- Private vehicle details and plate suffixes shared only between the two drivers.
- A matching private windshield pass for both drivers.
- A complete handover flow from claim to completion, including release and cancellation.
- Active handovers return after reopening the app.
- Optional Live Approach sharing that shows when the incoming driver is getting closer.
- Light and dark mode that follows the device setting.

## Technologies

- **Swift and SwiftUI:** The app’s logic, concurrency, and native interface.
- **MapKit:** Campus maps, parking zones, and Live Approach visuals.
- **Core Location:** Parking-area checks and optional foreground location sharing.
- **Supabase Swift SDK:** Access to authentication, stored data, and live updates.
- **PostgreSQL:** Storage for signals, vehicles, handovers, and their current state.
- **Anonymous authentication:** Automatic sign-in without a login screen.
- **Row Level Security and protected RPCs:** Access control and safe, single-step database actions.
- **Supabase Realtime:** Signal and handover updates between devices.
- **XCTest:** Automated checks for app behavior and privacy rules.

## How to Run

1. Open `SpotSoon.xcodeproj`.
2. Select the shared SpotSoon scheme.
3. Choose an iPhone Simulator.
4. Build and run.
5. Complete onboarding.
6. Add a vehicle in Garage.
7. Return to the campus map.

Internet access is required. The bundled public Supabase configuration connects the app to the prepared hosted backend, and anonymous sign-in happens automatically. The lecturer does not need Supabase credentials or dashboard access and must not run any SQL. See [SUBMISSION.md](SUBMISSION.md) for additional submission and build notes.

## Demo

### Publish a Parking Signal

1. In Simulator, choose **Features → Location → Custom Location**.
2. For Campus A, enter latitude `26.164736` and longitude `50.543676`.
3. Select Campus A in SpotSoon.
4. Tap the centre **Share your spot** action.
5. Choose a vehicle and departure time.
6. Enter the private hint `Row 3, near shade canopy`.
7. Wait for **Verified in zone**, then tap **Publish Signal**.

For a Campus B demonstration, use `26.158319, 50.546641` and select Campus B before publishing.

### Two-User Handover

1. Open SpotSoon on two different Simulator devices.
2. Complete onboarding and add a different vehicle on each device.
3. Simulator A publishes a parking signal.
4. Simulator B receives it, opens the claim sheet, and taps **Claim This Spot →**.
5. Confirm that both users see the private hint, the other participant’s vehicle, and the same handover pass.
6. On B, tap **I’m Here — Waiting at the Parking Area**, then confirm **I’m Here**.
7. On A, tap **I’ve Left — Space Is Vacant**, then confirm **I’ve Left**.
8. On B, tap **I Got the Spot**.
9. Confirm that the completed signal disappears from the active feed on both devices.

The claimant can choose **Release Claim** before the owner leaves, and the owner can choose **Cancel Signal** before the space is vacated.

### Live Approach Demo

To simulate movement, change Simulator B’s custom location while its Live Handover screen remains open. Simulator A should publish from `26.164736, 50.543676`. After B claims the signal, tap **Share Live Approach**, then change B’s coordinates one at a time and wait at least five seconds after each change.

| State | Latitude | Longitude |
|---|---:|---:|
| On the way | `26.166200` | `50.543676` |
| Approaching | `26.165750` | `50.543676` |
| Nearby | `26.165100` | `50.543676` |
| Very close | `26.164900` | `50.543676` |

Sharing is optional and works only while the handover screen is active. The distance is approximate, and the claimant can stop sharing with **Pause Live Approach**. Live Approach does not mark the claimant as arrived automatically. The claimant must still tap **I’m Here — Waiting at the Parking Area** and confirm **I’m Here**.

## Privacy

The public Supabase client key is safe to include in the app. Row Level Security and protected server functions control access to stored data. Only the current signal owner and claimant receive private handover information. Temporary approach locations are deleted when the handover ends. No service-role key, database password, or private Apple credential is included.

## Limitations

- An internet connection is required.
- GPS verifies an approximate parking area, not an exact bay.
- Device-level location spoofing cannot be completely prevented.
- Live Approach sharing is approximate, opt-in, and foreground-only.
- Remote push notifications are not included in the submitted build.
