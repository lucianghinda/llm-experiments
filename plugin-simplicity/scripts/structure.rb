#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"
require "ripper"
require "tmpdir"
require "fileutils"

# Structural counts are descriptive diagnostics, never a simplicity score.
module StructureDiagnostics
  module_function

  BRANCH_NODES = %i[if unless case when while until for rescue elsif if_mod unless_mod ifop while_mod until_mod rescue_mod].freeze

  def compare(baseline, final)
    left = source_counts(baseline)
    right = source_counts(final)
    deps = dependency_changes(baseline, final)
    {"metric_note" => "Counts describe structural differences; they are not simplicity scores.",
     "source_selection" => "Counts include production .rb files outside test/tests/spec/docs/doc/vendor path components, hidden directories, test_* basenames, and *_test.rb or *_spec.rb basenames.",
     "baseline" => left, "final" => right,
     "delta" => delta_counts(left, right), "dependency_files_changed" => deps}
  rescue StandardError => error
    {"metric_note" => "Counts describe structural differences; they are not simplicity scores.",
     "baseline" => unknown(error), "final" => unknown(error),
     "delta" => unknown(error), "dependency_files_changed" => "unknown"}
  end

  def source_counts(root)
    root = File.expand_path(root)
    return unknown("source path missing") unless File.directory?(root)

    files = Dir.glob(File.join(root, "**", "*.rb"), File::FNM_DOTMATCH).sort.reject do |path|
      test_or_docs?(Pathname.new(path).relative_path_from(Pathname.new(root)).to_s)
    end
    counts = {"ruby_files" => files.length, "classes" => 0, "modules" => 0, "method_definitions" => 0, "branch_nodes" => 0}
    files.each do |path|
      sexp = Ripper.sexp(File.read(path))
      return unknown("syntax error in #{relative(root, path)}") unless sexp

      walk(sexp) do |node|
        counts["classes"] += 1 if node[0] == :class
        counts["modules"] += 1 if node[0] == :module
        counts["method_definitions"] += 1 if %i[def defs].include?(node[0])
        counts["branch_nodes"] += 1 if BRANCH_NODES.include?(node[0])
      end
    end
    counts
  end

  def walk(node, &block)
    return unless node.is_a?(Array)
    yield node if node[0].is_a?(Symbol)
    node.each { |child| walk(child, &block) if child.is_a?(Array) }
  end

  def dependency_changes(baseline, final)
    a = dependency_map(baseline)
    b = dependency_map(final)
    (a.keys | b.keys).sort.filter_map do |path|
      next if a[path] == b[path]
      {"path" => path, "change" => a.key?(path) ? (b.key?(path) ? "modified" : "deleted") : "added"}
    end
  end

  def dependency_map(root)
    root = File.expand_path(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).select do |path|
      next false unless File.file?(path)
      File.basename(path).match?(/\A(?:Gemfile(?:\.lock)?|[^\/]+\.gemspec|gems\.rb)\z/)
    end.to_h { |path| [relative(root, path), File.binread(path)] }
  end

  def delta_counts(left, right)
    keys = %w[ruby_files classes modules method_definitions branch_nodes]
    return unknown("one or more source counts unknown") unless (keys - left.keys).empty? && (keys - right.keys).empty?
    keys.to_h { |key| [key, right[key] - left[key]] }
  end

  def test_or_docs?(path)
    parts = path.split("/")
    return true if parts.any? { |part| part.start_with?(".") || %w[test tests spec docs doc vendor].include?(part.downcase) }

    basename = File.basename(path).downcase
    basename.start_with?("test_") || basename.match?(/_(?:test|spec)\.rb\z/)
  end

  def relative(root, path)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  end

  def unknown(reason)
    {"status" => "unknown", "reason" => reason}
  end

  # Bundle mode materializes revisions in a temporary directory without
  # modifying either the source bundle or the caller's working tree.
  def from_bundles(baseline_bundle, final_bundle)
    Dir.mktmpdir("structure-metrics") do |dir|
      repo = File.join(dir, "repo")
      FileUtils.mkdir_p(repo)
      git(repo, "init", "-q")
      git(repo, "config", "gc.auto", "0")
      git(repo, "config", "maintenance.auto", "false")
      roots = %w[baseline final].map do |name|
        bundle = name == "baseline" ? baseline_bundle : final_bundle
        ref = "refs/pilot/#{name}"
        git(repo, "fetch", File.expand_path(bundle), "#{ref}:refs/metrics/#{name}")
        target = File.join(dir, name)
        FileUtils.mkdir_p(target)
        tar, error, status = Open3.capture3("git", "-C", repo, "archive", "--format=tar", "refs/metrics/#{name}")
        raise "git archive: #{error}" unless status.success?
        _out, error, status = Open3.capture3("tar", "-xf", "-", "-C", target, stdin_data: tar)
        raise "tar extraction: #{error}" unless status.success?
        target
      end
      compare(*roots)
    end
  rescue StandardError => error
    compare("/nonexistent/baseline", "/nonexistent/final").merge("baseline" => unknown("bundle error: #{error.message}"), "final" => unknown("bundle error: #{error.message}"), "delta" => unknown("bundle error"))
  end

  def git(repo, *args)
    out, err, status = Open3.capture3("git", "-C", repo, *args)
    raise "git #{args.first}: #{err}" unless status.success?
    out
  end
end

if $PROGRAM_NAME == __FILE__
  result = if ARGV.length == 3 && ARGV.first == "--bundles"
             StructureDiagnostics.from_bundles(ARGV[1], ARGV[2])
           elsif ARGV.length == 2
             StructureDiagnostics.compare(ARGV[0], ARGV[1])
           else
             warn "usage: structure.rb BASELINE_DIR FINAL_DIR | --bundles BASELINE.bundle FINAL.bundle"
             exit 2
           end
  puts JSON.pretty_generate(result)
end
