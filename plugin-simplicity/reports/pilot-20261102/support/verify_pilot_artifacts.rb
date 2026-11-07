require '/Users/luciang/Dropbox/workprojects/explorations/llm-experiments/plugin-simplicity/scripts/harness'
require 'digest'
root = File.expand_path(ARGV.fetch(0))
grid = JSON.parse(File.read(File.join(root, 'grid.json')))
records = []
grid.fetch('cells').each_with_index do |cell, index|
  next if ARGV[1] && cell['task'] != ARGV[1]
  trial = File.join(root, format('%04d', index + 1))
  paths = [File.join(trial, 'meta.json')] + Dir.glob(File.join(trial, 'continuations/*/meta.json'))
  paths.each do |path|
    unless File.file?(path)
      records << {'cell' => index + 1, 'error' => 'missing metadata'}
      next
    end
    out = File.dirname(path)
    meta = JSON.parse(File.read(path))
    archives = meta['worktrees']
    intact = meta['all_worktrees_saved'] == true && archives.is_a?(Array) && !archives.empty? && archives.all? do |entry|
      name = entry['archive']
      name.is_a?(String) && name.match?(/\Aworktree-\d+\.tar\.gz\z/) &&
        File.file?(File.join(out, name)) && Digest::SHA256.file(File.join(out, name)).hexdigest == entry['sha256']
    end
    records << {'cell' => index + 1, 'turn' => out.delete_prefix(root + '/'), 'status' => meta['status'],
                'restoration_verified_now' => Pilot.verify_restore(out), 'archives_verified_now' => intact,
                'transcript_retained' => File.file?(File.join(out, 'transcript.txt'))}
  rescue StandardError => error
    records << {'cell' => index + 1, 'error' => "#{error.class}: #{error.message}"}
  end
end
puts JSON.pretty_generate({'verified_at' => Time.now.utc.iso8601, 'assigned_cells' => grid['cells'].length, 'task_filter' => ARGV[1], 'turns' => records})
exit(records.all? { |r| !r['error'] && r['restoration_verified_now'] && r['archives_verified_now'] && r['transcript_retained'] } ? 0 : 1)
