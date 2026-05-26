cask "susurro" do
  version "0.6.0"
  sha256 "cadabf93d76781acebb8041618147fe55206a2156c4222ef3b959e4b67813546"

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
