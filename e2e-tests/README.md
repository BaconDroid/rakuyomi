# End-to-end tests

Drives a real KOReader instance with the rakuyomi plugin loaded, through the
KOReader IPC socket, and asserts on what the UI shows. These tests start the
Rust server, open views, and take screenshots, so they are slow and need a
display.

## Requirements

- **Python 3.13.** `pydantic-core` 2.27.2 has no wheel for 3.14 and does not
  build there. `devenv.nix` pins the same interpreter.
- **KOReader plus the plugin**, which the `dev` script provides:
  `nix run .#rakuyomi.koreader-with-plugin`. The driver launches it and waits
  for the IPC socket, so `nix` (via devenv) has to be available.
- **An X display.** Use `xvfb-run` when running headless.

## Running

```sh
poetry install --no-root
xvfb-run -a poetry run pytest
```

`devenv.nix` wires the same thing up as `run-e2e-tests`.

Some tests use an LLM to drive the UI. They read `OPENAI_API_KEY`,
`OPENAI_BASE_URL` and `OPENAI_MODEL`, so any OpenAI-compatible endpoint works;
the workflow points them at Gemini's compatibility API. `RAKUYOMI_TEST_INITIALIZATION_TIMEOUT`
raises the startup budget, because the first run builds the server from source.
