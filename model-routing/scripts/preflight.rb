# frozen_string_literal: true

module ModelRoutingPreflight
  MIN_FREE_GB = 4
  NON_CHATGPT_AUTH = /\A(?:API key configured|Logged in using (?:API key|access token|personal access token))\b/i

  module_function

  def codex_chatgpt_login_error(output, command_success:)
    return "codex login status command failed" unless command_success

    lines = output.to_s.lines.map(&:strip).reject(&:empty?)
    return "Codex is authenticated through a non-ChatGPT credential" if lines.any? { |line| line.match?(NON_CHATGPT_AUTH) }
    return nil if lines.include?("Logged in using ChatGPT")

    "codex login status did not positively report 'Logged in using ChatGPT'"
  end

  def claude_login_error(output, command_success:)
    return "claude auth status command failed" unless command_success

    require "json"
    status = JSON.parse(output)
    return nil if status["loggedIn"] == true
    return "Claude is not logged in" if status["loggedIn"] == false

    "claude auth status did not report a boolean loggedIn value"
  rescue JSON::ParserError
    "claude auth status returned invalid JSON"
  end

  def disk_error(free_gb)
    return nil if free_gb >= MIN_FREE_GB

    "only #{free_gb} GiB free; at least #{MIN_FREE_GB} GiB is required before each trial"
  end
end
