import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/202609250009_harden_push_tokens_and_expiration_schedule.sql"
BOOTSTRAP = ROOT / "supabase/parking_signals.sql"


class SubmissionHardeningSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.migration = MIGRATION.read_text()
        cls.bootstrap = BOOTSTRAP.read_text()

    def test_clients_can_only_read_their_own_push_rows(self):
        for sql in (self.migration, self.bootstrap):
            self.assertIn("grant select on table public.push_device_tokens to authenticated", sql)
            self.assertNotIn(
                "grant select, insert, update, delete on table public.push_device_tokens to authenticated",
                sql,
            )
        for policy in (
            '"Users can add their push devices"',
            '"Users can update their push devices"',
            '"Users can remove their push devices"',
        ):
            self.assertIn(f"drop policy if exists {policy}", self.migration)
            self.assertNotIn(f"create policy {policy}", self.bootstrap)

    def test_registration_rpcs_remain_authenticated_and_derive_auth_uid(self):
        self.assertIn("declare v_user_id uuid := auth.uid()", self.bootstrap)
        self.assertIn(
            "grant execute on function public.register_push_device(text, uuid, text) to authenticated",
            self.bootstrap,
        )
        self.assertIn(
            "grant execute on function public.deactivate_push_device(uuid, text) to authenticated",
            self.bootstrap,
        )

    def test_scheduler_expiry_is_server_only_and_idempotent(self):
        for sql in (self.migration, self.bootstrap):
            self.assertIn("expire_parking_signals_scheduled()", sql)
            self.assertIn("status in ('active', 'claimed', 'arrived', 'vacated')", sql)
            self.assertIn("and expires_at <= now()", sql)
            self.assertIn(
                "grant execute on function public.expire_parking_signals_scheduled()",
                sql,
            )
            self.assertIn("to service_role", sql)
        self.assertIn(
            "from public, anon, authenticated",
            self.migration,
        )

    def test_private_tables_stay_out_of_realtime(self):
        self.assertNotIn(
            "alter publication supabase_realtime add table public.push_device_tokens",
            self.bootstrap,
        )
        self.assertNotIn(
            "alter publication supabase_realtime add table public.parking_signal_locations",
            self.bootstrap,
        )


if __name__ == "__main__":
    unittest.main()
