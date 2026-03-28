class Thorapp < Formula
  desc "Native macOS control center for NVIDIA Jetson devices"
  homepage "https://github.com/RobotFlow-Labs/thorapp"
  url "https://github.com/RobotFlow-Labs/thorapp.git",
      tag:      "v0.1.0",
      revision: "HEAD"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma

  def install
    system "swift", "build",
           "-c", "release",
           "--disable-sandbox",
           "--arch", "arm64"

    # Install CLI
    bin.install ".build/release/thorctl"

    # Install agent
    (libexec/"agent").install Dir["Agent/*"]

    # Build and install .app bundle
    system "bash", "Scripts/package_app.sh", "release"
    prefix.install "THORApp.app"
  end

  def post_install
    # Symlink the app to /Applications for easy access
    app_link = Pathname("/Applications/THOR.app")
    app_link.unlink if app_link.symlink?
    app_link.make_symlink(prefix/"THORApp.app")
  end

  def caveats
    <<~EOS
      THOR has been installed!

      CLI tool:
        thorctl help

      GUI app:
        open /Applications/THOR.app
        # or: open #{prefix}/THORApp.app

      Jetson agent:
        The agent files are at: #{libexec}/agent/
        Copy them to your Jetson: scp -r #{libexec}/agent/ jetson@YOUR_IP:/opt/thor-agent/

      Docker simulators (for testing without hardware):
        cd #{prefix} && docker compose up -d

      Quick start:
        1. thorctl connect YOUR_JETSON_IP
        2. thorctl health
        3. thorctl power
        4. thorctl ros2-topics
    EOS
  end

  test do
    assert_match "thorctl", shell_output("#{bin}/thorctl version")
  end
end
