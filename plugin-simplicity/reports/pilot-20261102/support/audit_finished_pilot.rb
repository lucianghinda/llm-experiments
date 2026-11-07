require 'open3'
require 'rbconfig'
require 'json'
root = '/Users/luciang/Dropbox/workprojects/explorations/llm-experiments/plugin-simplicity'
require File.join(root, 'scripts/grid_summary')
grid = File.join(root, 'results-raw/pilot-20261102')
summary = GridSummary.build(grid)
terminal = %w[complete task_failure agent_failure infrastructure_failure timeout]
abort '48 terminal cells required for the final retention audit' unless summary['cells'].size == 48 && summary['cells'].all? { |c| terminal.include?(c['disposition']) }
out, err, status = Open3.capture3(RbConfig.ruby, '/private/tmp/verify_pilot_artifacts.rb', grid)
abort err unless status.success?
audit = JSON.parse(out)
path = File.join(root, 'reports/pilot-20261102/artifact-audit.json')
File.write(path, JSON.pretty_generate(audit) + "\n")
puts JSON.pretty_generate({'assigned_cells' => audit['assigned_cells'], 'verified_turns' => audit['turns'].size, 'audit_path' => path})
