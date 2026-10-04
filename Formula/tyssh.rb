# Updated by .github/workflows/publish.yml on each release.
class Tyssh < Formula
  desc "Cluster SSH for macOS Terminal.app"
  homepage "https://github.com/tomkins/TyphonSSH"
  url "https://github.com/tomkins/TyphonSSH/releases/download/0.3/tyssh-0.3-macos-universal.tar.gz"
  sha256 "c011d41ae93e87601ce1876bb7ce4a677b399f37e8427177805430480f640187"
  license "BSD-3-Clause"

  depends_on macos: :sequoia

  def install
    bin.install "tyssh"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tyssh --version")
  end
end
