#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tmpdir"
require_relative "harness"

module ReviewPackets
  module_function

  CODE_EXTENSIONS = %w[.rb .erb .rake].freeze
  LABEL_PATTERN = /ruby[-_ ]plainspoken|rubypowers|claude|codex|openai|anthropic/i

  def build(results_root, output_dir, seed:, final_trials: nil, contracts: nil, include_stable_failures: false)
    root = File.realpath(results_root)
    output = File.expand_path(output_dir)
    raise "output directory already exists: #{output}" if File.exist?(output)
    if include_stable_failures && !final_trials
      raise "--include-stable-failures requires an explicit --final-trials list"
    end

    records = load_records(root)
    contracts_by_task = contracts ? read_contracts(contracts) : {}
    FileUtils.mkdir_p(File.dirname(output))
    selected = final_trials ? supplied_finals(root, final_trials, records, include_stable_failures: include_stable_failures) : resolve_finals(root, records)
    packets = selected.filter_map do |record|
      if record[:validation]
        {trial: record, validation: record[:validation]}
      else
        packet_data(root, record, contracts_by_task)
      end
    end
    packets.each do |packet|
      reason = packet[:validation] || if packet[:files].to_a.empty?
        'manual review: no production diff; inspect worktree archives'
      elsif [packet[:trial][:meta], packet[:root_meta]].any? { |meta| meta['worktrees'].is_a?(Array) && meta['worktrees'].length > 1 }
        'manual review: multiple worktrees'
      elsif ([packet[:patch], packet[:contract]] + packet[:files].flat_map { |file| [file[:path], file[:baseline], file[:final]] }).compact.any? { |text| LABEL_PATTERN.match?(text) }
        'manual review: possible identifying label'
      end
      packet[:trial][:validation] = reason if reason
    end
    packet_by_path = packets.to_h { |packet| [packet[:trial][:path], packet] }
    selected.each do |record|
      packet = packet_by_path[record[:path]]
      next unless packet && packet[:trial][:validation]
      record[:review_selection] = "excluded from packets: #{packet[:trial][:validation]}"
    end
    packets.select! { |packet| packet[:trial][:validation].nil? }
    shuffled = packets.shuffle(random: Random.new(seed))

    Dir.mkdir(output, 0o700)
    begin
      packet_dir = File.join(output, "packets")
      Dir.mkdir(packet_dir)
      key = {}
      shuffled.each_with_index do |packet, index|
        id = format("R-%04d", index + 1)
        File.write(File.join(packet_dir, "#{id}.md"), render_packet(id, packet, hide_outcomes: include_stable_failures))
        key[id] = {
          final_trial: relative(root, packet[:trial][:path]),
          grid_cell: relative(root, packet[:root_path]),
          task: packet[:root_meta]["task"],
          agent: packet[:root_meta]["agent"],
          model: packet[:root_meta]["model"],
          condition: packet[:root_meta]["condition"],
          track: packet[:root_meta]["track"]
        }
      end
      write_private_key(output, key, seed)
      outcomes_path = File.join(output, "outcomes.md")
      File.write(outcomes_path, render_outcomes(root, records, selected: selected))
      File.chmod(0o600, outcomes_path)
      instructions = File.join(output, 'PRIVATE-README.txt')
      stable_note = include_stable_failures ? " This secondary review may include owner-selected stable failed outcomes; packet text does not report outcome status." : ""
      File.write(instructions, "Share only the packets/ directory and the separate review rubric. Keep private-key.json, outcomes.md, and this directory's other files private. Flagged submissions require manual review of original artifacts and worktree archives. Label scanning is not a guarantee of blindness.#{stable_note}\n")
      File.chmod(0o600, instructions)
    rescue StandardError
      FileUtils.remove_entry(output) if File.exist?(output)
      raise
    end

    {packet_count: shuffled.length, outcome_count: records.length, output: output}
  end

  def load_records(root)
    Dir.glob(File.join(root, "**", "meta.json")).sort.reject do |meta_path|
      Pathname.new(meta_path).relative_path_from(Pathname.new(root)).each_filename.include?("verification-attempts")
    end.filter_map do |meta_path|
      trial_path = File.dirname(meta_path)
      meta = read_json(meta_path)
      next unless meta.is_a?(Hash)

      snapshot = read_json(File.join(trial_path, "snapshot.json")) || {}
      checks = read_json(File.join(trial_path, "checks.json"))
      incident = read_json(File.join(trial_path, "incident.json"))
      {
        path: File.realpath(trial_path),
        relative: relative(root, trial_path),
        meta: meta,
        snapshot: snapshot,
        checks: checks,
        incident: incident,
        validation: validation(meta, snapshot, checks, trial_path, incident)
      }
    end
  end

  def validation(meta, snapshot, checks, trial_path, incident)
    return "fake adapter" if meta["adapter"] == "fake" || meta["status"].to_s.start_with?("fake_")
    return "infrastructure incident" if incident && incident["eligible_behavioral_trial"] == false
    return "status is not complete" unless meta["status"] == "complete"
    return "restoration not verified" unless meta["restoration_verified"] == true
    return "checks are not all passing" unless meta["checks_passed"] == true && passing_checks?(checks)
    return "baseline/final snapshot revisions missing" unless snapshot["baseline"] && snapshot["final"]
    return "baseline/final bundle missing" unless %w[baseline final].all? { |name| File.file?(File.join(trial_path, "#{name}.bundle")) }

    nil
  end

  def passing_checks?(checks)
    checks.is_a?(Array) && !checks.empty? && checks.all? do |check|
      check.is_a?(Hash) && check["exit"] == 0 && check["timed_out"] != true
    end
  end

  def resolve_finals(root, records)
    if records.any? { |record| record[:relative].include?("/continuations/") }
      raise "continuation results require an explicit --final-trials list"
    end

    records.select { |record| record[:validation].nil? }
  end

  def supplied_finals(root, list_path, records, include_stable_failures: false)
    raw = File.read(list_path)
    paths = if raw.lstrip.start_with?("[")
      JSON.parse(raw)
    else
      raw.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    end
    raise "final-trials list must contain paths" unless paths.is_a?(Array) && paths.all? { |path| path.is_a?(String) }

    by_path = records.to_h { |record| [record[:path], record] }
    selected = paths.map do |given|
      expanded = File.expand_path(given, root)
      expanded = File.realpath(expanded) if File.exist?(expanded)
      ensure_within_root!(root, expanded)
      record = by_path[expanded]
      raise "listed final trial has no meta.json: #{given}" unless record
      if record[:validation]
        if include_stable_failures
          reason = stable_failure_validation(record)
          if reason
            record = record.merge(validation: "not packet eligible: #{reason}", review_selection: "excluded from packets: #{reason}")
          else
            record = record.merge(validation: nil, review_selection: "eligible owner-selected stable failed outcome")
          end
        else
          raise "listed trial is not validated: #{given} (#{record[:validation]})"
        end
      end

      record
    end
    roots = selected.map { |record| root_record(record, by_path)[:path] }
    raise "final-trials list contains more than one record for a grid cell" unless roots.uniq.length == roots.length

    selected
  end

  def stable_failure_validation(record)
    meta = record[:meta]
    trial_path = record[:path]
    return "fake adapter" if meta["adapter"] == "fake" || meta["status"].to_s.start_with?("fake_")
    return "infrastructure incident" if record[:incident] && record[:incident]["eligible_behavioral_trial"] == false

    disposition_path = File.join(trial_path, "disposition.json")
    disposition = read_json(disposition_path)
    return "hash-bound owner disposition missing" unless disposition.is_a?(Hash)
    category = disposition["category"]
    expected_status = {"task_failure" => "awaiting_review", "timeout" => "timeout"}[category]
    return "disposition is not terminal task failure or timeout" unless expected_status && meta["status"] == expected_status
    return "disposition reason missing" unless disposition["reason"].is_a?(String) && !disposition["reason"].strip.empty?
    return "disposition does not confirm no pending question" unless disposition["no_pending_question"] == true
    return "disposition is not bound to current metadata" unless disposition["meta_sha256"] == Digest::SHA256.file(File.join(trial_path, "meta.json")).hexdigest
    return "manual owner review: workspace stability not verified" unless meta["workspace_stable"] == true
    return "manual owner review: restoration not verified" unless meta["restoration_verified"] == true
    return "manual owner review: snapshot/bundle evidence invalid" unless valid_snapshot_bundles?(trial_path, record[:snapshot])
    return "manual owner review: snapshot restoration could not be verified" unless Pilot.verify_restore(trial_path)

    nil
  rescue StandardError => error
    "manual owner review: stable failure validation error: #{error.class}: #{error.message}"
  end

  def valid_snapshot_bundles?(trial_path, snapshot)
    return false unless snapshot.is_a?(Hash) && %w[baseline final].all? { |key| snapshot[key].is_a?(String) && !snapshot[key].empty? }

    %w[baseline final].all? do |name|
      bundle = File.join(trial_path, "#{name}.bundle")
      next false unless File.file?(bundle)
      output, _error, status = Open3.capture3("git", "bundle", "list-heads", bundle)
      status.success? && output.lines.any? do |line|
        revision, reference = line.split
        revision == snapshot[name] && reference == "refs/pilot/#{name}"
      end
    end
  end

  def root_record(record, by_path)
    current = record
    seen = {}
    while current[:meta]["source_trial"]
      parent = parent_record_path(current, by_path)
      raise "continuation parent is outside results root: #{current[:relative]}" unless parent
      raise "continuation cycle at #{current[:relative]}" if seen[current[:path]]

      seen[current[:path]] = true
      current = by_path.fetch(parent)
    end
    current
  end

  def parent_record_path(record, by_path)
    source = record[:meta]["source_trial"]
    return nil unless source.is_a?(String) && !source.empty?

    expanded = File.realpath(source) if File.exist?(source)
    by_path.key?(expanded) ? expanded : nil
  end

  def packet_data(root, final, contracts_by_task)
    by_path = load_records(root).to_h { |record| [record[:path], record] }
    root_record = root_record(final, by_path)
    baseline_revision = root_record[:snapshot].fetch("baseline")
    final_revision = final[:snapshot].fetch("final")
    files, patch = production_changes(root_record[:path], final[:path], baseline_revision, final_revision)
    task = root_record[:meta]["task"]
    {trial: final, root_path: root_record[:path], root_meta: root_record[:meta], files: files, patch: patch, contract: contracts_by_task[task]}
  end

  def production_changes(baseline_trial, final_trial, baseline_revision, final_revision)
    Dir.mktmpdir("review-packet") do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p(repo)
      git(repo, "init", "-q")
      git(repo, "config", "gc.auto", "0")
      git(repo, "config", "maintenance.auto", "false")
      {"baseline" => baseline_trial, "final" => final_trial}.each do |name, trial_path|
        bundle = File.join(trial_path, "#{name}.bundle")
        git(repo, "fetch", bundle, "refs/pilot/#{name}:refs/pilot/#{name}")
      end
      baseline = git(repo, "rev-parse", "refs/pilot/baseline").strip
      final = git(repo, "rev-parse", "refs/pilot/final").strip
      raise "bundle revisions changed while building packet" unless baseline == baseline_revision && final == final_revision

      changed_paths = git(repo, "diff", "--no-renames", "--name-only", baseline, final).lines.map(&:chomp)
      production_paths = changed_paths.select { |path| production_code?(path) }
      files = production_paths.map do |path|
        {
          path: path,
          baseline: show_or_missing(repo, baseline, path),
          final: show_or_missing(repo, final, path)
        }
      end
      patch = if production_paths.empty?
        ""
      else
        git(repo, "diff", "--no-ext-diff", "--no-renames", baseline, final, "--", *production_paths)
          .lines.reject { |line| line.start_with?("index ") }.join
      end
      [files, patch]
    end
  end

  def production_code?(path)
    normalized = path.downcase
    components = normalized.split("/")
    blocked = %w[test tests spec specs docs doc vendor .agents .claude .codex .omx]
    return false if (components & blocked).any?
    return false if normalized.start_with?("test/", "tests/", "spec/")
    basename = File.basename(normalized)
    return false if basename.start_with?("test_") || basename.match?(/_(?:test|spec)\.rb\z/)
    return false if normalized.match?(%r{(?:^|/)[^/]+_(?:test|spec)\.rb\z})

    CODE_EXTENSIONS.include?(File.extname(normalized))
  end

  def show_or_missing(repo, revision, path)
    output, error, status = Open3.capture3("git", "-C", repo, "show", "#{revision}:#{path}")
    return "(file absent)\n" unless status.success?

    output.force_encoding(Encoding::UTF_8)
    raise "non-text production source cannot be included: #{path}" unless output.valid_encoding?

    output
  end

  def render_packet(id, packet, hide_outcomes: false)
    metadata_note = if hide_outcomes
      "Trial metadata is not included; this packet builder did not rerun acceptance checks."
    else
      "Trial metadata records passing final acceptance checks and restoration verification; this packet builder did not rerun those checks."
    end
    body = ["# Blinded code review: #{id}", "", "Review the changed production code and its patch. Do not infer an author, condition, or workflow. #{metadata_note} The baseline is the starting code.", ""]
    if packet[:contract]
      body.concat(["## Neutral behavior contract", "", packet[:contract].strip, ""])
    else
      body.concat(["## Context limitation", "", "No neutral behavior contract was supplied. Judge code tradeoffs only from the baseline, final code, and patch.", ""])
    end
    packet[:files].each do |file|
      body << "## #{file[:path]}"
      body << ""
      body << "### Baseline"
      body << ""
      body.concat(indented(file[:baseline]))
      body << ""
      body << "### Final"
      body << ""
      body.concat(indented(file[:final]))
      body << ""
    end
    body.concat(["## Production patch", ""])
    body.concat(indented(packet[:patch]))
    body.concat(["", "## Ratings", "", "Use the separate review rubric. Record one integer from 1 to 5 for each dimension and cite specific code evidence.", "", "- Concepts: ", "- Justified indirection/boundaries: ", "- Cohesion/fit: ", "- Interfaces/error clarity: ", "- Rationale: ", ""])
    body.join("\n")
  end

  def render_outcomes(root, records, selected: [])
    selected_by_path = selected.to_h { |record| [record[:path], record] }
    lines = [
      "# Private trial outcome table",
      "",
      "This file is for the study owner. Do not include it with blinded packets.",
      "",
      "| Trial | Task | Agent | Model | Condition | Track | Status | Packet eligibility | Checks | Restored |",
      "|---|---|---|---|---|---|---|---|---:|---|"
    ]
    records.each do |record|
      meta = record[:meta]
      check_count = record[:checks].is_a?(Array) ? "#{record[:checks].count { |check| check.is_a?(Hash) && check["exit"] == 0 && check["timed_out"] != true }}/#{record[:checks].length}" : "unknown"
      selection = selected_by_path[record[:path]]
      eligibility = if selection && selection[:review_selection]
        selection[:review_selection]
      else
        record[:validation] || "eligible"
      end
      row = [relative(root, record[:path]), meta["task"], meta["agent"], meta["model"], meta["condition"], meta["track"], meta["status"], eligibility, check_count, meta["restoration_verified"]]
      lines << "| #{row.map { |value| escape(value) }.join(' | ')} |"
    end
    lines.join("\n") + "\n"
  end

  def write_private_key(output, key, seed)
    path = File.join(output, "private-key.json")
    File.open(path, "wx", 0o600) do |file|
      file.write(JSON.pretty_generate({seed: seed, packets: key}))
      file.write("\n")
    end
    File.chmod(0o600, path)
  end

  def read_contracts(path)
    contracts = JSON.parse(File.read(path))
    raise "contracts file must be a JSON object of task IDs to neutral text" unless contracts.is_a?(Hash) && contracts.all? { |task, text| task.is_a?(String) && text.is_a?(String) }

    contracts
  end

  def indented(text)
    text.to_s.lines.map { |line| "    #{line.chomp}" }
  end

  def relative(root, path)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  end

  def ensure_within_root!(root, path)
    prefix = root.end_with?(File::SEPARATOR) ? root : root + File::SEPARATOR
    raise "path outside results root" unless path.start_with?(prefix)
  end

  def read_json(path)
    JSON.parse(File.read(path)) if File.file?(path)
  rescue JSON::ParserError
    nil
  end

  def git(repo, *args)
    output, error, status = Open3.capture3("git", "-C", repo, *args)
    raise "git #{args.first} failed: #{error}" unless status.success?

    output
  end

  def escape(value)
    value.nil? ? "unknown" : value.to_s.gsub("|", "\\|").gsub("\n", " ")
  end
end

if $PROGRAM_NAME == __FILE__
  options = {seed: 1}
  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/review_packets.rb RESULTS_ROOT OUTPUT_DIR --seed N [--final-trials FILE] [--contracts FILE] [--include-stable-failures]"
    opts.on("--seed N", Integer, "Deterministic packet order and IDs") { |value| options[:seed] = value }
    opts.on("--final-trials FILE", "One validated final trial path per grid cell (JSON array or newline list)") { |value| options[:final_trials] = value }
    opts.on("--contracts FILE", "Neutral task-ID-to-behavior-contract JSON object") { |value| options[:contracts] = value }
    opts.on("--include-stable-failures", "Secondary review of explicitly selected stable task failures/timeouts; requires --final-trials and does not grade correctness") { options[:include_stable_failures] = true }
  end
  parser.parse!
  abort parser.to_s unless ARGV.length == 2

  begin
    result = ReviewPackets.build(ARGV[0], ARGV[1], **options)
    label = options[:include_stable_failures] ? "Secondary review of selected stable code: " : "Created "
    puts "#{label}#{result[:packet_count]} blinded packets from #{result[:outcome_count]} recorded attempts."
    puts "Private mapping: #{File.join(result[:output], 'private-key.json')}"
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
