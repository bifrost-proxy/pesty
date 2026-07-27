import Foundation

enum UpdaterVerifier {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        guard UpdateManager.automaticCheckInterval == 3_600 else {
            throw Failure(description: "automatic update interval is not one hour")
        }
        guard UpdateService.isNewer("1.3.3", than: "1.3.2"),
              UpdateService.isNewer("2.0.0", than: "1.99.99"),
              UpdateService.isNewer("1.4.0-beta.2", than: "1.4.0-beta.1"),
              !UpdateService.isNewer("1.3.2", than: "1.3.2"),
              !UpdateService.isNewer("1.2.9", than: "1.3.2"),
              !UpdateService.isNewer("1.4.0-beta.1", than: "1.4.0"),
              !UpdateService.isNewer("invalid", than: "1.3.2") else {
            throw Failure(description: "semantic version comparison is incorrect")
        }

        let fixture = """
        {
          "tag_name": "v1.3.3",
          "draft": false,
          "prerelease": false,
          "assets": [{
            "name": "Pesty-1.3.3.dmg",
            "browser_download_url": "https://github.com/bifrost-proxy/pesty/releases/download/v1.3.3/Pesty-1.3.3.dmg",
            "digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
          }]
        }
        """
        let release = try UpdateService.decodeRelease(
            Data(fixture.utf8),
            requiredChannel: .stable
        )
        guard release.version == "1.3.3",
              release.channel == .stable,
              release.sha256 == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" else {
            throw Failure(description: "release decoding did not preserve version and digest")
        }

        let betaList = """
        [
          {
            "tag_name": "v1.4.0",
            "draft": false,
            "prerelease": false,
            "assets": []
          },
          {
            "tag_name": "v1.4.0-beta.1",
            "draft": false,
            "prerelease": true,
            "assets": [{
              "name": "Pesty-1.4.0-beta.1.dmg",
              "browser_download_url": "https://github.com/bifrost-proxy/pesty/releases/download/v1.4.0-beta.1/Pesty-1.4.0-beta.1.dmg",
              "digest": "sha256:1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            }]
          },
          {
            "tag_name": "v1.4.0-beta.2",
            "draft": false,
            "prerelease": true,
            "assets": [{
              "name": "Pesty-1.4.0-beta.2.dmg",
              "browser_download_url": "https://github.com/bifrost-proxy/pesty/releases/download/v1.4.0-beta.2/Pesty-1.4.0-beta.2.dmg",
              "digest": "sha256:2123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            }]
          }
        ]
        """
        let beta = try UpdateService.decodeReleaseList(
            Data(betaList.utf8),
            requiredChannel: .beta
        )
        guard beta.version == "1.4.0-beta.2", beta.channel == .beta else {
            throw Failure(description: "beta channel did not select the latest beta")
        }

        let atomFixture = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:github.com,2008:Repository/1/v1.4.0-beta.2</id>
            <link rel="alternate" type="text/html" href="https://github.com/bifrost-proxy/pesty/releases/tag/v1.4.0-beta.2"/>
            <content type="html">&lt;p&gt;SHA-256: &lt;code&gt;2123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef&lt;/code&gt;&lt;/p&gt;</content>
          </entry>
          <entry>
            <id>tag:github.com,2008:Repository/1/v1.4.0-beta.1</id>
            <link rel="alternate" type="text/html" href="https://github.com/bifrost-proxy/pesty/releases/tag/v1.4.0-beta.1"/>
            <content type="html">&lt;p&gt;SHA-256: &lt;code&gt;1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef&lt;/code&gt;&lt;/p&gt;</content>
          </entry>
          <entry>
            <id>tag:github.com,2008:Repository/1/v1.3.3</id>
            <link rel="alternate" type="text/html" href="https://github.com/bifrost-proxy/pesty/releases/tag/v1.3.3"/>
            <content type="html">&lt;p&gt;SHA-256: &lt;code&gt;3123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef&lt;/code&gt;&lt;/p&gt;</content>
          </entry>
        </feed>
        """
        let atomBeta = try UpdateService.decodeAtomFeed(
            Data(atomFixture.utf8),
            requiredChannel: .beta
        )
        let atomStable = try UpdateService.decodeAtomFeed(
            Data(atomFixture.utf8),
            requiredChannel: .stable
        )
        guard atomBeta.version == "1.4.0-beta.2",
              atomBeta.channel == .beta,
              atomStable.version == "1.3.3",
              atomStable.channel == .stable else {
            throw Failure(description: "Atom feed did not preserve Stable/Beta isolation")
        }
        do {
            _ = try UpdateService.decodeAtomFeed(
                Data(atomFixture.replacingOccurrences(
                    of: "SHA-256:",
                    with: "unlabelled digest:"
                ).utf8),
                requiredChannel: .beta
            )
            throw Failure(description: "Atom entry without a labelled SHA-256 digest was accepted")
        } catch is UpdateService.Failure {
            // Expected.
        }

        do {
            _ = try UpdateService.decodeRelease(
                Data(fixture.replacingOccurrences(
                    of: "\"tag_name\": \"v1.3.3\"",
                    with: "\"tag_name\": \"v1.3.3-beta.1\""
                ).replacingOccurrences(
                    of: "\"prerelease\": false",
                    with: "\"prerelease\": true"
                ).replacingOccurrences(
                    of: "Pesty-1.3.3.dmg",
                    with: "Pesty-1.3.3-beta.1.dmg"
                ).utf8),
                requiredChannel: .stable
            )
            throw Failure(description: "stable channel accepted a beta release")
        } catch is UpdateService.Failure {
            // Expected.
        }

        guard UpdatePresentation.showInMenuBar(hasUpdate: true, showsMenuBarIcon: true),
              !UpdatePresentation.showInClipboardBar(hasUpdate: true, showsMenuBarIcon: true),
              !UpdatePresentation.showInMenuBar(hasUpdate: true, showsMenuBarIcon: false),
              UpdatePresentation.showInClipboardBar(hasUpdate: true, showsMenuBarIcon: false),
              !UpdatePresentation.showInMenuBar(hasUpdate: false, showsMenuBarIcon: true),
              !UpdatePresentation.showInClipboardBar(hasUpdate: false, showsMenuBarIcon: false) else {
            throw Failure(description: "update indicator placement is not mutually exclusive")
        }

        let missingDigest = fixture.replacingOccurrences(
            of: "\"digest\": \"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"",
            with: "\"digest\": null"
        )
        do {
            _ = try UpdateService.decodeRelease(
                Data(missingDigest.utf8),
                requiredChannel: .stable
            )
            throw Failure(description: "release without SHA-256 digest was accepted")
        } catch is UpdateService.Failure {
            // Expected.
        }
    }
}
