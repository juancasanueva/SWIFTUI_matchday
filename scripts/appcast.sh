#!/usr/bin/env bash
#
# Build Matchday's Sparkle appcast for one published release.
#
# What this script is allowed to do: fetch the live feed, fetch and verify the
# pinned signing tool, sign one zip, merge one item, and write the result to an
# output directory. What it deliberately cannot do: publish, tag, retract, or
# select a repository. There is no `git` and no `gh` in it, and
# `AppcastScriptContractTests` asserts both — the release workflow's guarantee
# that it can only ever *create* a release is only worth something if the
# scripts it calls cannot quietly widen it.
#
# It never traces itself. Command tracing would echo the signing pipeline into
# the job log, and the signing pipeline is where the private key is.
#
# Three modes, chosen by the first argument (none means build):
#   scripts/appcast.sh tools   download the pinned Sparkle tarball, check its
#                              digest and extract it into SPARKLE_TOOLS_DIR, then
#                              stop.
#   scripts/appcast.sh fetch   fetch and validate the live feed into
#                              CURRENT_FEED_FILE, then stop.
#   scripts/appcast.sh         build: sign, merge and emit. It reads
#                              CURRENT_FEED_FILE and SPARKLE_TOOLS_DIR when they
#                              are set (CI, after the release exists, never
#                              touching the network again); for each one that is
#                              unset it downloads with the same rules (a local
#                              run).
#
# The release workflow runs `tools` and `fetch` *before* `gh release create`, so
# a download that fails stops the run while nothing is public yet. A failed
# `tools` or `fetch` also removes what an earlier run left at its destination,
# so a stale copy can never be read as this run's.
#
# Environment contract:
#   VERSION              marketing version, without the leading v (1.2.3)
#   BUILD_NUMBER         the build number the release was archived with
#   GITHUB_REF_NAME      the tag; a hyphen in it means prerelease, and no item
#   ASSET_URL            the published zip's download URL
#   ZIP_PATH             the local zip that was published, to be signed
#   FEED_URL             the live feed, fetched so history is preserved;
#                        required whenever this run fetches it
#   CURRENT_FEED_FILE    the pre-fetched feed: written by `fetch`, read by the
#                        build; optional for the build
#   SPARKLE_TOOLS_DIR    the pre-fetched, verified Sparkle tools: written by
#                        `tools`, read by the build; optional for the build
#   FETCH_RETRY_DELAY    seconds before the first retry of any download, a
#                        non-negative integer (default 5); the delay doubles on
#                        each later one
#   OUTPUT_DIR           where appcast.xml is written; never the repository tree
#   SPARKLE_PRIVATE_KEY  the EdDSA private key, read on **stdin only**
#
# Run it by hand exactly as CI runs it: every input is an environment variable
# and nothing is discovered from the checkout.

set -euo pipefail

MODE="${1:-build}"
case "$MODE" in
	tools | fetch | build) ;;
	*)
		echo "usage: scripts/appcast.sh [tools | fetch | build] (no argument means build)" >&2
		exit 2
		;;
esac

# Checked here, before anything runs, so a bad value stops the script at once
# with a message naming it, rather than surfacing after a failed download as an
# arithmetic error inside the retry loop. `10#` drops leading zeros, which shell
# arithmetic would otherwise read as octal.
FETCH_RETRY_DELAY="${FETCH_RETRY_DELAY:-5}"
case "$FETCH_RETRY_DELAY" in
	*[!0-9]*)
		echo "FETCH_RETRY_DELAY must be a non-negative integer number of seconds, got '$FETCH_RETRY_DELAY'" >&2
		exit 2
		;;
esac
FETCH_RETRY_DELAY=$((10#$FETCH_RETRY_DELAY))

# --- guard -------------------------------------------------------------------
# The same literal the workflow uses for `--prerelease`, restated here so a hand
# run behaves identically. A prerelease that reached the feed would be offered
# to every stable user; the version comparison alone would not stop that,
# because the feed is the thing being trusted.
case "$GITHUB_REF_NAME" in
	*-*)
		echo "prerelease $GITHUB_REF_NAME: no appcast item, no download"
		exit 0
		;;
esac

# The pinned signing tool. The version alone would not stop a tampered binary
# from signing the release with an attacker's key, and every installed copy
# would accept the result — the client only checks the signature against the key
# in its own bundle. The digest is what makes that unreachable, and the check
# runs before anything is signed.
SPARKLE_VERSION="2.9.6"
SPARKLE_TARBALL_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
SPARKLE_TARBALL_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
# Written into SPARKLE_TOOLS_DIR by `tools`, holding the digest it verified. The
# build only trusts a directory whose marker names the digest pinned above, and
# `tools` only ever deletes a directory that carries it.
SPARKLE_TOOLS_MARKER=".pinned-sha256"

# The app's own deployment target. It must equal the app target's
# MACOSX_DEPLOYMENT_TARGET, and `AppcastScriptContractTests` reads both and fails
# when they disagree: a feed advertising a lower floor than the build really has
# offers an update that a Mac on an older macOS cannot launch.
MINIMUM_SYSTEM_VERSION="15.6"

# --- fetch -------------------------------------------------------------------
# The merged feed replaces the live one wholesale, so what counts as "no feed
# yet" decides whether history survives. Exactly one answer means that: an HTTP
# 404, the designed state of the very first release, where an empty channel is
# the correct starting point. Every later run merges into whatever is actually
# being served, which is what keeps items for versions a user skipped from
# disappearing.
#
# Everything else stops the run before anything is signed or written: curl
# itself failing (DNS, timeout, TLS), any status other than 200 or 404, and a
# 200 whose body is empty or is not a feed. Treating a transient failure as
# "first release" would replace the live feed with a one-item feed. `curl -f`
# is deliberately not used here: it folds a 404 and a 503 into one exit status.
#
# Every download (the feed here, the Sparkle tarball below) goes through one
# helper, so both are bounded and retried the same way. Every attempt is bounded
# (`--connect-timeout`, `--max-time`), so a stalled endpoint cannot hold the
# signing job. Transient failures are retried by the loop below rather than by
# curl's own `--retry`: that flag retries timeouts and 408/429/5xx, but not a
# DNS failure or a dropped connection, and its `--retry-all-errors` widening
# would retry a 404 too. Here a retry happens only for curl exits 6 (DNS), 7
# (connect), 16 (HTTP/2 framing), 18 (partial transfer), 28 (timeout), 35 (TLS
# handshake), 52 (empty reply), 55/56 (send/receive) and 92 (HTTP/2 stream), and
# for HTTP 408, 429 and 5xx. A 200 and a 404 are answers, never retried; any
# other 4xx, and any other curl exit, is refused at once. Four attempts, 5 s,
# 10 s and 20 s apart by default (FETCH_RETRY_DELAY, validated at the top).
FETCH_ATTEMPTS=4

WORK="$(mktemp -d)"
STAGED=""
cleanup() {
	rm -rf "$WORK"
	if [ -n "$STAGED" ]; then rm -rf "$STAGED"; fi
}
trap cleanup EXIT

# A usable feed: non-empty, with a closing channel tag to insert before.
require_feed() {
	local file="$1" source="$2"
	if [ ! -s "$file" ]; then
		echo "$source is missing or empty; refusing to replace the live feed" >&2
		exit 1
	fi
	case "$(< "$file")" in
		*'</channel>'*) ;;
		*)
			echo "$source has no </channel>; refusing to replace the live feed" >&2
			exit 1
			;;
	esac
}

is_transient() {
	local curl_exit="$1" status="$2"
	case "$curl_exit" in
		6 | 7 | 16 | 18 | 28 | 35 | 52 | 55 | 56 | 92) return 0 ;;
		0) ;;
		*) return 1 ;;
	esac
	case "$status" in
		408 | 429 | 5??) return 0 ;;
		*) return 1 ;;
	esac
}

# download URL BODY MAX_TIME: the one curl call site. Leaves the last attempt's
# curl exit in DOWNLOAD_EXIT, its HTTP status in DOWNLOAD_STATUS and the attempt
# count in DOWNLOAD_ATTEMPTS; deciding what they mean is the caller's job.
download() {
	local url="$1" body="$2" max_time="$3" delay="$FETCH_RETRY_DELAY"
	DOWNLOAD_ATTEMPTS=1
	echo "==> fetch $url"
	while :; do
		rm -f "$body"
		DOWNLOAD_EXIT=0
		DOWNLOAD_STATUS="$(curl -sSL --connect-timeout 10 --max-time "$max_time" -w '%{http_code}' -o "$body" "$url")" ||
			DOWNLOAD_EXIT=$?
		if [ "$DOWNLOAD_ATTEMPTS" -ge "$FETCH_ATTEMPTS" ] || ! is_transient "$DOWNLOAD_EXIT" "$DOWNLOAD_STATUS"; then
			return 0
		fi
		echo "    attempt $DOWNLOAD_ATTEMPTS: curl exit $DOWNLOAD_EXIT, HTTP $DOWNLOAD_STATUS; retrying in ${delay}s"
		sleep "$delay"
		DOWNLOAD_ATTEMPTS=$((DOWNLOAD_ATTEMPTS + 1))
		delay=$((delay * 2))
	done
}

# Fetch the live feed into $1, or exit 1 having written nothing there.
fetch_feed() {
	local dest="$1" body="$WORK/fetched.xml"
	download "$FEED_URL" "$body" 60

	if [ "$DOWNLOAD_EXIT" -ne 0 ]; then
		echo "could not fetch $FEED_URL (curl exit $DOWNLOAD_EXIT, $DOWNLOAD_ATTEMPTS attempt(s)); refusing to replace the live feed" >&2
		exit 1
	fi
	case "$DOWNLOAD_STATUS" in
		200)
			require_feed "$body" "$FEED_URL (HTTP 200)"
			;;
		404)
			echo "    no live feed yet (HTTP 404); starting an empty channel"
			# `<<-` strips leading **tabs** only, so every line of this heredoc,
			# the closing XML included, must be indented with tabs. A space-indented
			# line keeps its spaces, and a closing XML that is not tab-indented
			# never ends the heredoc at all.
			cat > "$body" <<-XML
				<?xml version="1.0" encoding="UTF-8"?>
				<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
					<channel>
						<title>Matchday</title>
						<description>Updates for Matchday</description>
						<language>en</language>
					</channel>
				</rss>
			XML
			;;
		*)
			echo "$FEED_URL answered HTTP $DOWNLOAD_STATUS ($DOWNLOAD_ATTEMPTS attempt(s)); refusing to replace the live feed" >&2
			exit 1
			;;
	esac
	mkdir -p "$(dirname "$dest")"
	mv "$body" "$dest"
}

# --- tool --------------------------------------------------------------------
# Download the pinned tarball, verify its digest and extract it into $1, or exit
# 1 having installed nothing there. The tree is staged next to $1 and renamed
# into place only once it is complete and verified, so a failure part-way never
# leaves a usable-looking directory behind. A 404 here is a failure like any
# other: there is no "first release" of a pinned tarball.
install_tools() {
	local dest="$1" tarball="$WORK/sparkle.tar.xz"
	echo "==> tool Sparkle $SPARKLE_VERSION"
	download "$SPARKLE_TARBALL_URL" "$tarball" 300
	if [ "$DOWNLOAD_EXIT" -ne 0 ] || [ "$DOWNLOAD_STATUS" != 200 ]; then
		echo "could not download $SPARKLE_TARBALL_URL (curl exit $DOWNLOAD_EXIT, HTTP $DOWNLOAD_STATUS, $DOWNLOAD_ATTEMPTS attempt(s))" >&2
		exit 1
	fi
	if ! printf '%s  %s\n' "$SPARKLE_TARBALL_SHA256" "$tarball" | shasum -a 256 -c - > /dev/null; then
		echo "the Sparkle $SPARKLE_VERSION tarball does not match the pinned digest $SPARKLE_TARBALL_SHA256; refusing to sign with it" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$dest")"
	STAGED="$(mktemp -d "$(dirname "$dest")/.sparkle-tools.XXXXXX")"
	tar -xJf "$tarball" -C "$STAGED"
	if [ ! -x "$STAGED/bin/sign_update" ]; then
		echo "the Sparkle $SPARKLE_VERSION tarball has no bin/sign_update" >&2
		exit 1
	fi
	printf '%s\n' "$SPARKLE_TARBALL_SHA256" > "$STAGED/$SPARKLE_TOOLS_MARKER"
	mv "$STAGED" "$dest"
	STAGED=""
}

# Tools another step installed are used only if they carry the marker for the
# digest pinned in this script.
require_tools() {
	local dir="$1"
	if [ ! -x "$dir/bin/sign_update" ] || [ ! -f "$dir/$SPARKLE_TOOLS_MARKER" ] ||
		[ "$(< "$dir/$SPARKLE_TOOLS_MARKER")" != "$SPARKLE_TARBALL_SHA256" ]; then
		echo "the pre-fetched Sparkle tools in $dir are missing or were not verified against $SPARKLE_TARBALL_SHA256; refusing to sign" >&2
		exit 1
	fi
}

# Remove what an earlier `tools` run installed at $1. A directory without the
# marker was not written by this script and is never deleted: SPARKLE_TOOLS_DIR
# comes from the environment, and a mistyped path must not become `rm -rf`.
clear_tools() {
	local dir="$1"
	[ -e "$dir" ] || return 0
	rmdir "$dir" 2> /dev/null && return 0
	if [ ! -f "$dir/$SPARKLE_TOOLS_MARKER" ]; then
		echo "$dir exists and was not written by scripts/appcast.sh tools; refusing to replace it" >&2
		exit 1
	fi
	rm -rf "$dir"
}

if [ "$MODE" = tools ]; then
	SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:?SPARKLE_TOOLS_DIR is required}"
	clear_tools "$SPARKLE_TOOLS_DIR"
	install_tools "$SPARKLE_TOOLS_DIR"
	echo "==> installed $SPARKLE_TOOLS_DIR"
	exit 0
fi

if [ "$MODE" = fetch ]; then
	FEED_URL="${FEED_URL:?FEED_URL is required}"
	CURRENT_FEED_FILE="${CURRENT_FEED_FILE:?CURRENT_FEED_FILE is required}"
	# Gone before the first attempt, so a refused fetch can never leave an
	# earlier run's feed where the build will read it.
	rm -f "$CURRENT_FEED_FILE"
	fetch_feed "$CURRENT_FEED_FILE"
	echo "==> fetched $CURRENT_FEED_FILE"
	exit 0
fi

VERSION="${VERSION:?VERSION is required}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER is required}"
ASSET_URL="${ASSET_URL:?ASSET_URL is required}"
ZIP_PATH="${ZIP_PATH:?ZIP_PATH is required}"
OUTPUT_DIR="${OUTPUT_DIR:?OUTPUT_DIR is required}"

# A pre-fetched feed is read, never re-fetched: in CI the release already exists
# by now, and a missing file means the fetch step did not do its job, not that
# the network should be tried again.
if [ -n "${CURRENT_FEED_FILE:-}" ]; then
	echo "==> read $CURRENT_FEED_FILE"
	require_feed "$CURRENT_FEED_FILE" "the pre-fetched feed $CURRENT_FEED_FILE"
	cp "$CURRENT_FEED_FILE" "$WORK/current.xml"
else
	FEED_URL="${FEED_URL:?FEED_URL is required}"
	fetch_feed "$WORK/current.xml"
fi

# Pre-fetched tools are read, never re-downloaded, for the same reason.
if [ -n "${SPARKLE_TOOLS_DIR:-}" ]; then
	echo "==> tool $SPARKLE_TOOLS_DIR"
	TOOLS="$SPARKLE_TOOLS_DIR"
else
	TOOLS="$WORK/sparkle-tools"
	install_tools "$TOOLS"
fi
require_tools "$TOOLS"

# --- sign --------------------------------------------------------------------
# The key arrives on standard input and is never a file, never an argument, and
# never a redirection target. `--ed-key-file -` exists for exactly this: reading
# the key from a secret environment binding without writing it down anywhere.
# Under `set -u` an unset key aborts here rather than signing with nothing.
echo "==> sign $ZIP_PATH"
FRAGMENT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/bin/sign_update" --ed-key-file - "$ZIP_PATH")"

# The signing tool's output shape is an input to this script, so it is checked
# rather than assumed. Sparkle needs both attributes to verify and download an
# update; a tool whose output shape changed would otherwise emit an item that
# every installed copy rejects, discovered only after the feed was published.
case "$FRAGMENT" in
	*'sparkle:edSignature="'*) ;;
	*) echo "the signing tool emitted no sparkle:edSignature" >&2; exit 1 ;;
esac
case "$FRAGMENT" in
	*'length="'*) ;;
	*) echo "the signing tool emitted no length=" >&2; exit 1 ;;
esac

# --- merge -------------------------------------------------------------------
# One item, prepended, with every prior item preserved in its existing order. A
# bad release is corrected by publishing a higher version, never by deleting a
# feed item: deleting one strands every copy that already saw it.
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
# Written to a file rather than passed with `awk -v`: BSD awk rejects a newline
# inside a `-v` value outright, and the runner is macOS.
cat > "$WORK/item.xml" <<-XML
	        <item>
	            <title>Version ${VERSION}</title>
	            <pubDate>${PUB_DATE}</pubDate>
	            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
	            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
	            <sparkle:minimumSystemVersion>${MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
	            <enclosure url="${ASSET_URL}" ${FRAGMENT} type="application/octet-stream"/>
	        </item>
XML

mkdir -p "$OUTPUT_DIR"
# Inserted before the first existing item, or before the closing channel tag
# when there is none. Newest first, which is the order the feed has always
# had and the order a merge must not disturb.
awk -v itemfile="$WORK/item.xml" '
	!inserted && ($0 ~ /<item>/ || $0 ~ /<\/channel>/) {
		while ((getline line < itemfile) > 0) { print line }
		close(itemfile)
		inserted = 1
	}
	{ print }
' "$WORK/current.xml" > "$OUTPUT_DIR/appcast.xml"

# --- emit --------------------------------------------------------------------
# Nothing is written into the repository tree, so there is no new stowaway
# surface, no `.gitignore` change, and nothing for a later step to commit.
echo "==> emit $OUTPUT_DIR/appcast.xml"
