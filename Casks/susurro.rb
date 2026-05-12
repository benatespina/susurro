cask "susurro" do
  version "0.3.0"
  sha256 "1ece3695a9ca9cf99600aebb16566c3dac4d9efa3ef4dc5fa97fcc0e3413db2b"

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
