#!/bin/bash
#
# release.sh — archive, export, package, notarize, staple and verify a
# Developer ID build of Matchday.
#
# This is the build sequence, not a publishing path. It contains no version
# control and no release-management invocation of any kind, so it can neither
# select a repository nor publish, tag, or retract anything, whatever directory
# it is run from. Publication lives only in .github/workflows/release.yml.
# It also never creates, unlocks, or imports into a keychain: the workflow owns
# credentials, this file owns the build, and running these exact commands
# locally is what makes the local rehearsal a rehearsal rather than an
# approximation of one.
#
# Usage:
#   scripts/release.sh <archive|export|package|notarize|staple|verify|all>
#
# Environment:
#   VERSION            marketing version, e.g. 1.0.0                — all phases
#   BUILD_NUMBER       CURRENT_PROJECT_VERSION            — archive/export/verify
#   ASC_KEY_PATH       App Store Connect API key (.p8) path
#   ASC_KEY_ID         App Store Connect API key id
#   ASC_ISSUER_ID      App Store Connect issuer id
#                      — notarize, and archive/export when SIGNING_STYLE=automatic
#   SIGNING_STYLE      manual (default) or automatic
#   RELEASE_BUILD_DIR  output root, default "build" (excluded from the repository)
#   SMOKE_SECONDS      how long the delivered app must stay up, default 20  — smoke
#   SMOKE_BINARY       executable to launch instead of the verified app (tests) — smoke
#
# Signing style: `manual` signs the archive directly with the Developer ID
# Application identity already present in the keychain and asks Apple for
# nothing. `automatic` lets Xcode manage signing through the App Store Connect
# key, which on a fresh CI runner mints a new "Created via API" Mac Development
# certificate on every run; Apple caps those at ten per team.

set -euo pipefail

readonly TEAM_ID="Z3S5JK8E38"
readonly SCHEME="matchday"
# The Xcode target and scheme are called `matchday` (and so is the Swift
# module), but the product it produces is `Matchday.app` with
# `Contents/MacOS/Matchday`. One constant cannot mean both: `SCHEME` names
# what xcodebuild is asked to build, `PRODUCT` names what comes out.
readonly PRODUCT="Matchday"
readonly PROJECT="matchday.xcodeproj"
readonly EXPORT_OPTIONS="scripts/ExportOptions.plist"

# The repository root is resolved from this file's own location, never from the
# working directory: a build that silently picks up whichever checkout happens
# to be current is a build nobody can reason about.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SIGNING_STYLE="${SIGNING_STYLE:-manual}"
BUILD="${RELEASE_BUILD_DIR:-build}"

ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD/export"
APP="$EXPORT_DIR/$PRODUCT.app"
VERIFY_DIR="$BUILD/verify"
VERIFIED_APP="$VERIFY_DIR/$PRODUCT.app"
ZIP=""
SIGN_FLAGS=()
ARCHIVE_SETTINGS=()

usage() {
	cat >&2 <<'USAGE'
usage: scripts/release.sh <phase>

phases:
  archive    Build a Release archive stamped with VERSION / BUILD_NUMBER
  export     Export a Developer ID app, then gate its version and architecture
  package    ditto the exported app into Matchday-<version>.zip
  notarize   Submit the archive and wait for Apple's verdict
  staple     Staple the ticket, then repackage so the asset carries it
  verify     Re-check every claim against the copy extracted from the zip
  smoke      Launch the verified app and fail unless it stays up
  all        Run the seven phases above in order (the local rehearsal)
USAGE
}

fail() {
	echo "error: $*" >&2
	exit 1
}

require_env() {
	local name
	for name in "$@"; do
		if [ -z "${!name:-}" ]; then
			fail "$name must be set (see the header of scripts/release.sh)"
		fi
	done
}

expect_equal() {
	local actual="$1" expected="$2" what="$3"
	if [ "$actual" != "$expected" ]; then
		fail "$what is '$actual', expected '$expected'"
	fi
}

# Manual signing overrides the project's `CODE_SIGN_STYLE = Automatic` on the
# archive line and pins the Developer ID identity, so the archive is signed with
# the imported certificate and never with a freshly minted Development one.
# Automatic signing needs the App Store Connect key instead. The export options
# plist carries the matching `signingStyle`; the two must agree, so
# `SIGNING_STYLE` is checked against it before xcodebuild runs.
configure_signing() {
	SIGN_FLAGS=()
	ARCHIVE_SETTINGS=()
	expect_equal \
		"$(plutil -extract signingStyle raw -o - "$EXPORT_OPTIONS")" \
		"$SIGNING_STYLE" "signingStyle in $EXPORT_OPTIONS"
	case "$SIGNING_STYLE" in
	automatic)
		require_env ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
		SIGN_FLAGS=(
			-allowProvisioningUpdates
			-authenticationKeyPath "$ASC_KEY_PATH"
			-authenticationKeyID "$ASC_KEY_ID"
			-authenticationKeyIssuerID "$ASC_ISSUER_ID"
		)
		;;
	manual)
		ARCHIVE_SETTINGS=(
			CODE_SIGN_STYLE=Manual
			"CODE_SIGN_IDENTITY=Developer ID Application"
			"DEVELOPMENT_TEAM=$TEAM_ID"
		)
		;;
	*) fail "SIGNING_STYLE must be 'automatic' or 'manual', not '$SIGNING_STYLE'" ;;
	esac
}

phase_archive() {
	require_env VERSION BUILD_NUMBER
	configure_signing
	echo "==> archive $VERSION ($BUILD_NUMBER)"

	rm -rf "$ARCHIVE_PATH"
	mkdir -p "$BUILD"
	xcodebuild archive \
		-project "$PROJECT" \
		-scheme "$SCHEME" \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-archivePath "$ARCHIVE_PATH" \
		ARCHS=arm64 \
		ONLY_ACTIVE_ARCH=NO \
		MARKETING_VERSION="$VERSION" \
		CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
		${ARCHIVE_SETTINGS[@]+"${ARCHIVE_SETTINGS[@]}"} \
		${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}
}

# First of two gate passes: refuse to spend an Apple round trip on a mislabelled
# or wrongly built app. The second pass runs in `verify`, against the copy
# extracted from the published zip.
phase_export() {
	require_env VERSION
	configure_signing
	echo "==> export"

	rm -rf "$EXPORT_DIR"
	xcodebuild -exportArchive \
		-archivePath "$ARCHIVE_PATH" \
		-exportOptionsPlist "$EXPORT_OPTIONS" \
		-exportPath "$EXPORT_DIR" \
		${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"}

	expect_equal \
		"$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" \
		"$VERSION" "the exported CFBundleShortVersionString"
	expect_equal \
		"$(lipo -archs "$APP/Contents/MacOS/$PRODUCT")" \
		"arm64" "the exported architecture"
}

phase_package() {
	require_env VERSION
	echo "==> package $ZIP"

	mkdir -p "$BUILD"
	ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
}

phase_notarize() {
	require_env VERSION ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
	echo "==> notarize"

	local response status submission
	response="$(xcrun notarytool submit "$ZIP" \
		--key "$ASC_KEY_PATH" \
		--key-id "$ASC_KEY_ID" \
		--issuer "$ASC_ISSUER_ID" \
		--wait --output-format json)" || response=""

	printf '%s\n' "$response"
	status="$(printf '%s' "$response" | plutil -extract status raw -o - - 2>/dev/null || true)"
	submission="$(printf '%s' "$response" | plutil -extract id raw -o - - 2>/dev/null || true)"

	if [ "$status" != "Accepted" ]; then
		# The diagnostic log is surfaced rather than the run silently retrying
		# past the gate. Nothing is published either way.
		if [ -n "$submission" ]; then
			xcrun notarytool log "$submission" \
				--key "$ASC_KEY_PATH" \
				--key-id "$ASC_KEY_ID" \
				--issuer "$ASC_ISSUER_ID" >&2 || true
		fi
		fail "notarization did not succeed (status: ${status:-unknown})"
	fi
}

phase_staple() {
	require_env VERSION
	echo "==> staple"

	xcrun stapler staple "$APP"
	# `ditto` into an existing archive path adds to it rather than replacing it,
	# so the pre-notarization zip is deleted before the app is packaged again.
	# The published asset can then only be the stapled one — otherwise a
	# stranger's first launch would need network access to succeed.
	rm -f "$ZIP"
	phase_package
}

# Every gate here runs on the copy extracted from the archive that is about to
# be published, which is what makes each one a statement about the artifact
# users download rather than about an intermediate build product.
phase_verify() {
	require_env VERSION BUILD_NUMBER
	echo "==> verify"

	rm -rf "$VERIFY_DIR"
	mkdir -p "$VERIFY_DIR"
	ditto -x -k "$ZIP" "$VERIFY_DIR"

	spctl -a -vvv -t install "$VERIFIED_APP"
	xcrun stapler validate "$VERIFIED_APP"
	codesign --verify --strict --verbose=2 "$VERIFIED_APP"

	local signing
	signing="$(codesign -dvvv "$VERIFIED_APP" 2>&1)"
	printf '%s\n' "$signing" >"$BUILD/codesign.txt"
	printf '%s\n' "$signing" | grep -q 'flags=0x10000(runtime)'
	printf '%s\n' "$signing" | grep -q 'Authority=Developer ID Application'
	printf '%s\n' "$signing" | grep -q "TeamIdentifier=$TEAM_ID"

	# The sandbox must be absent, and the check must be able to fail. `grep -qv`
	# succeeds as soon as any one line differs, so it never fails; and a bare
	# `! pipeline` is exempt from `set -e` by definition, so it cannot fail the
	# script either. An explicit branch is the only form of this gate that gates.
	# The output is captured first: under `pipefail`, `grep -q` closing the pipe
	# early would turn a real match into status 141 and skip the branch.
	local entitlements
	entitlements="$(codesign -d --entitlements :- "$VERIFIED_APP" 2>&1)"
	if printf '%s\n' "$entitlements" | grep -q 'com.apple.security.app-sandbox'; then
		fail "the delivered bundle carries an app-sandbox entitlement"
	fi

	expect_equal \
		"$(lipo -archs "$VERIFIED_APP/Contents/MacOS/$PRODUCT")" \
		"arm64" "the delivered architecture"
	expect_equal \
		"$(plutil -extract CFBundleShortVersionString raw -o - "$VERIFIED_APP/Contents/Info.plist")" \
		"$VERSION" "the delivered CFBundleShortVersionString"
	expect_equal \
		"$(plutil -extract CFBundleVersion raw -o - "$VERIFIED_APP/Contents/Info.plist")" \
		"$BUILD_NUMBER" "the delivered CFBundleVersion"
	# The project sets no CFBundleDisplayName, so the name Finder, Sparkle and
	# the Homebrew cask see is CFBundleName, which PRODUCT_NAME generates.
	expect_equal \
		"$(plutil -extract CFBundleName raw -o - "$VERIFIED_APP/Contents/Info.plist")" \
		"$PRODUCT" "the delivered CFBundleName"
	expect_equal \
		"$(plutil -extract CFBundleIdentifier raw -o - "$VERIFIED_APP/Contents/Info.plist")" \
		"com.juancasanueva.matchday" "the delivered CFBundleIdentifier"

	# Nothing from scripts/ or .github/ may travel inside the bundle.
	# `matchday/` is a synchronized root group, so this is the gate that
	# catches a release file dropped into it by mistake.
	local stowaways
	stowaways="$(find "$VERIFIED_APP/Contents" \
		\( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name 'ExportOptions*.plist' \) \
		-print)"
	if [ -n "$stowaways" ]; then
		printf 'error: release infrastructure shipped inside the bundle:\n%s\n' "$stowaways" >&2
		exit 1
	fi

	echo "==> verified $ZIP"
}

# The verify gates prove what the artifact is, not that it runs. 1.0.0-1.0.2
# shipped an optimized build that crashed within a second of launch, which no
# Debug-built unit test could see, so the delivered binary itself is started
# and must still be alive SMOKE_SECONDS later.
phase_smoke() {
	local binary="${SMOKE_BINARY:-$VERIFIED_APP/Contents/MacOS/$PRODUCT}"
	local seconds="${SMOKE_SECONDS:-20}"
	echo "==> smoke (${seconds}s)"

	[ -x "$binary" ] || fail "no app to launch at $binary (run verify first)"
	mkdir -p "$BUILD"

	# A watchdog marks survival after SMOKE_SECONDS and then stops the app; the
	# phase waits on the app itself. Polling with `kill -0` is not enough: a
	# crashed app that bash has not reaped yet is a zombie, and signalling a
	# zombie succeeds, so a crash could pass the gate under load.
	local survived="$BUILD/smoke.survived"
	rm -f "$survived"
	"$binary" >"$BUILD/smoke.log" 2>&1 &
	local pid=$!
	(sleep "$seconds" && touch "$survived" && kill "$pid" 2>/dev/null) &
	local watchdog=$!

	local status=0
	wait "$pid" || status=$?
	if [ ! -f "$survived" ]; then
		pkill -P "$watchdog" 2>/dev/null || true
		kill "$watchdog" 2>/dev/null || true
		tail -n 20 "$BUILD/smoke.log" >&2 || true
		fail "the delivered app exited before ${seconds}s with status $status"
	fi
	wait "$watchdog" 2>/dev/null || true
	rm -f "$survived"
	echo "==> smoke passed: the app stayed up for ${seconds}s"
}

main() {
	local phase="${1:-}"

	case "$phase" in
	archive | export | package | notarize | staple | verify | smoke | all) ;;
	*)
		usage
		exit 1
		;;
	esac

	require_env VERSION
	ZIP="$BUILD/Matchday-$VERSION.zip"

	case "$phase" in
	archive) phase_archive ;;
	export) phase_export ;;
	package) phase_package ;;
	notarize) phase_notarize ;;
	staple) phase_staple ;;
	verify) phase_verify ;;
	smoke) phase_smoke ;;
	all)
		phase_archive
		phase_export
		phase_package
		phase_notarize
		phase_staple
		phase_verify
		phase_smoke
		;;
	esac
}

main "$@"
