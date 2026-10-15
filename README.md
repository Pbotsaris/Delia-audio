# Delia

A Zig DSP library and realtime audio runtime, written as a learning project in DSP, realtime
systems, memory design and optimization. It has an allocating analysis layer (FFT, waves,
filters; used from the Python notebooks) and a realtime layer (audio graph plus device
backends) that never allocates while rendering. The architecture and roadmap are in
`docs/DELIA_REFACTOR_PLAN.md`; the per-subsystem contracts are the other files in `docs/`.

## Requirements

- Zig 0.16.0
- Linux with ALSA headers available in the kernel (the library itself is vendored)
- autotools and `make`, used once to build the vendored alsa-lib

```sh
git clone --recurse-submodules <repo>
# or, in an existing checkout
git submodule update --init
```

## Build

```sh
zig build            # builds; the first run also configures and makes vendor/alsa
zig build run        # runs src/main.zig, the scratch entry point
zig build check      # compile-only, including every test binary (zls build-on-save uses this)
zig build bench      # zbench microbenchmarks from src/benchmarks.zig; compare with bench.txt
```

alsa-lib is built statically into `vendor/alsa/src/.libs/libasound.a` and linked only into the
`core/backends/alsa` module. Delete that file to force a rebuild of alsa-lib.

## Tests

```sh
zig build test                              # all modules
zig build test -Dtest-filter=FFT            # only tests whose name contains "FFT"
zig build test -Dtest-filter=FFT -Dtest-filter=Gain   # repeatable
```

Each module is its own test binary, so a new file is only tested once its module root lists it
in a `test { _ = file; }` block. Files that import no named module can also be run on their own:

```sh
zig test src/dsp/transforms.zig
zig test src/core/buffer/root.zig --test-filter "AudioBlock"
zig ast-check src/core/graph/plan.zig       # syntax and AST errors, no build wiring
```

Anything that imports `core/buffer`, `core/common`, `core/graph` or `dsp` by module name needs
`zig build test`.

## Examples

Examples are grouped by module and run through one entry point, `src/examples_main.zig`:

```sh
zig build example                                   # lists every group and example
zig build example -- graph                          # lists the graph examples
zig build example -- graph offline-fan-in           # render a small graph offline
zig build example -- alsa playback-sine             # 2 s of 440 Hz on the "default" device
zig build example -- alsa playback-sine hw:3 5      # 5 s on a specific card
```

Each group is a `commands` table in that module's `examples.zig`; adding an entry there is all
it takes to add an example.

### Running the ALSA examples

The backend talks to ALSA directly. Opening `default` goes through whatever ALSA is configured
to route to on your machine (PipeWire, PulseAudio or JACK through their ALSA plugins), which
works but adds their buffering on top of ours and says nothing about Delia's own timing.

For a real measurement open the card itself with `hw:N` (`aplay -l` lists them). That only
succeeds while no sound server holds the card: if `hw:N` returns `open_failed` and
`/proc/asound/cardN/stream0` says `Running`, stop the server first:

```sh
systemctl --user stop pipewire pipewire-pulse wireplumber   # PipeWire
systemctl --user start pipewire pipewire-pulse wireplumber  # afterwards
```

For PulseAudio use `pasuspender -- zig build example -- alsa playback-sine hw:3`; for JACK,
stop `jackd`.

## Layout

```
src/core/buffer/     planar f32 views and owned storage       docs/buffer-contract.md
src/core/graph/      GraphBuilder -> Compiler -> ExecutionPlan docs/graph-contract.md
src/core/backends/   alsa/: PlaybackDevice, PlaybackLoop, Pcm  docs/backend-contract.md
src/core/common/     audio_specs enums, example command table
src/dsp/             allocating analysis kernels
src/utils/           leaf helpers
pydelia-build/       CPython extension over src/dsp for notebooks/ (see its builder.py)
vendor/alsa/         alsa-lib submodule, built statically
```

Every subsystem is a named module declared in `build.zig`; files import across folders by
module name (`@import("core/buffer")`), never by relative path.
