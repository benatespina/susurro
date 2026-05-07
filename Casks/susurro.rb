cask "susurro" do
  version "0.2.1"
  sha256 "5c6f221b539b148d9219dfd576c96a66fceace855cb57815c4ef48004b694b6c"

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
