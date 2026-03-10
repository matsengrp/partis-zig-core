# partis-zig-core Constitution

Development principles for partis-zig-core — a Zig reimplementation of
partis's C++ computational core ([ham](https://github.com/psathyrella/ham)
and ig-sw), exposed to the partis Python driver via C ABI. Technical
architecture decisions will live in `DESIGN.md` once the project matures.

Principles are ordered by importance: core values first, then
development process, then project practice.

---

## I. Equivalence Is the Compass

Every piece of ported functionality MUST be validated against the
original C++ output. Equivalence is established incrementally through
instrumented output comparisons, not by eyeballing results.

- Both the C++ originals and the Zig replacements emit structured
  diagnostic output at key checkpoints (HMM scores, Viterbi paths,
  Forward probabilities, Smith-Waterman alignments). These are
  compared automatically.
- A component is "done" when its diagnostic output matches the C++
  original to within documented tolerances on the shared test suite.
- When partis-zig-core deliberately deviates from C++ behavior (e.g.
  fixing a known bug, improving numerical stability), document the
  deviation and the reasoning. The default is match, not improve.

## II. Familiar to partis Developers

A ham/ig-sw author reading this code should be able to find their
way around.

- Variable names, function names, and module boundaries should map
  recognizably to their C++ counterparts.
- When Zig idiom conflicts with a C++ name, prefer the existing name
  unless it would violate Zig conventions (e.g. Zig uses snake_case
  for functions, PascalCase for types).
- Gratuitous renaming is a defect. Renaming is allowed when the C++
  name is genuinely misleading or when Zig's type system makes a
  different factoring clearly superior.

## III. C ABI Is the Integration Surface

The Zig code exposes a C ABI that the partis Python driver calls
directly (via ctypes or cffi), replacing the current subprocess
invocation of `bcrham` and `ig-sw`.

- The C ABI must be stable and minimal — expose what Python needs,
  not the full internal API.
- Python calls Zig as a shared library, not as a subprocess. This
  eliminates serialization overhead and process startup cost.
- The library MUST also build as a standalone binary for testing
  and debugging independent of Python.

## IV. Incremental, Component-at-a-Time Porting

Port one component at a time, not both at once.

- Each component (ham, ig-sw) gets its own equivalence tests before
  the next one starts.
- Within ham, port subsystems incrementally: data structures first,
  then forward/Viterbi algorithms, then the full HMM pipeline.
- Each ported subsystem MUST compile and pass equivalence tests
  independently.

## V. Fail Fast, Explain Clearly

Invalid inputs and violated assumptions MUST produce immediate,
actionable errors.

- No silent defaults for required parameters.
- Error messages MUST say what was expected and what was received.
- Numerical issues (underflow, NaN, negative scores) MUST be caught
  and reported, not silently propagated.

## VI. Zig Idioms, Not C++ Transliteration

partis-zig-core is a Zig library, not C++ with different syntax.

- Use Zig's type system: tagged unions for variants, error unions for
  fallible operations, comptime generics where appropriate.
- Explicit memory management with arena allocators. No hidden heap
  allocation in hot paths.
- Cache-friendly data layout (struct-of-arrays where it matters).
- No runtime dispatch in inner loops — use comptime specialization.
- Lessons from phyz apply directly. Consult phyz's `DESIGN.md` and
  `CONSTITUTION.md` for Zig-specific patterns.

## VII. No Runtime Dependencies

The built artifact is a self-contained shared library (and optionally
a static library or standalone binary). No C++ standard library, no
GSL, no yaml-cpp, no SCons.

- Everything ham currently gets from GSL and yaml-cpp gets
  reimplemented in Zig or replaced with Zig stdlib equivalents.
- The only external dependency is the Zig standard library.

## VIII. Performance Is a Requirement, Not an Optimization

The C++ core exists because Python was too slow for HMM and
alignment operations. The Zig replacement must be at least as fast.

- Profile before optimizing, but design for performance from the start
  (cache layout, allocation strategy, SIMD where applicable).
- Benchmarks against the C++ originals MUST be part of the test suite.
- Performance regressions are bugs.

## IX. Simplicity

Prefer the simplest correct solution.

- Delete unused code completely — no commented-out blocks or
  compatibility shims.
- Don't build abstractions speculatively. Extract them when two
  modules demonstrably share a pattern.

## X. Respect the Field

partis represents years of careful work in computational immunology.
This rewrite is motivated by engineering goals (eliminating the C++
build complexity, type safety, performance), not dissatisfaction
with the original code's correctness.

- Public-facing text MUST be respectful of partis and its authors.
- When partis-zig-core deviates from C++ behavior, explain the
  engineering reasoning without disparaging the original design.
- The people who built partis are collaborators, not competitors.
