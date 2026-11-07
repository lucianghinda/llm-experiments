require 'tmpdir'
require 'rbconfig'
require 'fileutils'
require 'open3'
root = File.expand_path("..", __dir__)
solutions = {
  'report' => ->(s) { s.sub('def summary', 'def summary(status: nil)').sub('{count: @orders.size, total: @orders.sum { |order| order.fetch(:total) }}', "orders = status.nil? ? @orders : @orders.select { |order| order[:status] == status }\n    {count: orders.size, total: orders.sum { |order| order.fetch(:total) }}") },
  'identifiers' => ->(s) { s.sub('value.downcase', "normalized = value.to_s.strip.downcase\n    normalized.empty? ? nil : normalized").gsub('Identifiers.normalize(value)', "Identifiers.normalize(value) || raise(ArgumentError, 'blank identifier')") },
  'cancellation' => ->(s) { s.sub("  class Ship\n", "  class Cancel\n    def self.call(order)\n      return Result.new(success?: false, error: 'order cannot be cancelled') unless order.status == 'pending'\n      order.status = 'cancelled'\n      Result.new(success?: true, error: nil)\n    end\n  end\n\n  class Ship\n") },
  'csv_import' => ->(s) { s.sub("      count = 0\n      CSV.parse(csv, headers: true).each do |row|", "      rows = CSV.parse(csv, headers: true).map do |row|").sub("        @store.add(name: name, email: email)\n        count += 1\n      end\n      count", "        {name: name, email: email}\n      end\n      rows.each { |row| @store.add(**row) }\n      rows.size") }
}
Dir.mktmpdir('fixtures-validation') do |tmp|
  solutions.each do |id, solution|
    dir = File.join(tmp, id)
    FileUtils.cp_r(File.join(root, 'fixtures', id), dir)
    check = File.join(root, 'checks', "#{id}.rb")
    [['baseline suite', [RbConfig.ruby, 'test/test_app.rb'], true], ['baseline acceptance', [RbConfig.ruby, check], false]].each do |label, cmd, expected|
      output, status = Open3.capture2e(*cmd, chdir: dir)
      abort "#{id} #{label} unexpected: #{output}" unless status.success? == expected
      puts "#{id}: #{label} #{expected ? 'passed' : 'failed as expected'}"
    end
    app = File.join(dir, 'app.rb')
    File.write(app, solution.call(File.read(app)))
    [['reference suite', [RbConfig.ruby, 'test/test_app.rb']], ['reference acceptance', [RbConfig.ruby, check]]].each do |label, cmd|
      output, status = Open3.capture2e(*cmd, chdir: dir)
      abort "#{id} #{label} failed: #{output}" unless status.success?
      puts "#{id}: #{label} passed"
    end
    if id == 'csv_import'
      follow = File.join(root, 'checks/csv_import_followup.rb')
      output, status = Open3.capture2e(RbConfig.ruby, follow, chdir: dir)
      abort "followup unexpectedly passed" if status.success?
      source = File.read(app).sub("name, email = row['name'], row['email']", "name, email = row['name'] || row['full_name'], row['email'] || row['email_address']")
      File.write(app, source)
      output, status = Open3.capture2e(RbConfig.ruby, follow, chdir: dir)
      abort "followup failed: #{output}" unless status.success?
      puts 'csv_import: followup rejects first stage and passes reference followup'
    end
  end
end
