#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"

repository = File.expand_path("..", __dir__)
manifest = File.join(repository, "Vendor/AnyDocBridgeRust/Cargo.toml")
output = File.join(repository, "Familiar/Resources/AnyDocRustDependencies.txt")

metadata_json, status = Open3.capture2(
  "cargo", "metadata", "--format-version", "1", "--locked", "--manifest-path", manifest
)
abort "cargo metadata failed" unless status.success?

packages = JSON.parse(metadata_json).fetch("packages").sort_by { |package| [package.fetch("name"), package.fetch("version")] }
license_texts = {}
inventory = packages.map do |package|
  root = File.dirname(package.fetch("manifest_path"))
  files = Dir.glob(File.join(root, "{LICENSE*,COPYING*,NOTICE*,COPYRIGHT*}"))
    .select { |path| File.file?(path) && File.size(path) <= 1_000_000 }
    .sort

  references = files.each_with_object([]) do |path, values|
    text = File.read(path, encoding: "UTF-8", invalid: :replace, undef: :replace, replace: "�").strip
    next if text.empty?

    digest = Digest::SHA256.hexdigest(text)
    license_texts[digest] ||= { text: text, packages: [], filenames: [] }
    license_texts[digest][:packages] << "#{package.fetch("name")} #{package.fetch("version")}"
    license_texts[digest][:filenames] << File.basename(path)
    values << digest[0, 12]
  end

  {
    name: package.fetch("name"),
    version: package.fetch("version"),
    license: package["license"] || "NO SPDX EXPRESSION",
    repository: package["repository"] || package["homepage"] || package["source"] || "local source",
    references: references.uniq
  }
end

body = +"Familiar AnyDoc Rust Dependency Notices\n"
body << "Generated from Vendor/AnyDocBridgeRust/Cargo.lock. Do not edit by hand.\n\n"
body << "DEPENDENCY INVENTORY\n\n"
inventory.each do |entry|
  body << "#{entry[:name]} #{entry[:version]}\n"
  body << "License: #{entry[:license]}\n"
  body << "Source: #{entry[:repository]}\n"
  body << "License text IDs: #{entry[:references].empty? ? "none found in package" : entry[:references].join(", ")}\n\n"
end

body << "LICENSE AND NOTICE TEXTS\n\n"
license_texts.sort.each do |digest, entry|
  body << "===== #{digest[0, 12]} =====\n"
  body << "Packages: #{entry[:packages].uniq.sort.join(", ")}\n"
  body << "Files: #{entry[:filenames].uniq.sort.join(", ")}\n\n"
  body << entry[:text]
  body << "\n\n"
end

FileUtils.mkdir_p(File.dirname(output))
File.write(output, body)
puts output
