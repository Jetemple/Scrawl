#!/usr/bin/env ruby
# frozen_string_literal: true

abort "Usage: #{$PROGRAM_NAME} <cask-path> <version> <sha256> <url>" unless ARGV.length == 4

cask_path, version, sha256, url = ARGV

contents = File.read(cask_path)

replacements = {
  /^(\s*version\s+).+$/ => "\\1\"#{version}\"",
  /^(\s*sha256\s+).+$/ => "\\1\"#{sha256}\"",
  /^(\s*url\s+).+$/ => "\\1\"#{url}\""
}

replacements.each do |pattern, replacement|
  next if contents.sub!(pattern, replacement)

  abort "Could not update #{pattern.inspect} in #{cask_path}"
end

File.write(cask_path, contents)
