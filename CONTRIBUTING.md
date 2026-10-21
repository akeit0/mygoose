# Contributing

MyGoose is a native UI library with example apps. The portable core is Goose in `src/`;
OS event, text, clipboard and drawing adapters live in `native/`. Optional
packages live in `extras/`; Monitor's OS counters belong to `apps/monitor/`.
The project uses the [MIT license](LICENSE).

## Build and test

Install the dependencies in [platform setup](docs/platforms.md), then:

```sh
python3 tools/bootstrap.py
python3 tools/build.py all --mode small
python3 tools/build.py test --mode debug
```

Use `python` on Windows. `all` builds every app and runs the Goose and native
tests. For a focused change, choose the relevant target:

| Target | Coverage |
| --- | --- |
| `test` | Core controls, editing, layout, interaction, tables, selection, damage and native backend |
| `monitor-test` | Monitor UI/sampler, process identity, caption, window controls and icons |
| `performance-test` | Timing, history, hover, workload controls, nested scrolling and pacing |
| `rich-test` | Vector drawing and motion |
| `images-test` | RGBA image lifecycle and rendering |
| `charts-test` | Chart API, hover slots, native payload validation and rendering |

Pass `--mode debug` to a test target to enable Goose runtime diagnostics.
Linux native tests need an X11 display; use an isolated Xvfb session:

```sh
MYGOOSE_TEST_CLIPBOARD=1 xvfb-run -a -s "-screen 0 1280x1024x24 -noreset" python3 tools/build.py all --mode small
```

Headless tests use an isolated clipboard. Native window tests run on their own
platform; passing on macOS does not establish Windows or Linux behavior.
The [manual CI template](docs/ci/native.yml) can run the same targets on all
three platforms. [Platform setup](docs/platforms.md#ci-and-measurements)
explains how to enable it.

## Changes

- While the project is experimental, simplify APIs directly and update all
  examples and callers together. Do not add compatibility aliases, deprecated
  entry points or migration guides for unreleased APIs.
- Follow the pinned compiler's Goose grammar. Prefer direct functions,
  trailing-block callbacks and bounded storage; use `match` for dispatch on a
  single value and records when parallel arrays describe one entity.
- Keep app-specific models and counters outside the library. Optional packages
  should add no storage or native dependency to clients that do not use them.
- Preserve logical-pixel coordinates and UTF-8 byte offsets at the native ABI.
- Keep regression cases that verify observable behavior. Share test setup in
  `tests/test_support.goose`; retain the partial-versus-full repaint oracle.
- For a UI change, check the affected app at narrow and wide sizes. For native
  changes, run the affected platform tests and identify untested platforms.
- Update the relevant API or app documentation. Benchmark commands and metric
  definitions belong in [bench/README.md](bench/README.md); local measurements,
  generated code and captures belong in `build/`.

Describe the problem, resulting behavior and checks run in a pull request.
For bug reports include the platform, compiler revision, build mode, a minimal
reproduction and expected behavior. Review screenshots and logs for unrelated
personal content before sharing them. Compiler upgrades should update
`tools/toolchain.json` and validate the affected targets.

Known upstream observations and workarounds are tracked in
[Goose compatibility notes](docs/goose-issues.md). Add compiler revision, host,
minimal reproduction and validation status there when a compiler/package issue
affects MyGoose. Distinguish confirmed defects from documented language rules.
