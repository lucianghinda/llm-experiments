#!/usr/bin/env ruby
# frozen_string_literal: true

# Host-side orchestrator. Runs the whole grid, one container at a time, and is
# resumable: a cell whose output.json already parsed cleanly is never re-run.
#
#   ruby output-styles/scripts/run_grid.rb --runs 1,2
#   ruby output-styles/scripts/run_grid.rb --only 02-single-method-domain/03-explanatory --runs 1
#
# Disk frugality is the point of this shape. No app images are built: the apps
# arrive as git bundles (10 MB, not 5 GB), the newer Claude CLI is a host
# directory mounted read-only (installed once, inside a container, so the
# binaries are linux-arm64), and every trial container carries --rm so its
# writable layer dies with it. The only persistent growth is the results.

require "base64"
require "fileutils"
require "json"
require "open3"
require "shellwords"

ROOT       = File.expand_path("../..", __dir__)
EXP        = File.join(ROOT, "output-styles")
SCRATCH    = ENV.fetch("LLMX_SCRATCH") { abort "LLMX_SCRATCH required (bundles + staging dir)" }
BUNDLES    = File.join(SCRATCH, "bundles")
TOOLS      = File.expand_path("~/.llmx/tools/claude-latest")
AUTH       = File.expand_path("~/.llmx/auth")
MODEL      = ENV.fetch("LLMX_MODEL", "opus")
MEMORY     = ENV.fetch("LLMX_MEMORY", "4g")
CPUS       = ENV.fetch("LLMX_CPUS", "4")

TARGETS = {
  "01-rails-concern" => {
    bundle: "pcs.bundle",
    base: "Read the file app/controllers/concerns/idempotency.rb in this Rails app and explain to me%{slot} how it works.%{trail}"
  },
  "02-single-method-domain" => {
    bundle: "srb.bundle",
    base: "Read the method `build_blocks` in app/services/edition/draft_query.rb in this Rails app and explain to me%{slot} how it works.%{trail}"
  },
  "03-single-method-algorithm" => {
    bundle: "srb.bundle",
    base: "Read the method `count_transpositions` in app/services/authors/match_by_name.rb in this Rails app and explain to me%{slot} how it works.%{trail}"
  },
  "04-query-object" => {
    bundle: "srb.bundle",
    base: "Read the file app/services/edition/draft_query.rb in this Rails app and explain to me%{slot} how it works.%{trail}"
  }
}.freeze

VARIANTS = [
  { slug: "01-default" },
  { slug: "02-concise",         style: "Concise" },
  { slug: "03-explanatory",     style: "Explanatory" },
  { slug: "04-learning",        style: "Learning" },
  { slug: "05-proactive",       style: "Proactive" },
  { slug: "06-style-ste",       style: "Simple Technical English",   file: "simple-technical-english.md" },
  { slug: "07-style-asd",       style: "ASD-STE100",                 file: "asd-ste100.md" },
  { slug: "08-style-asd-hatch", style: "ASD-STE100 escape hatch",    file: "asd-ste100-escape-hatch.md" },
  { slug: "09-style-asd-bare",  style: "ASD-STE100 bare",            file: "asd-ste100-bare.md" },
  { slug: "10-prompt-ste",      slot: " in Simple Technical English" },
  { slug: "11-prompt-asd",      slot: " in ASD-STE100 Simplified Technical English" },
  { slug: "12-prompt-asd-hatch", trail: " Use ASD-STE100 Simplified Technical English (STE) when it doesn't detract from meaning." }
].freeze

runs = [1]
only = nil
args = ARGV.dup
until args.empty?
  case (arg = args.shift)
  when "--runs" then runs = args.shift.split(",").map(&:to_i)
  when "--only" then only = args.shift
  else abort "unknown option: #{arg}"
  end
end

def log(msg)
  puts "[grid #{Time.now.strftime('%H:%M:%S')}] #{msg}"
  $stdout.flush
end

def cell_done?(dir, slug)
  json = File.join(dir, "#{slug}.json")
  return false unless File.exist?(json)

  parsed = JSON.parse(File.read(json))
  parsed["type"] == "result" && parsed["subtype"] == "success" && !parsed["is_error"]
rescue JSON::ParserError
  false
end

failures = 0

runs.each do |run|
  TARGETS.each do |target, tcfg|
    VARIANTS.each do |variant|
      cell = "#{target}/#{variant[:slug]}"
      next if only && cell != only

      out_dir = File.join(EXP, "runs", "run-#{run}", target)
      FileUtils.mkdir_p(out_dir)
      if cell_done?(out_dir, variant[:slug])
        log "skip run-#{run} #{cell} (done)"
        next
      end

      prompt = format(tcfg[:base], slot: variant[:slot].to_s, trail: variant[:trail].to_s)
      staging = File.join(SCRATCH, "results", "run-#{run}--#{target}--#{variant[:slug]}")
      FileUtils.rm_rf(staging)
      FileUtils.mkdir_p(staging)

      cmd = [
        "container", "run", "--rm",
        "--memory", MEMORY, "--cpus", CPUS,
        "--mount", "type=bind,source=#{BUNDLES},target=/bundles,readonly",
        "--mount", "type=bind,source=#{TOOLS},target=/tools/claude,readonly",
        "--mount", "type=bind,source=#{File.join(EXP, 'styles')},target=/styles,readonly",
        "--mount", "type=bind,source=#{File.join(EXP, 'scripts')},target=/scripts,readonly",
        "--volume", "#{AUTH}:/home/agent/.agent-auth",
        "--volume", "#{staging}:/results",
        "--env", "LLMX_BUNDLE=#{tcfg[:bundle]}",
        "--env", "LLMX_PROMPT_B64=#{Base64.strict_encode64(prompt)}",
        "--env", "LLMX_MODEL=#{MODEL}",
        "--env", "LLMX_STYLE_NAME=#{variant[:style]}",
        "--env", "LLMX_STYLE_FILE=#{variant[:file]}",
        "llmx-base", "bash", "-lc", "exec ruby /scripts/trial.rb"
      ]

      log "run-#{run} #{cell} starting"
      _out, err, status = Open3.capture3(*cmd)

      output_json = File.join(staging, "output.json")
      ok = status.success? && File.exist?(output_json)
      parsed = ok ? (JSON.parse(File.read(output_json)) rescue nil) : nil

      if parsed && parsed["type"] == "result" && !parsed["is_error"]
        File.write(File.join(out_dir, "#{variant[:slug]}.md"), parsed["result"].to_s + "\n")
        FileUtils.cp(output_json, File.join(out_dir, "#{variant[:slug]}.json"))
        FileUtils.cp(File.join(staging, "meta.json"), File.join(out_dir, "#{variant[:slug]}.meta.json"))
        model_used = (parsed["modelUsage"] || {}).keys.join(",")
        log "run-#{run} #{cell} ok (#{parsed['duration_ms'].to_i / 1000}s, #{model_used})"
        FileUtils.rm_rf(staging)
      else
        failures += 1
        tail = File.exist?(File.join(staging, "stderr.txt")) ? File.read(File.join(staging, "stderr.txt"))[-500..] : err[-500..]
        log "run-#{run} #{cell} FAILED (exit #{status.exitstatus}); staging kept at #{staging}\n#{tail}"
        abort "aborting: 3 consecutive-ish failures, check auth/harness" if failures >= 3
      end
    end
  end
end

log "grid complete (#{failures} failures)"
