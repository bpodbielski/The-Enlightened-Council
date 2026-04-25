---
description: Verify air gap enforcement blocks every cloud AI hostname at the URLSession layer
---

# airgap-verify

Run this as part of Phase 3 exit and again at Phase 10 ship gate.

## Hostnames to verify blocked

- `api.anthropic.com`
- `api.openai.com`
- `generativelanguage.googleapis.com`
- `api.x.ai`

## Steps

1. Enable air gap (`air_gap_enabled = true`) via Settings.
2. Run `./scripts/airgap-verify.sh`, which:
   - Launches a local proxy on port 8888
   - Starts the app in debug mode
   - Triggers a dummy council run that attempts one request to each provider
   - Confirms zero requests reach the proxy
3. Report pass/fail per hostname.
4. Repeat for `sensitivity_class = confidential` (should auto-enable air gap with no toggle change required).

## Pass criteria

- Zero outbound requests to any of the four hostnames during a full council run
- Zero DNS queries for those hostnames if system `dnssd` logging is captured

## Output

Pass or fail per hostname + aggregate pass/fail. Log results to `scripts/airgap-results.json`.
