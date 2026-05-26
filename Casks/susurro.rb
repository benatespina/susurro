cask "susurro" do
  version "0.6.1"
  sha256 "348811a5d422e9965a30493193210286aed881a84d259026b847619fbb48da6c"

  url "https://github.com/benatespina/susurro/releases/download/v#{version}/Susurro-#{version}.dmg"
  name "Susurro"
  desc "Read-aloud helper for macOS"
  homepage "https://github.com/benatespina/susurro"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  app "Susurro.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Susurro.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Preferences/com.benatespina.susurro.plist",
    "~/Library/Caches/com.benatespina.susurro",
    "~/Library/Application Support/Susurro",
  ]
end
