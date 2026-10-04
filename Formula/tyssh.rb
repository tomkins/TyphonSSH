# Updated by .github/workflows/publish.yml on each release.
class Tyssh < Formula
  desc "Cluster SSH for macOS Terminal.app"
  homepage "https://github.com/tomkins/TyphonSSH"
  url "https://github.com/tomkins/TyphonSSH/releases/download/0.1/tyssh-0.1-macos-universal.tar.gz"
  sha256 "702d13d6f56d3578a440e9dbcceb949447c6f6faf797d89c4c279fdbd6fee639"
  license "BSD-3-Clause"

  depends_on macos: :sequoia

  def install
    bin.install "tyssh"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/tyssh --version")
  end
end
