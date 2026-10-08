# Per-User Native Strategy Access

Admin identity is a server-side UUID role for `ciracicemberk0@gmail.com`, not
user-editable metadata. The admin panel selects a user, then lists the private
catalog by ORB, MaCross, Sol Advanced, and EntryLab. All strategies are denied
until an explicit per-user grant is enabled. Toggle updates use a revision check
and create audit events.

The private catalog currently contains 188 import-validated native records.
Assigned strategies appear in that user's Studio library. Loading a record
rechecks the authenticated session, entitlement, and grant, and updates only the
Studio draft. It does not enable live trading. Disabling a grant prevents future
loads, but cannot erase a configuration the user already received or copied.

Private tables have RLS and no direct browser grants. Exposed RPC wrappers are
security-invoker functions; privileged functions remain in the private schema
with an empty search path. Service credentials and full native snapshots are
not included in the static frontend export.

Verification: the rollback SQL suite covers metadata forgery, cross-user access,
direct writes, new-account default denial, stale revisions, grant/load/revoke,
and invalid sessions. The local control/auth/cloud/delivery/catalog suites have
80 passing tests. Static Pages build and secret-exposure checks pass. The live
cloud smoke test uses an existing QA account, which can legitimately have grants
assigned through the admin panel; it must not reset those grants as a test side
effect. Visual/browser usability verification remains separate from API checks.
