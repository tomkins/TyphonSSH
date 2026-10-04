# Updated by .github/workflows/publish.yml on each release.
class Tyssh < Formula
  desc "Cluster SSH for macOS Terminal.app"
  homepage "https://github.com/tomkins/TyphonSSH"
  url "https://github.com/tomkins/TyphonSSH/releases/download/0.2/tyssh-0.2-macos-universal.tar.gz"
  sha256 "f01cf050cba6984ccea7119ef32fe80b5473ee850e5e409b7c355ee908f8d0c7"
  license "BSD-3-Clause"

  depends_on macos: :sequoia

  def install
    bin.install "tyssh"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tyssh --version")
  end
end
