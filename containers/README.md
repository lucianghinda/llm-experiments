# Container kit

A clean room for measuring agents. Every trial runs in a fresh container with
freshly installed agent CLIs and no host state: no user `CLAUDE.md`, no MCP
servers, no hooks, no project memory. The host only orchestrates.

This kit is not tied to one experiment. Point it at another app and another
prompt and it works the same way.

## Why bother

A throwaway "reply with OK" run of `claude -p` on my own Mac arrives carrying
**8 MCP servers, 39 tools, an auto-memory directory, 5 fired hooks**, and about
**48,000 tokens of context before the task starts**. None of that is the thing
being measured, all of it varies from machine to machine and week to week, and
it is large enough to bury any effect an experiment is looking for.

Inside this kit that same run starts from near enough nothing, and
`parse_transcript.rb` fails loudly if a trial ever reports an MCP server or a
memory path, so a contaminated run cannot be mistaken for a clean one.

## Requirements

Apple's `container` CLI, which runs each container in its own lightweight Linux
VM. Verified against 0.5.0 on Apple silicon.

**Disk.** Budget roughly **10 GB for the base image and 4-8 GB per app image**,
plus a BuildKit cache that reached 9.8 GB building one Rails app. `kit.rb`
refuses to start an app image build below `LLMX_MIN_FREE_GB` (12 GB by default),
because running out mid-build does not fail cleanly: the build dies with no
message, and on a truly full disk even writing the error fails.

What an image actually costs on disk is its **unpacked snapshot**, not the layer
sizes `container image inspect` reports. Measured on 0.5.0: deleting three app
images returned about 16 GB, roughly 5 GB each, against the 1.2-1.6 GB that
`inspect` sums to. Plan reclamation against the snapshot, not the manifest:

```sh
du -sh ~/Library/Application\ Support/com.apple.container/*
container image delete llmx-app-<name>       # the big win, ~5 GB each
container image prune                        # unreferenced and dangling only
```

To reclaim the BuildKit cache, which is regenerable:

```sh
container builder stop && container delete buildkit   # images survive this
```

**That command can fail silently, and did.** See the builder note below before
trusting its exit code.

```sh
container --version
container system start      # the apiserver
container builder start     # BuildKit, a separate service
```

Things worth knowing, each of which cost time to find:

- **`container builder stop` can report success and do nothing.** On 0.5.0, with a
  builder VM that had been up three days, `container builder stop`, `container
  delete --force buildkit` and `container system stop` all returned exit 0 while
  `container ls -a` went on reporting the builder as `running` and its 6.8 GB
  directory stayed on disk. Earlier, at 2.9 GB free, the same `stop` hung for
  seven minutes with no output at all, which is the full-disk failure mode above.
  Always verify with `container ls -a` and `du -sh` rather than the exit code.

  What worked was ending the VM directly, then deleting the container:

  ```sh
  ps -eo pid,etime,command | grep -E 'container-runtime-linux|Virtualization' | grep -v grep
  kill -TERM <runtime-pid> <vm-pid>
  container delete --force buildkit
  ```

  Read that `ps` output before killing anything. The runtime line names
  `--uuid buildkit`, so it is unambiguous, but the VM line is a bare
  `Virtualization.framework` XPC service that looks identical for **any** VM on the
  Mac: Docker, UTM, Parallels, a Simulator. Match it to the runtime process rather
  than pattern-killing on the name.

  A plain `TERM` was enough and `-9` was not needed, which suggests the VM was
  responsive and the CLI's stop path was the broken part. Both processes were
  signalled together, so whether ending the runtime alone would do it is untested.
  The apiserver does not need to be touched and keeps running. The builder is
  recreated on the next build, so the first build after this re-downloads the
  builder image.

- The subcommand is `container image list`. `container images list` looks for a
  plugin that is not installed and fails with a confusing message.
- A trial container's default envelope is about **992 MB and 4 CPUs**, which is
  not enough for `bundle install` or a Rails suite. Everything here passes
  `--memory` and `--cpus` explicitly; see `DEFAULT_MEMORY` in `scripts/lib/kit.rb`.
- **The builder is a separate VM with its own, smaller envelope: 2 CPUs and
  2 GB.** Compiling a Rails app's native gem extensions exhausts it, and when it
  dies the build stops mid-step **with no error message at all** — the log simply
  ends on an ordinary "Installing …" line. It reads exactly like a hang. The kit
  now provisions the builder with 6 CPUs and 8 GB (`BUILDER_CPUS`,
  `BUILDER_MEMORY` in `kit.rb`).
- `--memory` needs a unit suffix. `--memory 8192` is rejected as smaller than
  the minimum, because it is not read as megabytes. Use `8G`.
- **`container run <image> <binary>` does not use the image's `ENV PATH` to
  find `<binary>`.** The rubies here are mise shims under `/opt/mise/shims`,
  so `container run llmx-base ruby foo.rb` fails with
  `No such file or directory` — which names the argument you can see rather
  than the interpreter you cannot, and so reads as a missing script or a
  broken mount. Run through a login shell: `bash -lc "exec ruby foo.rb"`.
  Every invocation in this kit does.
- **A healthy `bundle install` looks identical to the OOM death above.** On the
  postcraftstudio build the step printed nothing for about eight minutes, then
  `Fetching gem metadata` at t=490s and `Bundle complete` at t=1038s. Reading
  CPU tells you little: the work happens inside the VM, and the host-side
  `container-runtime-linux` process reports an average since start. The
  reliable test is whether the build process is still in the process table —
  a starved builder exits, a slow one does not:

  ```sh
  pgrep -f build_app_image.rb >/dev/null && echo alive || echo gone
  ```

- **The builder's DNS is intermittent.** The same build hit
  `Socket::ResolutionError ... Temporary failure in name resolution` for one
  gem while the host resolved `rubygems.org` fine. Bundler's own retry
  recovered it. A build that dies on name resolution is worth simply
  retrying — BuildKit caches every layer up to the failure, so the retry
  resumes rather than restarts.

- A wedged builder does not respond to `container builder stop`, `container kill`
  or `container system stop`; all three hang. Kill the
  `container-runtime-linux` process whose `--root` ends in `/buildkit`, then
  `container delete buildkit` and start a fresh one. Stored images are on disk
  and survive this.

## Layout

```
containers/
  base/Containerfile        Ubuntu 24.04, mise-managed rubies, Node, all three
                            CLIs, postgres, libvips, ffmpeg, sqlite
  opencode/Containerfile    a compatibility layer for a base built before
                            opencode was folded in; delete after the next rebuild
  scripts/lib/kit.rb        version pins, container helpers, a small YAML reader
  scripts/build_base.rb     builds and smoke-checks the base image
  scripts/build_app_image.rb builds a per-app image from a git bundle
  scripts/auth_setup.rb     one-time interactive login, persisted outside images
  scripts/build_opencode_image.rb builds llmx-base-opencode; only needed on an
                            older base, see opencode/Containerfile
  scripts/seed_opencode_auth.rb   copies opencode credentials into the store,
                            as an alternative to logging in
  scripts/trial_shell.rb    interactive shell in a trial container, for debugging
```

## Using it

```sh
ruby containers/scripts/build_base.rb                      # ~20-40 min cold
ruby containers/scripts/auth_setup.rb                      # once, interactive
ruby containers/scripts/build_app_image.rb --app <key>
ruby containers/scripts/trial_shell.rb --app <key>         # when something breaks
```

`build_base.rb` compiles the rubies from source, so the first build is slow and
every later one is cached. All version pins live in `Kit::PINS`; change them
there, nowhere else.

## How code gets in

As a **git bundle**, never as a copy of the working checkout. A bundle carries
committed history and nothing else, which keeps three classes of host junk out
of the image:

- untracked secrets, such as a `.envrc` or a `.env.test.local`
- gitignored bundler config, including local gem path overrides pointing at
  directories that no longer exist
- repository hooks

Images built from private code are never pushed to any registry.

## How credentials get in

Not through an image. `auth_setup.rb` opens an interactive container, you
complete the normal plan-subscription login flows, and the credentials land in
`~/.llmx/auth` on the host. Every trial bind-mounts that directory and points
`CLAUDE_CONFIG_DIR` and `CODEX_HOME` at it. Nothing is baked into a layer and no
API key is needed.

Re-run `auth_setup.rb` when a refresh token expires.

**opencode does not take a variable like the other two.** It keeps credentials
in `XDG_DATA_HOME`, next to its sessions and its database, so pointing that at
the mount would hand every run a shared, host-persisted session store rather
than a credential seed. `auth_setup.rb` points `XDG_DATA_HOME` at a directory
inside the container, lets the login write whatever it wants there, and copies
only `auth.json` back out when the shell exits. Everything else dies with the
container. `seed_opencode_auth.rb` remains as the other way in: it copies this
machine's own credential file across without a login.

**The mounted store is a seed, not a home.** An agent CLI derives more than
credentials from its config directory: Claude Code puts project state and its
auto-memory directory there too. Pointing `CLAUDE_CONFIG_DIR` straight at the
mount therefore gives every trial the same writable, host-persisted directory,
which is a channel between runs that are supposed to be independent. A runner
should copy the credential files into a container-local directory and point
the CLI at the copy, so the mount is only ever read.
`at-file-mentions/scripts/runner.rb` does this; Codex gets the same guarantee
from `--ignore-user-config --ephemeral`.

## Reusing this for another experiment

1. Add the app to your experiment's `apps.yml`: ruby version, database,
   test command, and which files to delete so the repository cannot coach the
   agent under test.
2. Create the branches you want to test and run `build_app_image.rb --app <key>`.
3. Write a runner that reads its configuration from the environment and writes
   its output to `/results`. `at-file-mentions/scripts/runner.rb` is a worked
   example: it isolates the branch, proves the task is real before spending a
   trial on it, runs the agent, and records what changed.

The one rule worth carrying over: **anything that could let the agent read the
answer instead of finding it has to be gone before the agent starts.** For the
`at-file-mentions` experiment that meant flattening git history, because the
planted commit's own diff was the answer. Your experiment will have its own
version of that problem.
