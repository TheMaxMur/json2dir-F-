# json2dir in F*

A Unix command-line port of [alurm/json2dir](https://github.com/alurm/json2dir).
Reads one JSON document from stdin and materializes its object in the current
directory. The application is written entirely in F*: JSON parsing, Unicode
conversion, path checks, duplicate handling, tree traversal and CLI behavior.

```sh
make bootstrap
make test
mkdir output
cd output
../json2dir < ../example-tree.json
```

Objects become directories, strings become files, `["link", target]` becomes a
symbolic link, and `["script", content]` becomes a file with all three execute
bits set. The root must be an object. Additional command-line arguments print
usage and exit with status 1, as in the original.

## Build

`make bootstrap` downloads the pinned official F* **v2026.09.27** distribution
into `.tools/fstar`, checks its SHA-256, and uses Nix to build OCaml 5.3 and
its libraries into `.tools/ocaml` if `ocamlfind` is not already installed.
Supports macOS arm64/x86_64 and Linux aarch64/x86_64. Nothing is added to the
global Nix profile. The OCaml dependencies are pinned by `flake.lock`.

With an existing OCaml environment, install findlib, batteries, stdint,
ppx_deriving and ppx_deriving_yojson (for example via opam). Set `FSTAR_HOME`
to the root of the F* release bundle if it lives elsewhere:

```sh
FSTAR_HOME=/path/to/fstar make
make verify
make test
make install PREFIX="$HOME/.local"
```

The build first checks F*, then extracts **only** the `Json2dir` modules to
OCaml, and compiles a native `json2dir` executable. It recompiles the required
official F* runtime sources with the local OCaml packages, avoiding ABI
mismatches with prebuilt libraries. Generated files and build dependencies
are ignored; there are no handwritten application `.ml`, Rust, C, shell
commands or external JSON parser in the executable. Shell scripts orchestrate
the build; Python is used only to test it.

## Source

| File | Purpose |
| --- | --- |
| `src/Json2dir.Json.fst` | Total recursive-descent JSON parser, escape/surrogate handling, nesting limit |
| `src/Json2dir.Spec.fst` | Pure executable name checker and JSON-to-entry classifier |
| `src/Json2dir.Proofs.fst` | Checked safety and classification lemmas, ported from the Lean specification |
| `src/Json2dir.Utf8.fst` | UTF-8 encoding and decoding, including NUL and non-BMP characters |
| `src/Json2dir.Tree.fst` | Uses the verified name checker/classifier; handles ordering and materialization |
| `src/Json2dir.Main.fst` | Stdin, UTF-8/number validation, errors and exit status |
| `src/native/*.fsti` | Typed interfaces to existing OCaml standard library and Unix primitives |

`make verify` discharges the F* verification conditions without `admit`,
`--lax` or admitted SMT queries. The parser and its pure helpers are total.
The OS/runtime interfaces are trusted declarations; filesystem operations
and the CLI use the ML effect.

## Verified properties

`src/Json2dir.Proofs.fst` ports every theorem in
[tsalkenov/json2dir-lean's Spec.lean](https://github.com/tsalkenov/json2dir-lean/blob/1d307a44d04a690fdc142ae7b219ede83195dd27/Spec.lean)
(commit `1d307a44d04a690fdc142ae7b219ede83195dd27`, WTFPL). The corresponding
pure functions are implemented in `Json2dir.Spec` and called by the CLI:

| Lean theorem | F* lemma |
| --- | --- |
| `interpretParts_safe` | `interpret_parts_safe` |
| `parseName_safe` | `parse_name_safe` |
| `parseName_noTraversal` | `parse_name_no_traversal` |
| `classify_directory` | `classify_directory` |
| `classify_file` | `classify_file` |
| `classify_link` | `classify_link` |
| `classify_script` | `classify_script` |
| `classify_unknown_kind` | `classify_unknown_kind` |
| `classify_empty_array` | `classify_empty_array` |
| `classify_null` | `classify_null` |
| `classify_bool` | `classify_bool` |
| `classify_num` | `classify_num` |

An accepted key normalizes to one nonempty component that is neither `.` nor
`..` and contains no `/`. The F* version additionally rules out NUL.
`parse_name_single_component` proves that the normalized component list is
exactly that singleton and that the original key has neither a root/current
directory prefix nor NUL. `valid_name_has_safe_component` connects the boolean
check used by the CLI to the safe normalized result.

The classification lemmas prove the directory/file/link/script conversion
table, including preservation of children and payloads, and rejection of
unknown tags, empty arrays, null, both booleans, and numbers. Null and booleans
have distinct AST constructors so their statements match the Lean version.

These are propositions over the actual pure runtime functions, checked by
F* and Z3, not tests or assumed theorems. `make verify` checks all 14 lemmas;
the proof module is not included in the executable. As in the Lean source,
these proofs do not verify JSON parsing, OS operations, concurrent symlink
safety, or full equivalence to Rust. The CLI retains the original key spelling
for I/O to preserve Rust's behavior on trailing separators; the name lemmas
describe its normalized component, not the raw key as a slash-free string.

## Compatibility

- UTF-8 is validated before parsing or filesystem writes. JSON strings support
  every standard escape, UTF-16 surrogate pairs and embedded NUL in file content.
- Syntax is validated for numbers, booleans and null; these values cannot be
  materialized. Non-finite numbers fail before any write, including in a
  subsequently overwritten duplicate member.
- Keys are processed in lexicographic order, with the last value for duplicate
  keys retained, matching the original serde_json configuration.
- Keys must contain one normal Unix path component. Empty names, absolute paths,
  leading `./`, `..`, multi-component paths and NUL in names are rejected.
  Rust's accepted redundant trailing separators and interior `.` components
  are preserved; the OS may still reject a file path ending in `/`.
- Existing files and symlinks are unlinked before processing their value.
  Existing directories are merged and their unrelated entries remain.
  Directories, including empty ones, are never removed to make room for a file.
- Permissions follow the process umask; scripts add `0o111` to their current mode.
- The JSON nesting limit is 128 containers. Errors go to stderr and return 1;
  successful runs are silent and return 0.
- Directory traversal uses explicit relative paths instead of changing process
  cwd. Error wording includes the failing path but is not byte-identical to Rust.

As in the original, conversion can leave a partially updated tree after a
semantic or I/O error. JSON syntax errors leave the tree untouched. Filesystem
operations do not protect against concurrent symlink/TOCTOU attacks.

## Tests

```sh
make test
make differential REFERENCE=/absolute/path/to/original/json2dir
```

The black-box suite checks Unicode boundaries, malformed JSON and UTF-8,
path rejection, overwrites, directory merging, dangling and directory symlinks,
executable modes under different umasks, permission errors, stdin errors,
duplicates, number overflow, nesting and large content. Differential tests
compare exit status and complete filesystem snapshots against the Rust binary,
including deterministic generated trees. Exact stderr wording is not compared.

Validated on macOS arm64 with F* v2026.09.27 and OCaml 5.3.0:
all 24 tests passed, including 88 differential inputs against the original Rust
implementation. Linux build configuration is provided but was not run here.

The original license is retained in `LICENSE`.
