# frozen_string_literal: true

# Shared plumbing for the per-task acceptance checks. Runs inside the trial
# container, after the agent has stopped and after runner.rb has recorded the
# diff, so nothing here can be mistaken for the agent's own work.
#
# Every task decides success by script. "It looks right" is not a measurement,
# and a trial that produced a plausible-looking wrong answer has to score as a
# failure or the token counts describe nothing.

require "json"
require "open3"

module Acceptance
  APP_DIR = "/workspace/app"
  RESULTS = "/results"

  module_function

  def run(cmd, timeout: nil, env: {})
    cmd = "timeout #{timeout} #{cmd}" if timeout
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out, err, status = Open3.capture3(env, cmd, chdir: APP_DIR)
    { "cmd" => cmd, "exit" => status.exitstatus, "out" => out + err,
      "seconds" => (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1) }
  end

  def log(message)
    warn "[check] #{message}"
  end

  def variant
    ENV.fetch("LLMX_VARIANT", "unknown")
  end

  # The files a competent answer had to reach, already resolved to this
  # variant's spelling by run_trial.rb.
  def targets
    ENV.fetch("LLMX_TARGETS", "").split(",").reject(&:empty?)
  end

  # The agent's final message, extracted by runner.rb. Empty when the agent
  # produced no closing text, which is itself a result rather than an error.
  def answer
    path = File.join(RESULTS, "answer.txt")
    File.exist?(path) ? File.read(path) : ""
  end

  # Paths the answer cites, normalised so an absolute or dot-prefixed spelling
  # of the right file still counts. Reporting the correct file in an unexpected
  # notation is a formatting difference, not a navigation failure.
  def cited_paths(text = answer)
    text.to_s.scan(%r{[\w./-]+\.(?:rb|erb|yml|yaml)(?::\d+)?}).map do |raw|
      raw.sub(/:\d+\z/, "")
         .sub(%r{\A/workspace/app/}, "")
         .sub(%r{\A\./}, "")
         .sub(%r{\A/}, "")
    end.uniq
  end

  def cited_lines(text = answer)
    text.to_s.scan(%r{[\w./-]+\.(?:rb|erb):(\d+)}).flatten.map(&:to_i).uniq
  end

  # Whether the app's own suite still passes. Charged separately from the task's
  # acceptance: a trial that reached the goal by breaking six other tests has
  # not done the task, and one that is merely slow has. Conflating them would
  # hide both.
  def regression_suite
    return { "ran" => false, "ok" => nil, "summary" => "skipped" } if ENV["LLMX_REGRESSION_SUITE"] == "0"

    result = run("bin/rails test", timeout: 2400)
    summary = result["out"][/\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?/]
    { "ran" => true, "ok" => result["exit"].zero? && !summary.nil?,
      "summary" => summary || "no summary line", "seconds" => result["seconds"] }
  end

  # `checks` decides the verdict; `facts` is recorded and never gates it. The
  # split matters: a locate task should pass on naming the right file even when
  # the line number is off by one, but the line number is still worth keeping.
  def report(checks, facts = {})
    passed = checks.all? { |c| c["ok"] }
    payload = {
      "task" => ENV["LLMX_TASK"],
      "variant" => variant,
      "passed" => passed,
      "checks" => checks,
      "facts" => facts,
      "finished_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    File.write(File.join(RESULTS, "acceptance.json"), JSON.pretty_generate(payload))
    checks.each { |c| log(format("%-5s %s", c["ok"] ? "ok" : "FAIL", c["label"])) }
    log("acceptance: #{passed ? 'PASSED' : 'FAILED'}")
    exit(passed ? 0 : 1)
  end
end
