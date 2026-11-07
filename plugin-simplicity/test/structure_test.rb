# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/structure"

class StructureDiagnosticsTest
  def with_sources
    Dir.mktmpdir("structure-test") do |root|
      baseline = File.join(root, "baseline")
      final = File.join(root, "final")
      FileUtils.mkdir_p([baseline, final])
      yield baseline, final
    end
  end

  def write(root, path, content)
    target = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end

  def test_counts_classes_modules_method_forms_and_branch_nodes
    with_sources do |baseline, final|
      write(baseline, "lib/a.rb", "class A\n def one; end\nend\n")
      write(final, "lib/a.rb", "module M\n class A\n def one; end\n def self.two; if true; end; end\n def three; x if y; x unless z; x while q; x until r; x rescue nil; a ? b : c; end\n end\nend\n")
      result = StructureDiagnostics.compare(baseline, final)
      equal({"ruby_files" => 1, "classes" => 1, "modules" => 0, "method_definitions" => 1, "branch_nodes" => 0}, result["baseline"])
      equal({"ruby_files" => 1, "classes" => 1, "modules" => 1, "method_definitions" => 3, "branch_nodes" => 7}, result["final"])
      equal(2, result.dig("delta", "method_definitions"))
      match(/not simplicity scores/, result["metric_note"])
    end
  end

  def test_excludes_report_packet_nonproduction_paths
    with_sources do |baseline, final|
      write(final, "lib/a.rb", "def x; end")
      write(final, "test/a_test.rb", "class TestThing; end")
      write(final, "lib/test_support.rb", "class TestSupport; end")
      write(final, "lib/a_test.rb", "class ATest; end")
      write(final, "lib/a_spec.rb", "class ASpec; end")
      write(final, "docs/example.rb", "module Example; end")
      write(final, "app/vendor/generated.rb", "module Generated; end")
      write(final, ".omx/workflow.rb", "module Workflow; end")
      write(final, "app/.github/workflow.rb", "module GithubWorkflow; end")
      equal(1, StructureDiagnostics.source_counts(final)["ruby_files"])
    end
  end

  def test_syntax_error_returns_unknown_instead_of_zero
    with_sources do |baseline, final|
      write(baseline, "lib/a.rb", "def ok; end")
      write(final, "lib/a.rb", "class Broken\n")
      result = StructureDiagnostics.compare(baseline, final)
      equal("unknown", result.dig("final", "status"))
      match(/syntax error/, result.dig("final", "reason"))
      equal("unknown", result.dig("delta", "status"))
    end
  end

  def test_dependency_changes_are_reported_separately
    with_sources do |baseline, final|
      write(baseline, "Gemfile", "source 'https://rubygems.org'\n")
      write(final, "Gemfile", "source 'https://rubygems.org'\ngem 'rake'\n")
      write(final, "new.gemspec", "Gem::Specification.new\n")
      changes = StructureDiagnostics.dependency_changes(baseline, final)
      equal([{"path" => "Gemfile", "change" => "modified"}, {"path" => "new.gemspec", "change" => "added"}], changes)
    end
  end

  def test_harness_style_bundles_use_pilot_refs
    Dir.mktmpdir("bundle-smoke") do |root|
      repo = File.join(root, "repo")
      FileUtils.mkdir_p(repo)
      git(repo, "init", "-q")
      git(repo, "config", "user.name", "Test")
      git(repo, "config", "user.email", "test@example.invalid")
      write(repo, "lib/a.rb", "class A; end\n")
      git(repo, "add", "-A")
      git(repo, "commit", "-qm", "baseline")
      baseline = git(repo, "rev-parse", "HEAD").strip
      git(repo, "update-ref", "refs/pilot/baseline", baseline)
      baseline_bundle = File.join(root, "baseline.bundle")
      git(repo, "bundle", "create", baseline_bundle, "refs/pilot/baseline")
      write(repo, "lib/a.rb", "class A; def run; if true; end; end; end\n")
      git(repo, "add", "-A")
      git(repo, "commit", "-qm", "final")
      git(repo, "update-ref", "refs/pilot/final", "HEAD")
      final_bundle = File.join(root, "final.bundle")
      git(repo, "bundle", "create", final_bundle, "refs/pilot/final")

      result = StructureDiagnostics.from_bundles(baseline_bundle, final_bundle)
      equal(1, result.dig("baseline", "classes"))
      equal(1, result.dig("final", "method_definitions"))
      equal(1, result.dig("final", "branch_nodes"))
      equal(1, result.dig("delta", "branch_nodes"))
    end
  end

  def git(repo, *args)
    output, error, status = Open3.capture3("git", "-C", repo, *args)
    raise "git #{args.first}: #{error}" unless status.success?
    output
  end
end

def equal(expected, actual)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end

def match(pattern, actual)
  raise "expected #{actual.inspect} to match #{pattern.inspect}" unless pattern.match?(actual)
end

tests = StructureDiagnosticsTest.new
tests.methods.grep(/^test_/).sort.each do |name|
  tests.public_send(name)
  puts "PASS #{name}"
end
