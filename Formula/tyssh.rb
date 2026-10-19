# Updated by .github/workflows/publish.yml on each release.
class Tyssh < Formula
  desc "Cluster SSH for macOS Terminal.app"
  homepage "https://github.com/tomkins/TyphonSSH"
  url "https://github.com/tomkins/TyphonSSH/releases/download/0.4/tyssh-0.4-macos-universal.tar.gz"
  sha256 "d7a1aa01d7f3bbf0606a23e797d9eb9b6b7865a2047969e6dc4e982d525ba389"
  license "BSD-3-Clause"

  depends_on macos: :sequoia

  def install
    bin.install "tyssh"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tyssh --version")
  end
end
