#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"

input_path = ARGV.fetch(0)
output_path = ARGV.fetch(1)

violations = File.exist?(input_path) ? JSON.parse(File.read(input_path)) : []

severity_map = {
  "error" => "major",
  "warning" => "minor"
}

report = violations.map do |violation|
  file = violation.fetch("file", "")
  line = violation.fetch("line", 1) || 1
  rule = violation.fetch("rule_id", "swiftlint")
  reason = violation.fetch("reason", "SwiftLint violation")
  severity = severity_map.fetch(violation["severity"], "minor")
  fingerprint_source = [file, line, rule, reason].join(":")

  {
    type: "issue",
    check_name: rule,
    description: reason,
    categories: ["Style"],
    fingerprint: Digest::MD5.hexdigest(fingerprint_source),
    severity: severity,
    location: {
      path: file,
      lines: {
        begin: line
      }
    }
  }
end

File.write(output_path, JSON.pretty_generate(report))

