# dispatch-push-notifications

This server-only Edge Function claims idempotent lifecycle events from the private outbox and sends minimal APNs alerts. It never reads handover snapshots.

Configure these Supabase Edge Function secrets without placing values in source or chat:

- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY` (the Apple `.p8` key contents)
- `APNS_BUNDLE_ID` (`com.zainab.SpotSoon` for the current target)
- `PUSH_DISPATCH_SECRET` (a strong independent scheduler secret)

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to deployed Supabase functions. Deploy this function with JWT verification disabled, then invoke it only from a Supabase Cron job or trusted scheduler that sends `x-push-dispatch-secret`. The function itself rejects requests without that secret. Schedule it once per minute. Never place the service-role key or APNs key in SQL, the iOS app, or Realtime.

APNs `BadDeviceToken`, `DeviceTokenNotForTopic`, `Unregistered`, and HTTP 410 responses deactivate the device. Other failures back off and retry. Stable APNs IDs and database uniqueness prevent ordinary duplicate lifecycle delivery.
