#!/usr/bin/env ruby
# frozen_string_literal: true

abort "Usage: #{$PROGRAM_NAME} <cask-path> <version> <sha256> <url>" unless ARGV.length == 4

cask_path, version, sha256, url = ARGV

unless sha256.match?(/\A[0-9a-f]{64}\z/)
  abort "sha256 must be exactly 64 lowercase hexadecimal characters"
end

contents = File.read(cask_path)

replacements = {
  /^(\s*version\s+).+$/ => "\\1\"#{version}\"",
  /^(\s*sha256\s+)[\s\S]*?(?=^\s*(?:url|name|desc|homepage|depends_on|app|uninstall|zap)\b)/ => "\\1\"#{sha256}\"\n",
  /^(\s*url\s+).+$/ => "\\1\"#{url}\""
}

replacements.each do |pattern, replacement|
  next if contents.sub!(pattern, replacement)

  abort "Could not update #{pattern.inspect} in #{cask_path}"
end

File.write(cask_path, contents)
