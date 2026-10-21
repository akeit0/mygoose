# Goose compatibility notes

Track upstream observations here so a later issue or PR has a reproducible
starting point. The compiler pin is
[`448efe7021f7e6a2357d20c717f1aa9c8798b2f2`](../tools/toolchain.json).
Recheck an observation after changing that pin. Record compiler/toolchain
versions, host, expected/observed behavior, the smallest reproduction and the
workaround before proposing an upstream change.

## GOOSE-001: MinGW CMake archive paths in response files

**Status:** confirmed on Windows on 2026-10-21 with the pinned compiler,
MinGW-w64 GCC 15.2.0 and CMake 3.30.3. The reduced fixture below fails to link
from both plain and space-containing project directories when the compiler
cache path has no spaces. Correcting only the response-file path separators
makes it link and run. The fixture also builds and runs on macOS/Clang.

**Upstream PR:** [aardappel/goose#56](https://github.com/aardappel/goose/pull/56)
quotes and escapes cc-style response-file arguments. The regression fails on
unmodified upstream `8511ae3` and passes after the fix with Windows GCC 15.2.0,
Windows Clang 18.1.8 and Linux/WSL2 GCC 11.4.0. The PR is open; keep the local
workaround until a compiler revision containing the fix is adopted.

**Affected route:** `goose build --cc gcc` on Windows, with a CMake package
whose interface target links a static implementation target. The direct
`tools/build.py` route does not use Goose's CMake response-file handling.

**Observed behavior:** a CMake archive path such as `pkg\libimpl.a` is copied
into a GCC response file without escaping its backslash. GCC interprets that
backslash while reading an unquoted response-file argument, so the library
path is changed and linking fails. This is specifically an unquoted-path
failure: putting the compiler cache in a directory containing spaces makes
Goose quote the archive argument, and that control case passes.

**Expected behavior:** CMake's resolved archive paths reach the linker
unchanged for the selected toolchain, including paths containing spaces.

A minimal package should contain these files:

```goose
// main.goose
import native from "./pkg";
fn main() { assert(native::answer() == 42); }
```

```goose
// pkg/native.goose
namespace native;
extern fn answer() -> i32;
```

```goose
// pkg/native.build
main_thread_only = true;
cmake_target = "native";
```

```c
/* pkg/impl.c */
#include <stdint.h>
int32_t answer(void) { return 42; }
```

```cmake
# pkg/CMakeLists.txt
cmake_minimum_required(VERSION 3.20)
project(response_path C)
add_library(impl STATIC impl.c)
add_library(native INTERFACE)
target_link_libraries(native INTERFACE impl)
```

On Windows with MinGW GCC and CMake/Ninja on PATH, run
`goose build --cc gcc main.goose`. The CMake library fragment is
`pkg\libimpl.a`; Goose resolves it against the CMake build directory and writes
an unquoted argument ending in `cmake/pkg\libimpl.a` to `link-cc.rsp`. The linker
then reports `cannot find .../cmake/pkglibimpl.a: No such file or directory`.
Replacing backslashes with forward slashes in a copy of that response file,
then rerunning the same GCC link command with the copy, links successfully;
the resulting program passes its assertion. Moving only the project into a
directory containing spaces still fails because the cache path stays unchanged.
Setting `GOOSE_HOME` to a cache directory containing spaces passes, with the
archive argument now double-quoted. The original affected targets and workaround are in
[`CMakeLists.txt`](../CMakeLists.txt) and
[`apps/monitor/CMakeLists.txt`](../apps/monitor/CMakeLists.txt).

**Workaround:** preserve the implementation build dependency, and link with
`-L${CMAKE_CURRENT_BINARY_DIR}` and `-lmygoose_native_impl` (or the Monitor
implementation name) rather than passing CMake's archive path. Keep this local
to `MINGW`; other toolchains link the target normally.

**Upstream investigation:** the CMake response-file writer in
[`src/native.h` at the pin](https://github.com/aardappel/goose/blob/448efe7021f7e6a2357d20c717f1aa9c8798b2f2/src/native.h)
quotes fragments only when they contain spaces. The same writer is present in
[`8511ae3`](https://github.com/aardappel/goose/blob/8511ae34bdc9aabf77baaab80b4d659ea87835e2/src/native.h#L368),
the upstream head checked on 2026-10-21. The PR above fixes toolchain-aware
response-file escaping without changing linker flags such as `-l...`. Its
regression exercises backslashes and spaces through the CMake package route,
alongside an unaffected Unix build.

## GOOSE-002: root files must declare package dependencies

**Status:** documented design constraint, not a compiler bug. Reproduced on
macOS with the pinned compiler during Monitor cleanup. Consider it only as an
API/packaging ergonomics discussion, not as a failing import resolver.

This originally surfaced when static graphics imported the motion packages.
Graphics now has a static runner and no motion dependency, so Monitor no longer
needs those root imports. The compiler rule still applies to animation runners.

To reproduce in a scratch copy, remove the `mygoose_motion` import from
`examples/motion.goose` while retaining `mygoose_motion_app`, then run:

```sh
goose build --cc clang examples/motion.goose
```

The diagnostic identifies the missing package and supplies the import line to
add. Restoring the motion declaration makes the build succeed. The same rule applies
to benchmark and test entry points. The requirement is intentional:
[upstream package documentation](https://github.com/aardappel/goose/blob/448efe7021f7e6a2357d20c717f1aa9c8798b2f2/docs/packages.md)
keeps package versions flat and declared in the root file.

**Workaround:** keep the root declarations, even when a named import has no
direct call site in that entry point. Removing an unused library-local import
is different from removing a root package declaration. No downstream compiler
patch is needed. Any proposed alternative should preserve explicit version
selection and useful diagnostics for conflicting package sources.
