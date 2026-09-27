import pathlib
import unittest

ROOT = pathlib.Path(__file__).parents[2]
MIGRATION = (ROOT / "supabase/migrations/202609250007_add_push_notifications.sql").read_text()
BOOTSTRAP = (ROOT / "supabase/parking_signals.sql").read_text()
EDGE = (ROOT / "supabase/functions/dispatch-push-notifications/index.ts").read_text()


class PushNotificationSchemaTests(unittest.TestCase):
    def test_required_server_confirmed_events_are_queued(self):
        for event in (
            "signal_claimed", "claimant_arrived", "signal_vacated",
            "claim_released", "signal_unavailable", "active_claim_expired",
        ):
            self.assertIn(event, MIGRATION)
        self.assertIn("after update of status, claimed_by, claimed_at", MIGRATION)
        self.assertIn("on conflict do nothing", MIGRATION)

    def test_participant_targets_and_generic_copy(self):
        self.assertIn("v_recipient := new.created_by", MIGRATION)
        self.assertIn("v_recipient := old.claimed_by", MIGRATION)
        for forbidden in ("parking_hint", "confirmation_number", "plate_suffix", "latitude", "longitude"):
            self.assertNotIn(forbidden, EDGE)

    def test_private_tables_are_rls_protected_and_not_realtime(self):
        self.assertIn("alter table public.push_device_tokens enable row level security", MIGRATION)
        self.assertIn("alter table public.push_notification_events enable row level security", MIGRATION)
        self.assertNotIn("add table public.push_device_tokens", BOOTSTRAP)
        self.assertNotIn("add table public.push_notification_events", BOOTSTRAP)

    def test_bootstrap_contains_the_incremental_schema(self):
        # Later ordered hardening migrations intentionally tighten the initial
        # table grants, so compare the durable schema/RPC/trigger contract
        # rather than requiring the bootstrap to preserve obsolete grants.
        for definition in (
            "create table public.push_device_tokens (",
            "create table public.push_notification_events (",
            "create function public.register_push_device(",
            "create function public.deactivate_push_device(",
            "create function public.claim_push_notification_events(",
            "create function public.enqueue_parking_signal_notifications()",
            "create trigger parking_signals_enqueue_notifications",
        ):
            self.assertIn(definition, MIGRATION)
            self.assertIn(definition, BOOTSTRAP)
        self.assertIn(
            "grant execute on function public.register_push_device(text, uuid, text) to authenticated",
            BOOTSTRAP,
        )
        self.assertIn(
            "grant execute on function public.deactivate_push_device(uuid, text) to authenticated",
            BOOTSTRAP,
        )


if __name__ == "__main__":
    unittest.main()
