class Thorapp < Formula
  desc "Native macOS control center for NVIDIA Jetson devices"
  homepage "https://github.com/RobotFlow-Labs/thorapp"
  url "https://github.com/RobotFlow-Labs/thorapp.git",
      tag: "v0.1.0"
  version "0.1.0"
  license "MIT"
  head "https://github.com/RobotFlow-Labs/thorapp.git", branch: "main"

  depends_on xcode: ["16.3", :build]
  depends_on macos: :sonoma

  def install
    system "swift", "build",
           "-c", "release",
           "--disable-sandbox",
           "--arch", "arm64"

    package_script = if (buildpath/"Scripts/package_app.sh").exist?
      "Scripts/package_app.sh"
    elsif (buildpath/"Scripts/release/package_app.sh").exist?
      "Scripts/release/package_app.sh"
    else
      odie "Missing package script"
    end

    # Install CLI
    bin.install ".build/release/thorctl"

    # Install agent
    (libexec/"agent").install Dir["Agent/*"]

    # Build and install .app bundle
    system(
      {
        "SWIFT_BUILD_DISABLE_SANDBOX" => "1",
        "SKIP_SWIFT_BUILD" => "1",
      },
      "bash",
      package_script,
      "release"
    )
    prefix.install "THORApp.app"

    (bin/"thorapp").write <<~EOS
      #!/bin/bash
      exec open -a "#{prefix}/THORApp.app" "$@"
    EOS
    chmod 0555, bin/"thorapp"
  end

  def caveats
    <<~EOS
      THOR has been installed!

      CLI tool:
        thorctl help

      GUI app:
        thorapp
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
    assert_predicate prefix/"THORApp.app/Contents/Info.plist", :exist?
    assert_predicate prefix/"THORApp.app/Contents/MacOS/THORApp", :exist?
    assert_predicate bin/"thorapp", :exist?
    assert_match "open -a \"#{prefix}/THORApp.app\"", (bin/"thorapp").read
  end
end
