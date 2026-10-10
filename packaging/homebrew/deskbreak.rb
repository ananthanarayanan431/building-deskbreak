# Copy this file to the `homebrew-tap` repository as Formula/deskbreak.rb.
#
# Release steps:
#   1. Bump VERSION in the app repo, commit, and tag it (git tag v1.0.0 && git push --tags).
#   2. curl -L <url below> | shasum -a 256   and paste the result into sha256.
#   3. Commit the formula to homebrew-tap.
class Deskbreak < Formula
  desc "Menu bar reminders to drink water and walk, counted in active Mac time"
  homepage "https://github.com/ananthanarayanan431/deskbreak"
  license "MIT"
  url "https://github.com/ananthanarayanan431/deskbreak/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_OF_THE_TAGGED_TARBALL"
  version "1.0.0"

  depends_on macos: :ventura

  def install
    # SwiftPM uses its own sandbox, which cannot nest inside Homebrew's build sandbox.
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    system "scripts/build-app.sh", "--output", buildpath/"dist"
    prefix.install buildpath/"dist/DeskBreak.app"
  end

  def caveats
    <<~EOS
      Start DeskBreak:
        open "#{opt_prefix}/DeskBreak.app"

      Then turn on "Launch at login" in DeskBreak's Settings.
      After `brew upgrade deskbreak`, toggle it off and on again so it points at the new version.

      To remove everything after `brew uninstall deskbreak`:
        rm -rf ~/Library/Application\\ Support/DeskBreak
        defaults delete io.github.ananthanarayanan431.deskbreak
    EOS
  end

  test do
    app = prefix/"DeskBreak.app"
    assert_path_exists app/"Contents/Info.plist"
    assert_predicate app/"Contents/MacOS/DeskBreak", :executable?
    system "codesign", "--verify", "--strict", app
  end
end
