#!/usr/bin/env ruby
# frozen_string_literal: true

# Migration script: sandpersona → pocketrb
# Converts facts.json + identity files → MEMORY.md + daily notes

require "json"
require "date"
require "fileutils"

SANDPERSONA_KNOWLEDGE = File.expand_path("~/.sandpersona/agent/knowledge")
POCKETRB_WORKSPACE = ARGV[0] || File.expand_path("~/.pocketrb")

def main
  puts "=== Sandpersona → Pocketrb Migration ==="
  puts "Source: #{SANDPERSONA_KNOWLEDGE}"
  puts "Target: #{POCKETRB_WORKSPACE}"
  puts

  # Create workspace
  FileUtils.mkdir_p(POCKETRB_WORKSPACE)
  FileUtils.mkdir_p(File.join(POCKETRB_WORKSPACE, "memory"))
  FileUtils.mkdir_p(File.join(POCKETRB_WORKSPACE, "skills"))

  # Load source data
  facts = load_facts
  recent = load_recent
  identity = load_identity

  # Generate MEMORY.md
  memory_content = generate_memory_md(facts, identity)
  memory_path = File.join(POCKETRB_WORKSPACE, "MEMORY.md")
  File.write(memory_path, memory_content)
  puts "✓ Created #{memory_path} (#{memory_content.length} bytes)"

  # Generate daily notes from recent events
  daily_notes = generate_daily_notes(recent)
  daily_notes.each do |date, content|
    note_path = File.join(POCKETRB_WORKSPACE, "memory", "#{date}.md")
    File.write(note_path, content)
    puts "✓ Created #{note_path}"
  end

  # Generate identity prompt file
  identity_content = generate_identity_prompt(identity)
  identity_path = File.join(POCKETRB_WORKSPACE, "IDENTITY.md")
  File.write(identity_path, identity_content)
  puts "✓ Created #{identity_path} (#{identity_content.length} bytes)"

  # Summary
  puts
  puts "=== Migration Complete ==="
  puts "Files created:"
  puts "  - MEMORY.md (learned facts, installed software, user info)"
  puts "  - IDENTITY.md (personality, values, instructions)"
  puts "  - memory/*.md (#{daily_notes.size} daily notes)"
  puts
  puts "To use with pocketrb:"
  puts "  pocketrb chat --workspace #{POCKETRB_WORKSPACE}"
end

def load_facts
  path = File.join(SANDPERSONA_KNOWLEDGE, "life/areas/infrastructure/memory_legacy/facts.json")
  return {} unless File.exist?(path)

  JSON.parse(File.read(path))
rescue JSON::ParserError => e
  puts "Warning: Could not parse facts.json: #{e.message}"
  {}
end

def load_recent
  path = File.join(SANDPERSONA_KNOWLEDGE, "life/areas/infrastructure/memory_legacy/recent.json")
  return [] unless File.exist?(path)

  JSON.parse(File.read(path))
rescue JSON::ParserError => e
  puts "Warning: Could not parse recent.json: #{e.message}"
  []
end

def load_identity
  identity_dir = File.join(SANDPERSONA_KNOWLEDGE, "life/areas/identity")
  return {} unless Dir.exist?(identity_dir)

  files = {}
  Dir.glob(File.join(identity_dir, "*")).each do |path|
    next if File.directory?(path)

    name = File.basename(path, ".*")
    files[name] = File.read(path)
  end
  files
end

def generate_memory_md(facts, identity)
  sections = []

  sections << "# Pocketrb Memory"
  sections << ""
  sections << "_Migrated from sandpersona on #{Date.today}_"
  sections << ""

  # User info
  if facts["user"]&.any?
    sections << "## User Information"
    sections << ""
    facts["user"].each do |key, data|
      value = data.is_a?(Hash) ? data["value"] : data
      sections << "- **#{key}**: #{value}"
    end
    sections << ""
  end

  # Self info
  if facts["self"]&.any?
    sections << "## Agent Identity"
    sections << ""
    facts["self"].each do |key, data|
      value = data.is_a?(Hash) ? data["value"] : data
      sections << "- **#{key}**: #{value}"
    end
    sections << ""
  end

  # Installed software (selective - skip sensitive data)
  if facts["installed"]&.any?
    sections << "## Environment"
    sections << ""
    safe_installed = facts["installed"].reject do |name, _|
      name.to_s.match?(/smtp|password|credential|token|secret|login/i)
    end
    safe_installed.each do |name, data|
      details = data.is_a?(Hash) ? data["details"] : data
      # Truncate long details
      details = details.to_s[0..200] + "..." if details.to_s.length > 200
      sections << "- **#{name}**: #{details}"
    end
    sections << ""
  end

  # Learned facts (top 20)
  if facts["learned"]&.any?
    sections << "## Learned Knowledge"
    sections << ""
    facts["learned"].first(20).each do |topic, entries|
      latest = entries.is_a?(Array) ? entries.last : entries
      info = latest.is_a?(Hash) ? latest["info"] : latest
      # Truncate long entries
      info = info.to_s[0..300] + "..." if info.to_s.length > 300
      sections << "### #{topic}"
      sections << ""
      sections << info.to_s
      sections << ""
    end
  end

  sections.join("\n")
end

def generate_daily_notes(recent)
  notes = Hash.new { |h, k| h[k] = [] }

  recent.each do |event|
    timestamp = event["timestamp"]
    next unless timestamp

    date = Date.parse(timestamp).to_s rescue nil
    next unless date

    description = event["description"] || event["type"]
    notes[date] << "- #{description}"
  end

  # Format each day
  notes.transform_values do |entries|
    "# Daily Notes\n\n#{entries.join("\n")}\n"
  end
end

def generate_identity_prompt(identity)
  sections = []

  sections << "# Agent Identity"
  sections << ""
  sections << "_This file defines the agent's personality and behavior._"
  sections << ""

  # Core identity first
  if identity["core"]
    sections << "## Core"
    sections << ""
    sections << identity["core"]
    sections << ""
  end

  # Personality
  if identity["personality"]
    sections << "## Personality"
    sections << ""
    # Extract just the key parts
    personality = identity["personality"]
    # Skip very long sections
    if personality.length < 5000
      sections << personality
    else
      sections << personality[0..4000] + "\n\n_[Truncated]_"
    end
    sections << ""
  end

  # Values
  if identity["values"]
    sections << "## Values"
    sections << ""
    values = identity["values"]
    if values.length < 3000
      sections << values
    else
      sections << values[0..2500] + "\n\n_[Truncated]_"
    end
    sections << ""
  end

  # Instructions
  if identity["instructions"]
    sections << "## Operating Instructions"
    sections << ""
    sections << identity["instructions"]
    sections << ""
  end

  sections.join("\n")
end

main
