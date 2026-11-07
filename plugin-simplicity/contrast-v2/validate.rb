require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

root = __dir__
results = []

def run_ruby(workspace, script)
  Open3.capture3(RbConfig.ruby, script, chdir: workspace)
end

%w[notification_digest regional_policy archive_export].each do |id|
  fixture = File.join(root, 'fixtures', id)
  reference = File.join(root, 'references', id)
  test_script = File.join(fixture, 'test', 'test_app.rb')
  _, _, base_status = Open3.capture3(RbConfig.ruby, test_script, chdir: fixture)
  result = {id: id, baseline_passes: base_status.success?}
  %w[acceptance followup].each do |phase|
    check_id = phase == 'acceptance' ? id : "#{id}_followup"
    check_script = File.join(root, 'checks', "#{check_id}.rb")
    _, _, starter_status = run_ruby(fixture, check_script)
    Dir.mktmpdir("#{id}-reference-") do |workspace|
      Dir.children(fixture).each { |entry| FileUtils.cp_r(File.join(fixture, entry), workspace) }
      FileUtils.cp(File.join(reference, 'app.rb'), File.join(workspace, 'app.rb'))
      _, _, reference_baseline = Open3.capture3(RbConfig.ruby, File.join(workspace, 'test', 'test_app.rb'), chdir: workspace)
      stage1_followup_rejects = nil
      if phase == 'followup'
        _, _, stage1_status = run_ruby(workspace, check_script)
        stage1_followup_rejects = !stage1_status.success?
        FileUtils.cp(File.join(reference, 'followup_app.rb'), File.join(workspace, 'app.rb'))
      end
      _, _, reference_status = run_ruby(workspace, check_script)
      result[:reference_baseline_passes] = reference_baseline.success?
      result["starter_#{phase}_rejects"] = !starter_status.success?
      result[:stage1_reference_followup_rejects] = stage1_followup_rejects if phase == 'followup'
      result["reference_#{phase}_passes"] = reference_status.success?
    end
  end
  results << result
end

File.write(File.join(root, 'validation-results.json'), JSON.pretty_generate(results) + "\n")
puts JSON.pretty_generate(results)
expected = results.all? do |result|
  result[:baseline_passes] && result[:reference_baseline_passes] &&
    result['starter_acceptance_rejects'] && result['reference_acceptance_passes'] &&
    result['starter_followup_rejects'] && result['reference_followup_passes'] &&
    result[:stage1_reference_followup_rejects]
end
abort 'fixture validation matrix failed' unless expected
