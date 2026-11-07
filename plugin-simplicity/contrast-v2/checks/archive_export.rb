require File.expand_path('app.rb', Dir.pwd)
require File.expand_path('test_support.rb', Dir.pwd)
include TestSupport
rows=[{id:1},{id:2}]
{header: :header, row: 2, finish: :finish}.each do |phase, fail_on|
  writer=Writer.new(fail_on: fail_on); exporter=ArchiveExporter.new(Source.new(rows),writer)
  error=nil
  begin; exporter.export; rescue IOError => caught; error=caught; end
  raise "#{phase} failure must propagate" unless error && error.equal?(writer.failure) && error.message == "failure at #{fail_on}"
  raise "#{phase} failure leaked partial output" unless writer.events.empty?
  exporter.export
  raise "#{phase} retry output missing" unless writer.events == [[:header],[:row,1],[:row,2],[:finish]]
  raise "#{phase} retry was not idempotent" unless exporter.export == :already_exported
end
