# Cloud Runtime

- Target orchestrated, non-interactive jobs.
- Inputs come from prepared workspaces, artifacts, or named state roots.
- Dynamic host `PWD` behavior is not part of the contract.
- Job output must be recoverable from exit status and preserved artifacts.
- Favor one-shot execution and deterministic shutdown over interactive convenience.
