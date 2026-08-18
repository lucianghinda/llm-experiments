# Shared helpers for the container kit. Ruby stdlib only.
#
# Every version pin lives here so a rebuild is reproducible and a result can be
# traced back to a toolchain.

require "fileutils"
require "json"
require "open3"
require "shellwords"

module Kit
  PINS = {
    ruby_versions: "3.4.5 4.0.1",
    node_version: "22",
    claude_code_version: "2.1.233",
    codex_version: "0.147.0",
    opencode_version: "1.18.15"
  }.freeze

  BASE_IMAGE = ENV.fetch("LLMX_BASE_IMAGE", "llmx-base:latest")

  # opencode used to live one thin layer above the base, because adding a package
  # to the base invalidates the layers that compile two rubies from source.
  # base/Containerfile carries it now, so on a rebuilt base this is the base
  # image. The derived image is still used when it is present, so a machine that
  # has not rebuilt yet keeps working and neither state fails silently.
  DERIVED_OPENCODE_IMAGE = "llmx-base-opencode:latest"

  # Apple's containers get a small default envelope (992MB / 4 CPU). Rails test
  # suites and `bundle install` need more than that.
  DEFAULT_MEMORY = ENV.fetch("LLMX_MEMORY", "6g")
  DEFAULT_CPUS = ENV.fetch("LLMX_CPUS", "4")

  # Agent credentials live outside the repository and outside every image, in a
  # directory bind-mounted into each trial. Nothing here is ever committed and
  # nothing is ever baked into a layer.
  AUTH_DIR = File.expand_path(ENV.fetch("LLMX_AUTH_DIR", "~/.llmx/auth"))
  AGENT_USER = "agent"

  ROOT = File.expand_path("../../..", __dir__)
  CONTAINERS_DIR = File.join(ROOT, "containers")

  module_function

  # An override that is set but empty is a mistake, not a choice: it would
  # otherwise resolve to an image with no name and fail somewhere less obvious.
  def env_override(name)
    value = ENV[name].to_s.strip
    value.empty? ? nil : value
  end

  # Resolved rather than constant, because answering it means asking the runtime
  # which images exist, and most scripts that require this file never touch a
  # container. Memoised so the question is asked once per process.
  def opencode_image
    @opencode_image ||=
      env_override("LLMX_OPENCODE_IMAGE") ||
      (image_exists?(DERIVED_OPENCODE_IMAGE) ? DERIVED_OPENCODE_IMAGE : BASE_IMAGE)
  end


  def log(message)
    warn "[kit] #{message}"
  end

  # Run a command, stream its output, raise unless it succeeds.
  def sh(*cmd, allow_failure: false)
    log(cmd.shelljoin)
    ok = system(*cmd)
    return ok if ok || allow_failure

    raise "command failed: #{cmd.shelljoin}"
  end

  # Run a command and capture stdout. Raises unless it succeeds.
  def capture(*cmd, allow_failure: false)
    out, err, status = Open3.capture3(*cmd)
    unless status.success? || allow_failure
      raise "command failed: #{cmd.shelljoin}\n#{err}"
    end

    out
  end

  # Run a command and report whether it worked. Use this instead of checking
  # `$?` after `capture`, which drops the status.
  def try(*cmd)
    out, err, status = Open3.capture3(*cmd)
    [out + err, status.success?]
  end

  def try_input(input, *cmd)
    out, err, status = Open3.capture3(*cmd, stdin_data: input)
    [out + err, status.success?]
  end

  def container_cli!
    capture("container", "--version")
  rescue StandardError
    abort "Apple `container` CLI not found. Install it, then run `container system start`."
  end

  # The BuildKit builder is its own VM with its own resource envelope, separate
  # from the trial containers. It defaults to 2 CPUs and 2 GB, which is not
  # enough: compiling a Rails app's native gem extensions exhausts it and the
  # build dies mid-step with no error message at all, which reads like a hang.
  # The memory value needs a unit suffix; a bare number is rejected.
  BUILDER_CPUS = ENV.fetch("LLMX_BUILDER_CPUS", "6")
  BUILDER_MEMORY = ENV.fetch("LLMX_BUILDER_MEMORY", "8G")

  # The apiserver and the BuildKit builder are separate services; a build fails
  # confusingly if only the first one is up.
  def ensure_system_started!
    container_cli!
    status = capture("container", "system", "status", allow_failure: true)
    unless status.include?("apiserver is running")
      log "starting container system"
      sh("container", "system", "start")
    end
    true
  end

  def ensure_builder_started!
    ensure_system_started!
    status = capture("container", "builder", "status", allow_failure: true)
    if status.match?(/^buildkit\s.*\brunning\b/)
      cpus = status[/\brunning\s+\S+\s+(\d+)/, 1].to_i
      return true if cpus >= BUILDER_CPUS.to_i

      log "builder has #{cpus} CPUs; restarting with #{BUILDER_CPUS}"
      sh("container", "builder", "stop", allow_failure: true)
    end

    log "starting image builder (#{BUILDER_CPUS} CPUs, #{BUILDER_MEMORY})"
    sh("container", "builder", "start", "--cpus", BUILDER_CPUS, "--memory", BUILDER_MEMORY)
    true
  end

  # Building an app image needs room for a BuildKit cache and a new snapshot.
  # Running out part way through does not fail cleanly: the build dies without a
  # message, and on a really full disk even writing the error fails. Check first.
  MIN_FREE_GB = ENV.fetch("LLMX_MIN_FREE_GB", "12").to_i

  def free_gb
    line = capture("df", "-g", "/System/Volumes/Data", allow_failure: true).lines.last.to_s
    line.split[3].to_i
  rescue StandardError
    0
  end

  def ensure_disk_space!(need_gb: MIN_FREE_GB)
    free = free_gb
    return true if free >= need_gb

    abort <<~MSG
      Only #{free} GB free; an app image build needs about #{need_gb} GB.

      Most of what this kit uses lives in:
        ~/Library/Application Support/com.apple.container

      To reclaim the BuildKit cache, which is regenerable and often the largest
      single item, stop the builder and delete it:
        container builder stop && container delete buildkit
      Images survive that. `container image list` shows what is kept; remove one
      with `container image delete <name>:<tag>`.
    MSG
  end

  def image_exists?(name)
    repo, tag = name.split(":", 2)
    tag ||= "latest"
    capture("container", "image", "list", allow_failure: true)
      .lines
      .drop(1)
      .any? { |line| line.split[0] == repo && line.split[1] == tag }
  end

  def volume_exists?(name)
    capture("container", "volume", "list", allow_failure: true)
      .lines
      .drop(1)
      .any? { |line| line.split[0] == name }
  end

  def ensure_volume!(name)
    return true if volume_exists?(name)

    log "creating volume #{name}"
    sh("container", "volume", "create", name)
    true
  end

  # Arguments common to every trial container: resource envelope plus the
  # credentials directory. Claude and Codex are pointed at subdirectories of it
  # through CLAUDE_CONFIG_DIR and CODEX_HOME, so a login survives between runs
  # without ever entering an image.
  def run_args(memory: DEFAULT_MEMORY, cpus: DEFAULT_CPUS, mount_auth: true)
    args = ["--memory", memory, "--cpus", cpus.to_s]
    if mount_auth
      FileUtils.mkdir_p(File.join(AUTH_DIR, "claude"))
      FileUtils.mkdir_p(File.join(AUTH_DIR, "codex"))
    FileUtils.mkdir_p(File.join(AUTH_DIR, "opencode"))
      args += ["--volume", "#{AUTH_DIR}:/home/#{AGENT_USER}/.agent-auth"]
      args += ["--env", "CLAUDE_CONFIG_DIR=/home/#{AGENT_USER}/.agent-auth/claude"]
      args += ["--env", "CODEX_HOME=/home/#{AGENT_USER}/.agent-auth/codex"]
      # opencode takes no equivalent variable: it reads credentials from
      # XDG_DATA_HOME, which also holds its sessions and its database. A runner
      # points XDG_DATA_HOME at a private directory and copies the seed in from
      # here, so this only ever says where the seed is.
      args += ["--env", "LLMX_OPENCODE_AUTH=/home/#{AGENT_USER}/.agent-auth/opencode"]
    end
    args
  end

  def apps_config
    path = File.join(ROOT, "at-file-mentions", "apps.yml")
    raise "missing #{path}" unless File.exist?(path)

    TinyYAML.load_file(path)
  end

  # A deliberately small YAML reader: the kit is stdlib-only and the config
  # files here are flat maps, lists and scalars. Anything fancier belongs in a
  # config file that should have been simpler.
  module TinyYAML
    module_function

    def load_file(path)
      parse(File.readlines(path, chomp: true))
    end

    def parse(lines)
      lines = lines.reject { |l| l.strip.empty? || l.strip.start_with?("#") }
      value, _ = parse_block(lines, 0, indent_of(lines.first || ""))
      value
    end

    def indent_of(line)
      line[/\A */].length
    end

    def parse_block(lines, index, indent)
      first = lines[index]
      return [nil, index] unless first

      if first.strip.start_with?("- ")
        parse_sequence(lines, index, indent)
      else
        parse_mapping(lines, index, indent)
      end
    end

    def parse_mapping(lines, index, indent)
      result = {}
      while (line = lines[index])
        current = indent_of(line)
        break if current < indent

        key, _, rest = line.strip.partition(":")
        rest = rest.strip
        index += 1
        if rest.empty?
          nested_indent = lines[index] ? indent_of(lines[index]) : indent
          if nested_indent > current
            result[key], index = parse_block(lines, index, nested_indent)
          else
            result[key] = nil
          end
        else
          result[key] = scalar(rest)
        end
      end
      [result, index]
    end

    def parse_sequence(lines, index, indent)
      result = []
      while (line = lines[index])
        current = indent_of(line)
        break if current < indent || !line.strip.start_with?("- ")

        rest = line.strip.sub(/\A- /, "")
        if rest.include?(":") && !rest.start_with?('"') && !rest.start_with?("'")
          # Inline first key of a mapping item; re-parse the item as a mapping.
          item_lines = [" " * (current + 2) + rest]
          index += 1
          while (nxt = lines[index]) && indent_of(nxt) > current
            item_lines << nxt
            index += 1
          end
          item, _ = parse_mapping(item_lines, 0, current + 2)
          result << item
        else
          result << scalar(rest)
          index += 1
        end
      end
      [result, index]
    end

    def scalar(raw)
      case raw
      when /\A"(.*)"\z/, /\A'(.*)'\z/ then Regexp.last_match(1)
      when "true" then true
      when "false" then false
      when "null", "~", "" then nil
      when /\A-?\d+\z/ then raw.to_i
      when /\A-?\d+\.\d+\z/ then raw.to_f
      else raw
      end
    end
  end
end
