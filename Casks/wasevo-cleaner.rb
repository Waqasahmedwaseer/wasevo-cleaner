cask "wasevo-cleaner" do
  version "0.6.0"
  sha256 "90cc1d2987b3f8df0055a1cbc1f7f03c24a720e329c559272fbc947c1b932180"

  url "https://github.com/Waqasahmedwaseer/wasevo-cleaner/releases/download/v#{version}/Wasevo-Cleaner-#{version}.dmg"
  name "Wasevo Cleaner"
  desc "Free, open-source disk cleaner that never deletes what matters"
  homepage "https://github.com/Waqasahmedwaseer/wasevo-cleaner"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "Wasevo Cleaner.app"

  zap trash: [
    "~/Library/Logs/WasevoCleaner.log",
    "~/Library/Preferences/com.wasevo.cleaner.plist",
  ]
end
