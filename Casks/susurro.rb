cask "susurro" do
  version "0.5.1"
  sha256 "2844a9266d25bec59d28be7328b165d791108887314079676ea656bc5747415d"

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
