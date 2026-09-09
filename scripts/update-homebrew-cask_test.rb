#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

SCRIPT_PATH = File.expand_path("update-homebrew-cask.rb", __dir__)

class UpdateHomebrewCaskTest < Minitest::Test
  CASK_TEMPLATE = <<~RUBY
    cask "scrawl" do
      version "0.0.15"
      sha256 "#{"0" * 64}"
      url "https://example.com/old.zip"
      app "Scrawl.app"
    end
  RUBY

  def run_updater(
    sha256: "#{"a" * 64}",
    version: "0.0.16",
    url: "https://example.com/new.zip",
    cask_contents: CASK_TEMPLATE
  )
    Dir.mktmpdir do |directory|
      cask_path = File.join(directory, "scrawl.rb")
      File.write(cask_path, cask_contents)

      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT_PATH,
        cask_path,
        version,
        sha256,
        url
      )

      yield cask_path, stdout, stderr, status
    end
  end

  def test_updates_a_cask_with_a_single_sha256_digest
    run_updater do |cask_path, _stdout, stderr, status|
      assert status.success?, stderr

      contents = File.read(cask_path)
      assert_includes contents, %(version "0.0.16")
      assert_includes contents, %(sha256 "#{"a" * 64}")
      assert_includes contents, %(url "https://example.com/new.zip")
    end
  end

  def test_repairs_a_multiline_sha256_assignment
    malformed_cask = <<~RUBY
      cask "scrawl" do
        version "0.0.15"
        sha256 "#{"b" * 64}"
        #{"c" * 64}"
        #{"d" * 64}"
        #{"e" * 64}"

        url "https://example.com/old.zip"
        app "Scrawl.app"
      end
    RUBY

    run_updater(cask_contents: malformed_cask) do |cask_path, _stdout, stderr, status|
      assert status.success?, stderr

      contents = File.read(cask_path)
      assert_equal 1, contents.scan(/^\s*sha256 "[0-9a-f]{64}"$/).length
      refute_includes contents, "#{"b" * 64}"
      refute_includes contents, "#{"c" * 64}"
      refute_includes contents, "#{"d" * 64}"
      refute_includes contents, "#{"e" * 64}"
    end
  end

  def test_rejects_a_multiline_sha256_digest
    multiline_sha256 = "#{"a" * 64}\n#{"b" * 64}"

    run_updater(sha256: multiline_sha256) do |_cask_path, _stdout, stderr, status|
      refute status.success?, "expected multiline SHA256 to be rejected"
      assert_includes stderr, "sha256 must be exactly 64 lowercase hexadecimal characters"
    end
  end
end
