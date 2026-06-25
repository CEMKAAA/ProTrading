# EA License Manager

Standalone Flask control panel for remote ERL_IRL and Liquidity Narrative EA licensing.

## Run

Use:

```bat
start_license_manager.bat
```

Default local URL:

```text
http://127.0.0.1:8765
```

Default admin token in the BAT file is `change-me-now`. Change it before exposing the service.

## EA Validate URL

For local testing:

```text
http://127.0.0.1:8765/api/license/validate
```

For worldwide/remote control, host this Flask app on a VPS/domain and set the EA input:

```text
InpLicenseServerUrl=https://your-domain.com/api/license/validate
```

In MT5, add the host to:

```text
Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL
```

Use only the scheme + host, for example:

```text
https://your-domain.com
```

or local:

```text
http://127.0.0.1:8765
```

## License Fields

- `license_key`: key entered into the EA.
- `product`: comma-separated allowed products, for example `ERL_IRL,LIQUIDITY_NARRATIVE`. Blank means all products.
- `account`: comma-separated MT5 account numbers. Blank means all accounts.
- `terminal`: usually `MT5`. Blank means all terminals.
- `expires_at`: optional ISO datetime, for example `2026-12-31T23:59:59+00:00`.
- `active`: when false, EA validation returns inactive and the EA blocks new trades.

## Security

The validate endpoint is public by design because EAs need to call it.
All management endpoints and the UI require the admin token.

For real remote usage:

1. Set a strong `LICENSE_ADMIN_TOKEN`.
2. Run behind HTTPS.
3. Do not expose the project filesystem directly.
4. Keep backups of `license_manager/data/licenses.json`.
