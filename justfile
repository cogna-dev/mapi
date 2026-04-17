# mapi — Project Lifecycle
# Run `just <command>` from the repo root.

install_dir := env_var_or_default("MAPI_INSTALL_DIR", "~/.local/bin")
binary      := "_build/native/release/build/main/main.exe"

# Show available commands
default:
    @just --list

# Type-check the whole workspace
check:
    moon check

# Build all packages
build:
    moon build

# Run all tests
test:
    moon test

# Format all source files
fmt:
    moon fmt

# Format check without modifying files
fmt-check:
    moon fmt --check

# Remove build artifacts
clean:
    moon clean

# Run the CLI (pass args after --)
run *args:
    moon run main -- {{args}}

# Compile the mapi CLI as a native binary and install it to ~/.local/bin (or $MAPI_INSTALL_DIR)
install:
    moon build main --target native --release
    mkdir -p {{install_dir}}
    cp {{binary}} {{install_dir}}/mapi
    @echo "mapi installed → {{install_dir}}/mapi"
