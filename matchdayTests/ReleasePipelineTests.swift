//
//  ReleasePipelineTests.swift
//  matchdayTests
//
//  Cheap contract tests over the release pipeline's files: scripts/release.sh,
//  scripts/appcast.sh, scripts/ExportOptions.plist and
//  .github/workflows/release.yml. They read the repository off disk, so a
//  pipeline that drifts from the app it ships (product name, feed URL, minimum
//  system version) fails here rather than after a tag has been pushed.
//

import Foundation
import Testing

/// Reads the repository off disk. The `#filePath` anchor is used because the
/// test runner promises nothing about the working directory, and the test host
/// is not sandboxed, so the checkout is readable.
enum ReleasePipelineSources {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // matchdayTests
            .deletingLastPathComponent()   // repository root
    }

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    static func text(_ relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    static func plist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: url(relativePath))
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(object as? [String: Any])
    }

    static let releaseScript = "scripts/release.sh"
    static let appcastScript = "scripts/appcast.sh"
    static let exportOptions = "scripts/ExportOptions.plist"
    static let workflow = ".github/workflows/release.yml"
    static let infoPlist = "Resources/Matchday-Info.plist"
    static let projectFile = "matchday.xcodeproj/project.pbxproj"

    /// Every capture of `pattern`'s first group in `text`.
    static func captures(_ pattern: String, in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Script lines with comments and blank lines removed, so a word that only
    /// appears in prose never satisfies or fails an assertion about code.
    static func codeLines(_ relativePath: String) throws -> [String] {
        try text(relativePath)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }
}

@Suite("Release pipeline files")
struct ReleasePipelineFilesTests {
    @Test(arguments: [ReleasePipelineSources.releaseScript, ReleasePipelineSources.appcastScript])
    func scriptsAreExecutableAndFailOnTheFirstError(path: String) throws {
        let url = ReleasePipelineSources.url(path)
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        let code = try ReleasePipelineSources.codeLines(path)
        #expect(code.contains("set -euo pipefail"))
    }

    @Test(arguments: [ReleasePipelineSources.releaseScript, ReleasePipelineSources.appcastScript])
    func scriptsCannotPublishOrTraceThemselves(path: String) throws {
        let code = try ReleasePipelineSources.codeLines(path)
        let invocations = code.filter { line in
            line.range(of: #"(^|[\s;|&(])(git|gh)\s"#, options: .regularExpression) != nil
        }
        #expect(invocations.isEmpty, "publishing belongs to the workflow: \(invocations)")
        #expect(!code.contains { $0.range(of: #"set\s+-[a-z]*x"#, options: .regularExpression) != nil })
    }

    @Test func exportOptionsDeclareManualDeveloperIDSigning() throws {
        let options = try ReleasePipelineSources.plist(ReleasePipelineSources.exportOptions)
        #expect(options["method"] as? String == "developer-id")
        #expect(options["signingStyle"] as? String == "manual")
        #expect(options["signingCertificate"] as? String == "Developer ID Application")
        #expect(options["teamID"] as? String == "Z3S5JK8E38")
    }
}

@Suite("Release script contract")
struct ReleaseScriptContractTests {
    @Test func buildsTheMatchdayProductFromTheMatchdayScheme() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.releaseScript)
        #expect(script.contains(#"readonly SCHEME="matchday""#))
        #expect(script.contains(#"readonly PRODUCT="Matchday""#))
        #expect(script.contains(#"readonly PROJECT="matchday.xcodeproj""#))
        #expect(script.contains("ARCHS=arm64"))
    }

    @Test func packagesTheAssetAsMatchdayVersionZip() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.releaseScript)
        #expect(script.contains(#"ZIP="$BUILD/Matchday-$VERSION.zip""#))
    }

    @Test func refusesABundleThatCarriesTheAppSandbox() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.releaseScript)
        #expect(script.contains("grep -q 'com.apple.security.app-sandbox'"))
        #expect(script.contains(#"fail "the delivered bundle carries an app-sandbox entitlement""#))
    }

    @Test func stapleDeletesThePreNotarizationZipBeforeRepackaging() throws {
        let code = try ReleasePipelineSources.codeLines(ReleasePipelineSources.releaseScript)
        let staple = try #require(code.firstIndex(of: #"xcrun stapler staple "$APP""#))
        let delete = try #require(code.firstIndex(of: #"rm -f "$ZIP""#))
        #expect(staple < delete)
    }
}

@Suite("Appcast script contract")
struct AppcastScriptContractTests {
    @Test func pinsTheSigningToolBySHA256() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.appcastScript)
        #expect(script.contains(#"SPARKLE_VERSION="2.9.6""#))
        let digests = try ReleasePipelineSources.captures(#"^SPARKLE_TARBALL_SHA256="([0-9a-f]{64})"$"#, in: script)
        #expect(digests == ["52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"])
    }

    @Test func readsThePrivateKeyOnStandardInputOnly() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.appcastScript)
        #expect(script.contains(#"printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/bin/sign_update" --ed-key-file - "$ZIP_PATH""#))
        let mentions = try ReleasePipelineSources.codeLines(ReleasePipelineSources.appcastScript)
            .filter { $0.contains("SPARKLE_PRIVATE_KEY") }
        #expect(mentions.count == 1)
    }

    @Test func minimumSystemVersionIsTheAppDeploymentTarget() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.appcastScript)
        let emitted = try ReleasePipelineSources.captures(#"^MINIMUM_SYSTEM_VERSION="([0-9.]+)"$"#, in: script)
        let project = try ReleasePipelineSources.text(ReleasePipelineSources.projectFile)
        // The app target is the one whose configurations name Matchday-Info.plist.
        let appTargets = try ReleasePipelineSources.captures(
            #"INFOPLIST_FILE = "Resources/Matchday-Info.plist";[\s\S]*?MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);"#,
            in: project
        )
        #expect(!appTargets.isEmpty)
        #expect(Set(appTargets).count == 1)
        #expect(emitted == [try #require(appTargets.first)])
    }

    @Test func anEmptyChannelIsTitledMatchday() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.appcastScript)
        #expect(script.contains("<title>Matchday</title>"))
    }

    @Test func aPrereleaseTagFetchesNothingAndSucceeds() throws {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("matchday-appcast-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [ReleasePipelineSources.url(ReleasePipelineSources.appcastScript).path, "fetch"]
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "GITHUB_REF_NAME": "v1.0.0-rc.1",
            // Unreachable on purpose: a prerelease must stop before any download.
            "FEED_URL": "http://127.0.0.1:9/appcast.xml",
            "CURRENT_FEED_FILE": output.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}

@Suite("Release workflow contract")
struct ReleaseWorkflowContractTests {
    @Test func isTriggeredOnlyByAPushedVersionTag() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        #expect(workflow.contains("on:\n  push:\n    tags: ['v*']\n"))
        for trigger in ["pull_request", "workflow_dispatch", "branches:", "schedule:", "workflow_run"] {
            #expect(!workflow.contains(trigger), "unexpected trigger \(trigger)")
        }
    }

    @Test func referencesExactlyTheSevenReleaseSecrets() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        let secrets = Set(try ReleasePipelineSources.captures(#"secrets\.([A-Z0-9_]+)"#, in: workflow))
        #expect(secrets == [
            "BUILD_CERTIFICATE_BASE64", "P12_PASSWORD", "KEYCHAIN_PASSWORD",
            "APPLE_API_KEY_P8", "APPLE_API_KEY_ID", "APPLE_API_ISSUER_ID",
            "SPARKLE_PRIVATE_KEY",
        ])
    }

    @Test func fetchesTheFeedTheAppReads() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        let info = try ReleasePipelineSources.plist(ReleasePipelineSources.infoPlist)
        let feed = try #require(info["SUFeedURL"] as? String)
        let urls = try ReleasePipelineSources.captures(#"^\s*FEED_URL: (\S+)$"#, in: workflow)
        #expect(urls == [feed])
    }

    @Test func publishesAndSignsTheAssetTheScriptPackages() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        #expect(workflow.contains(#"gh release create "$GITHUB_REF_NAME" "build/Matchday-${VERSION}.zip""#))
        #expect(workflow.contains("--verify-tag --generate-notes"))
        #expect(workflow.contains("/releases/download/${{ github.ref_name }}/Matchday-${{ env.VERSION }}.zip"))
        #expect(workflow.contains("ZIP_PATH: build/Matchday-${{ env.VERSION }}.zip"))
    }

    @Test func deletesTheEphemeralKeychainUnconditionally() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        let keychains = Set(try ReleasePipelineSources.captures(#"(\$RUNNER_TEMP/[\w-]+\.keychain-db)"#, in: workflow))
        #expect(keychains == ["$RUNNER_TEMP/matchday-release.keychain-db"])
        #expect(workflow.contains("- name: Delete the ephemeral keychain and the API key\n        if: always()"))
    }

    /// Every stable run fetches the live feed, prepends its item and redeploys
    /// the whole site, so two runs in flight at once would each drop the
    /// other's item. One constant group serializes them across tags.
    @Test func feedRunsAreSerializedAcrossTags() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        #expect(workflow.contains("concurrency:\n  group: release-feed\n  cancel-in-progress: false"))
        let groups = try ReleasePipelineSources.captures(#"^\s*group: (.+)$"#, in: workflow)
        #expect(groups == ["release-feed"])
    }

    @Test func everyActionIsPinnedToACommitSHA() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        let uses = try ReleasePipelineSources.captures(#"uses: (\S+)"#, in: workflow)
        #expect(!uses.isEmpty)
        for action in uses {
            #expect(action.range(of: #"@[0-9a-f]{40}$"#, options: .regularExpression) != nil, "\(action)")
        }
    }
}

/// Runs the distinct-commit gate's own shell, as written in the workflow,
/// against a stand-in `curl` that answers with a chosen Pages status.
@Suite("Release workflow distinct-commit gate")
struct DistinctCommitGateTests {
    static let stepName = "- name: Refuse a second feed deployment from this commit"

    /// The `run: |` block of the gate step, dedented.
    static func gateScript() throws -> String {
        let lines = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
            .components(separatedBy: "\n")
        let step = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == stepName })
        let run = try #require(lines[step...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "run: |" })
        let runIndent = lines[run].prefix { $0 == " " }.count
        var body: [String] = []
        for line in lines[(run + 1)...] {
            let indent = line.prefix { $0 == " " }.count
            if !line.trimmingCharacters(in: .whitespaces).isEmpty && indent <= runIndent { break }
            body.append(line)
        }
        let indent = try #require(body.first).prefix { $0 == " " }.count
        return body.map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " }.count))) }
            .joined(separator: "\n")
    }

    static func exitStatus(forPagesStatus status: String) throws -> Int32 {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("matchday-gate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let curl = directory.appendingPathComponent("curl")
        try Data(#"#!/bin/bash\#nprintf '{"status":"%s"}' "$FAKE_STATUS"\#n"#.utf8).write(to: curl)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", try gateScript()]
        process.environment = [
            "PATH": "\(directory.path):/usr/bin:/bin",
            "GITHUB_REPOSITORY": "juancasanueva/SWIFTUI_matchday",
            "GITHUB_SHA": "0123456789abcdef0123456789abcdef01234567",
            "RELEASE_TOKEN": "test-token",
            "FAKE_STATUS": status,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func aCommitPagesHasNeverDeployedPasses() throws {
        #expect(try Self.exitStatus(forPagesStatus: "") == 0)
    }

    @Test func aCommitThatAlreadyDeployedIsRefused() throws {
        #expect(try Self.exitStatus(forPagesStatus: "succeed") != 0)
    }

    /// RELEASING.md's recovery is "delete the release and re-run": a deployment
    /// that never went live must not lock its commit out of the feed.
    @Test(arguments: ["deployment_failed", "deployment_content_failed", "deployment_cancelled",
                      "deployment_attempt_error", "deployment_lost"])
    func aFailedDeploymentCanBeRetried(status: String) throws {
        #expect(try Self.exitStatus(forPagesStatus: status) == 0)
    }

    /// A deployment still in flight, or a status this gate does not know, is not
    /// proof the feed is free.
    @Test(arguments: ["deployment_in_progress", "syncing_files", "something_new"])
    func anUnfinishedOrUnknownStatusIsRefused(status: String) throws {
        #expect(try Self.exitStatus(forPagesStatus: status) != 0)
    }
}

/// The smoke phase launches the delivered app and fails the release if it does
/// not stay up: 1.0.0–1.0.2 shipped an optimized build that crashed at launch,
/// which no Debug-built unit test could see.
@Suite("Release smoke launch")
struct ReleaseSmokeLaunchTests {
    @Test func theScriptLaunchesTheVerifiedApp() throws {
        let script = try ReleasePipelineSources.text(ReleasePipelineSources.releaseScript)
        #expect(script.contains("phase_smoke() {"))
        #expect(script.contains("smoke) phase_smoke ;;"))
        #expect(script.contains(#"SMOKE_BINARY:-$VERIFIED_APP/Contents/MacOS/$PRODUCT"#))
        #expect(script.contains("  smoke      "))
    }

    @Test func theWorkflowSmokesAfterVerifyAndBeforePublishing() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflow)
        let verify = try #require(workflow.range(of: "run: scripts/release.sh verify"))
        let smoke = try #require(workflow.range(of: "run: scripts/release.sh smoke"))
        let publish = try #require(workflow.range(of: #"gh release create "$GITHUB_REF_NAME""#))
        #expect(verify.upperBound < smoke.lowerBound)
        #expect(smoke.upperBound < publish.lowerBound)
    }

    /// A stand-in binary: one that exits at once must fail the phase, one that
    /// keeps running must pass it.
    @Test(arguments: [("exit 3", false), ("sleep 30", true)])
    func thePhaseFailsOnlyWhenTheAppExits(body: String, passes: Bool) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("matchday-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("fake-app")
        try "#!/bin/bash\n\(body)\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [ReleasePipelineSources.url(ReleasePipelineSources.releaseScript).path, "smoke"]
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "VERSION": "0.0.0",
            "RELEASE_BUILD_DIR": directory.path,
            "SMOKE_BINARY": binary.path,
            "SMOKE_SECONDS": "2",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        #expect((process.terminationStatus == 0) == passes)
    }
}
