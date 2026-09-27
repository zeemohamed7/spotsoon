import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).parents[2]
MIGRATION = (ROOT / "supabase/migrations/202609250008_add_live_approach_tracking.sql").read_text()
BOOTSTRAP = (ROOT / "supabase/parking_signals.sql").read_text()


class ApproachTrackingSchemaTests(unittest.TestCase):
    def test_private_table_has_structural_and_accuracy_constraints(self):
        self.assertIn("create table public.parking_signal_locations", MIGRATION)
        self.assertIn("references public.parking_signals(id) on delete cascade", MIGRATION)
        self.assertIn("owner_horizontal_accuracy between 0 and 65", MIGRATION)
        self.assertIn("claimant_horizontal_accuracy between 0 and 65", MIGRATION)
        self.assertIn("parking_signal_locations_claimant_state_check", MIGRATION)

    def test_rls_allows_only_creator_or_current_claimant(self):
        self.assertIn("alter table public.parking_signal_locations enable row level security", MIGRATION)
        self.assertIn("signal.created_by = (select auth.uid())", MIGRATION)
        self.assertIn("signal.claimed_by = (select auth.uid())", MIGRATION)
        self.assertIn("signal.expires_at > now()", MIGRATION)
        self.assertIn("grant select on table public.parking_signal_locations to authenticated", MIGRATION)
        self.assertNotIn("grant insert on table public.parking_signal_locations", MIGRATION)
        self.assertNotIn("grant update on table public.parking_signal_locations", MIGRATION)

    def test_coordinates_are_not_added_to_public_realtime(self):
        publication = re.compile(
            r"alter\s+publication\s+supabase_realtime\s+add\s+table\s+public\.parking_signal_locations",
            re.IGNORECASE,
        )
        self.assertIsNone(publication.search(MIGRATION))
        self.assertIsNone(publication.search(BOOTSTRAP))

    def test_publish_atomically_stores_the_verified_owner_position(self):
        self.assertIn("create or replace function public.publish_parking_signal", MIGRATION)
        self.assertIn("insert into public.parking_signal_locations", MIGRATION)
        self.assertIn("p_device_latitude, p_device_longitude, p_horizontal_accuracy, now()", MIGRATION)
        self.assertIn("security definer", MIGRATION)
        self.assertIn("set search_path = ''", MIGRATION)

    def test_claimant_updates_are_authenticated_fresh_and_throttled(self):
        self.assertIn("create function public.set_approach_location_sharing", MIGRATION)
        self.assertIn("create function public.update_claimant_approach_location", MIGRATION)
        self.assertIn("signal.claimed_by = v_user_id", MIGRATION)
        self.assertIn("p_captured_at < now() - interval '15 seconds'", MIGRATION)
        self.assertIn("p_horizontal_accuracy not between 0 and 65", MIGRATION)
        self.assertIn("if v_elapsed < 5 and v_moved < 15", MIGRATION)
        self.assertIn("if p_captured_at <= v_location.claimant_captured_at", MIGRATION)
        self.assertIn("signal.status in ('claimed', 'arrived')", MIGRATION)
        self.assertIn("signal.expires_at > now()", MIGRATION)
        self.assertIn("to authenticated", MIGRATION)

    def test_release_reclaim_vacancy_and_terminal_cleanup_are_explicit(self):
        self.assertIn("new.status in ('completed', 'unavailable', 'cancelled', 'expired')", MIGRATION)
        self.assertIn("delete from public.parking_signal_locations where signal_id = new.id", MIGRATION)
        self.assertIn("old.status in ('claimed', 'arrived') and new.status = 'active'", MIGRATION)
        self.assertIn("old.status = 'active' and new.status = 'claimed'", MIGRATION)
        self.assertIn("claimant_latitude = null", MIGRATION)
        self.assertIn("claimant_sharing_enabled = false", MIGRATION)
        self.assertIn("new.status = 'vacated'", MIGRATION)

    def test_bootstrap_contains_the_incremental_schema(self):
        body = MIGRATION.split("begin;\n", 1)[1].rsplit("\ncommit;", 1)[0].strip()
        self.assertIn(body, BOOTSTRAP)


if __name__ == "__main__":
    unittest.main()
