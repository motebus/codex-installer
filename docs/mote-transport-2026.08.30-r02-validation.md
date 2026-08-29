# Mote Transport 2026.08.30 R02 canary validation

This release is a traceable **canary**, not a production-readiness claim.

## Included runtime

| Package | Version | Architecture |
|---|---:|---|
| `sphere` | `4.0.0-1` | `amd64` |
| `mote-proxy` | `1.4.0-14` | `all` |
| `moted` | `3.2.0-33` | `amd64` |

The supported transport is Agent-first SSH with SFTP file transfer. Legacy SCP,
rsync, and RDP are retired and are not installed, enabled, or tested by this
installer.

## Verified result

- Both L1 and L9 run the exact package set and required services.
- Bidirectional noninteractive SSH completed 20/20 per direction in the R02
  acceptance run.
- Git-over-SSH push and clone completed two rounds per direction with matching
  refs, commits, trees, blobs, and content.
- A 1 MiB SFTP acceptance transfer completed with exact SHA-256 in the original
  closure run.
- Package module suites covered ordered native-send backpressure, relay terminal
  convergence, idempotent tombstones, protocol admission, and correlated
  counters.

## Known open findings

- A later controlled deployment observed two fresh SFTP uploads terminate with
  proxy `EAGAIN`; SFTP resume completed and final hashes matched. R02 is reopened
  specifically for unresumed SFTP stream completion.
- R03 remains open for intermittent MoteD/MoteC pre-handler delivery timeouts.
- R04 remains open because local readiness can be true while the required MoteD
  registration path is degraded.

Use this release only in the authorized lab/canary scope until those acceptance
items are closed. No controlled interruption or stress/load test is represented
by this evidence.

