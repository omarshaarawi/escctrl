# escctrl tasks. Run `just` to list.

cli_dir := "/usr/local/bin"

default:
    @just --list

# Build (debug)
build:
    swift build

# Run the unit tests
test:
    swift test

# Run the agent in the foreground (the running binary needs Accessibility permission)
run:
    swift run escctrl

# Assemble a signed (ad-hoc) escctrl.app in dist/ for the host arch
bundle:
    scripts/bundle.sh --release

# Assemble a universal (arm64 + x86_64) escctrl.app
bundle-universal:
    scripts/bundle.sh --release --universal

# Build, install to /Applications, and symlink the CLI onto your PATH
install: bundle
    rm -rf /Applications/escctrl.app
    cp -R dist/escctrl.app /Applications/escctrl.app
    ln -sf /Applications/escctrl.app/Contents/MacOS/escctrl {{cli_dir}}/escctrl
    @echo "Installed. Launch with: open -a escctrl   (grant Accessibility on first run)"

# Quit the agent, remove the app and the CLI symlink
uninstall:
    -escctrl quit
    rm -rf /Applications/escctrl.app
    rm -f {{cli_dir}}/escctrl

# Format sources in place
format:
    swift format --in-place --recursive Sources

# Remove build artifacts
clean:
    rm -rf .build dist
