# SpotSoon

SpotSoon is a native iOS application for Bahrain Polytechnic that helps students coordinate campus parking handovers. A departing student publishes a temporary signal for a parking space they are about to leave, including a departure time and optional private bay or landmark hint.

Another student can claim the signal and coordinate a private handover. GPS verifies that publishing occurs within the selected campus parking area, while participant-only vehicle details, partial plate suffixes, and a matching visual pass help the two drivers identify each other safely.

## Features

- Campus A and Campus B parking maps.
- GPS-verified parking-signal publishing.
- Saved Garage with a selectable Today’s Vehicle.
- Departure-time selection.
- Private bay or landmark hints.
- Realtime parking signals across devices.
- Atomic signal claiming that prevents double claims.
- Participant-only vehicle details and optional plate suffixes.
- Matching private windshield handover passes.
- Arrival, vacancy, completion, release, and cancellation lifecycle.
- Active-handover restoration after relaunch.
- Optional foreground Live Approach sharing.
- System light and dark mode support.

## Technologies

- **Swift and SwiftUI:** Native application logic, concurrency, and interface.
- **MapKit:** Campus maps, zone overlays, and approach visualization.
- **Core Location:** Foreground parking-area verification and optional approach sharing.
- **Supabase Swift SDK:** Client access to authentication, data, and Realtime services.
- **PostgreSQL:** Persistent signals, vehicles, private handovers, and lifecycle state.
- **Anonymous authentication:** Automatic account creation without a visible login screen.
- **Row Level Security and protected RPCs:** Participant authorization and atomic operations.
- **Supabase Realtime:** Cross-device signal and lifecycle synchronization.
- **XCTest:** Automated validation of models, stores, lifecycle behavior, and privacy rules.

## How to Run

1. Open `SpotSoon.xcodeproj`.
2. Select the shared SpotSoon scheme.
3. Choose an iPhone Simulator.
4. Build and run.
5. Complete onboarding.
6. Add a vehicle in Garage.
7. Return to the campus map.

Internet access is required. The app uses its bundled public Supabase client configuration and connects to an already-prepared hosted backend. Anonymous sign-in happens automatically. The lecturer does not need Supabase credentials or dashboard access and must not run any SQL. See [SUBMISSION.md](SUBMISSION.md) for additional submission and build notes.

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

Physical movement can be simulated by changing Simulator B’s custom location while its Live Handover screen remains open. Simulator A should publish from `26.164736, 50.543676`. After B claims the signal, tap **Share Live Approach**, then change B’s coordinates one at a time and wait at least five seconds after each change.

| State | Latitude | Longitude |
|---|---:|---:|
| On the way | `26.166200` | `50.543676` |
| Approaching | `26.165750` | `50.543676` |
| Nearby | `26.165100` | `50.543676` |
| Very close | `26.164900` | `50.543676` |

Sharing is optional and works only while the handover screen is active. Displayed distance is approximate, and the claimant can stop sharing with **Pause Live Approach**. Live Approach never marks the claimant as arrived automatically; the claimant must still tap **I’m Here — Waiting at the Parking Area** and confirm **I’m Here**.

## Privacy

The public Supabase client key is safe to bundle in the application. Row Level Security and protected server functions control data access, and only the current signal owner and claimant receive private handover information. Temporary approach locations are deleted when the handover ends. No service-role key, database password, or private Apple credential is included.

## Limitations

- An internet connection is required.
- GPS verifies an approximate parking area, not an exact bay.
- Device-level location spoofing cannot be completely prevented.
- Live Approach sharing is approximate, opt-in, and foreground-only.
- Remote push notifications are not included in the submitted build.
