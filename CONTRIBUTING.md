# Contributing to mapi

Practical guide for contributing to the `mapi` project.

## Prerequisites

- [MoonBit CLI](https://www.moonbitlang.com/download)
- [just](https://github.com/casey/just)

## Getting Started

1. Clone the repository
2. Install dependencies:
```bash
moon install
```

## Development Workflow

Use `just` to manage the project lifecycle. All commands should be run from the repository root.

| Command | Description |
|:--- |:--- |
| `just check` | Type-check the whole workspace |
| `just build` | Build all packages |
| `just test` | Run all tests |
| `just fmt` | Format all source files |
| `just fmt-check` | Check formatting without modifying files |
| `just clean` | Remove build artifacts |
| `just run [args]` | Run the CLI (pass args after `--`) |
| `just install` | Build and install the `mapi` binary locally |

## Code Style

MoonBit code must be formatted using the official formatter. Run this before committing:

```bash
just fmt
```

Continuous Integration runs `just fmt-check` to ensure compliance.

## Running Tests

Verify your changes by running the test suite:

```bash
just test
```

## Local Installation

To install the `mapi` binary to `~/.local/bin/mapi`:

```bash
just install
```

You can override the installation directory by setting `MAPI_INSTALL_DIR`.

## Pull Requests

1. Fork the repository
2. Create a feature branch
3. Ensure all checks pass: `just fmt-check && just check && just test`
4. Submit a Pull Request
