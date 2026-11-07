#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "rbconfig"
require_relative "prepare_stage2"

def option_values(argv, name)
  values = []
  index = 0
  while index < argv.length
    arg = argv[index]
    if arg == name
      raise "#{name} value missing" if argv[index + 1].to_s.empty? || argv[index + 1].start_with?("--")
      values << argv[index + 1]
      index += 2
    elsif arg.start_with?("#{name}=")
      values << arg.split("=", 2).last
      index += 1
    else
      index += 1
    end
  end
  values
end

begin
  prepared_args = option_values(ARGV, "--prepared")
  raise "--prepared must appear exactly once" unless prepared_args.length == 1
  prepared_value = prepared_args.first
  prepared_indices = []
  ARGV.each_with_index { |arg, index| prepared_indices << index if arg == "--prepared" || arg.start_with?("--prepared=") }
  prepared_arg = prepared_indices.first
  if prepared_arg
    ARGV.slice!(prepared_arg, ARGV[prepared_arg].include?("=") ? 1 : 2)
  end
  raise "--prepared required" if prepared_value.to_s.empty?
  prepared = File.realpath(prepared_value)
  manifest = JSON.parse(File.read(File.join(prepared, "stage2-manifest.json")))
  raise "prepared manifest is not stage 2" unless manifest["stage"] == 2
  {"--task" => "task", "--agent" => "agent", "--model" => "model", "--condition" => "condition", "--track" => "track"}.each do |flag, key|
    values = option_values(ARGV, flag)
    raise "#{flag} must appear exactly once" unless values.length == 1
    raise "#{flag} differs from prepared assignment" unless values.first == manifest.fetch(key).to_s
  end
  raise "--catalog is fixed by the prepared catalog" unless option_values(ARGV, "--catalog").empty?
  output_values = option_values(ARGV, "--output")
  raise "--output must appear exactly once" unless output_values.length == 1
  output = File.expand_path(output_values.first)
  raise "output already exists" if File.exist?(output)
  timeout_values = option_values(ARGV, "--timeout")
  if timeout_values.any?
    raise "--timeout must appear exactly once" unless timeout_values.length == 1
    raise "stage-2 timeout must be 900 seconds" unless Float(timeout_values.first) == 900
  else
    ARGV.concat(["--timeout", "900"])
  end
  command = [RbConfig.ruby, File.join(__dir__, "support", "run_trial.rb"), "--catalog", prepared, *ARGV]
  success = system(*command)
  if File.file?(File.join(output, "meta.json"))
    meta_path = File.join(output, "meta.json")
    meta = JSON.parse(File.read(meta_path))
    meta.merge!(manifest.slice("stage", "stage_kind", "stage_timeout_seconds", "repeat", "stage1_source_trial", "stage1_outcome", "stage1_status", "stage1_disposition_category", "stage1_final", "stage1_final_bundle_sha256", "followup_prompt_sha256", "initial_contract_sha256", "stage2_prompt_sha256", "prompt_context"))
    meta["stage2_prepared_catalog"] = prepared
    File.write(meta_path, JSON.pretty_generate(meta) + "\n")
    puts JSON.pretty_generate(meta)
  end
  exit(success ? 0 : 1)
rescue StandardError => error
  warn "#{error.class}: #{error.message}"
  exit 2
end
