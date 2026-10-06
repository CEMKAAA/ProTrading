# Demo And Personalized EA

This is a working **loopback local pilot**, not a deployed public identity service.
Run `start_stratum_web.bat`, open `http://127.0.0.1:4310/studio`, then create an
account or sign in. No payment is needed for a new account's demo.

## User Flow

1. Registration grants 30 * 24 hours from the server's registration timestamp.
2. Studio displays DEMO, remaining days and the expiry date.
3. Download your personalized EA produces a private ZIP. Extract it into a
   private folder; run `start_connection.bat` with Node.js 22.13+ installed.
4. The helper generates its Ed25519 device key locally, redeems a one-use ticket,
   and displays the device fingerprint, five-minute pairing code and MT5 preset.
5. In the **same** Studio account, open Pair / Manage MT5, review the code,
   compare the fingerprint and approve. Another account cannot approve it.
6. Copy the ZIP's `MQL5` contents into MT5's **File > Open Data Folder** directory.
   Attach the EA and load `.state/connection.set` in Inputs.
7. Keep the helper running, authorize the controller in Studio, and Apply to
   audit. Trading starts OFF. Only an explicit ON after a complete matching
   audit can authorize entries. The MT5 panel shows DEMO and remaining days.

The original ZIP contains a bearer **enrollment** secret: do not share it.
It is not a trade license and never contains a server signing key, password,
browser session or broker credential. The ticket expires in 30 minutes and is
consumed once. A new download invalidates older **unused** tickets, not already
approved device keys. After pairing expires, download/extract a fresh package.
Restart an already approved installation from its existing extracted folder.
Do not move its private `.state` folder to another computer.

## Security Boundaries

- Trial history is persistent and account-scoped. Login, download, installation
  changes, local clock changes and billing events do not restart it.
- Existing pre-feature accounts are not retroactively given another demo.
- Paid entitlement and trial dates are separate. Only the operator/provider
  boundary can update paid entitlement; browser signup input cannot.
- Short-lived server RSA commands still enforce installation, MT5 account,
  broker, symbol, configuration, controller generation and replay fencing.
- DEMO is a signed **display** certificate, not execution authority.
- Expired/disabled entitlement blocks new work/entries; protective management
  of existing positions is not disabled. MT5 AlgoTrading must also be enabled
  by the user for execution. Tests do not enable it.
- Only a verified binary with current clean-compile fingerprints, original-EA
  parity and native roundtrip PASS may be downloaded. Server key pin must match.
- No `terminal64.exe`, `MetaEditor64.exe`, house MQ5/MQH files or server private
  keys are shipped. MetaTrader is obtained from the user's broker or the
  [official download](https://www.metatrader5.com/en/download). A compiled EX5
  does not require end-user compilation.

## Public Release Gates

The service refuses production startup and listens only on loopback. Supabase
has **not** been configured: no project credentials were available. Existing
local auth uses salted scrypt hashes and random, server-revocable, hashed
session tokens, never a fake frontend login.

Before public release: verified-email identity (e.g. Supabase), password reset,
MFA where required, hardened HttpOnly/SameSite cookie sessions, HTTPS deployment,
database authorization/RLS, persistent/distributed abuse limits, backed-up trial
ledger, trusted billing reconciliation, signing-key protection/rotation and
independent security review are required. One account/email cannot receive a
second demo; one **person** opening several accounts is not solved by this pilot.
Windows key-file mode alone is not TPM/non-exportable device binding. A modified
privileged client cannot be described as tamper-proof. Installer/companion code
signing and a supported Node-independent installer remain deployment work.

Do not publish the local development session/key files or compiled installer
packages as public static assets. User-facing downloads are authenticated and
`no-store`; no long-lived user license is embedded into a copied EX5.
