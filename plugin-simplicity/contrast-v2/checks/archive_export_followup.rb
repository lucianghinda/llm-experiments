require File.expand_path('app.rb', Dir.pwd)
require File.expand_path('test_support.rb', Dir.pwd)
include TestSupport

rows = [{id: 1}, {id: 2}]
source = Source.new(rows)
default_writer = Writer.new
alternate_writer = Writer.new(fail_on: 2)
exporter = ArchiveExporter.new(source, default_writer)

exporter.export
raise 'default output is wrong' unless default_writer.events == [[:header], [:row, 1], [:row, 2], [:finish]]

error = nil
begin
  exporter.export_to(alternate_writer)
rescue IOError => caught
  error = caught
end
raise 'alternate writer must propagate its own error' unless error && error.equal?(alternate_writer.failure)
raise 'alternate failure must not publish partial output' unless alternate_writer.events.empty?
raise 'alternate failure must not reset default completion' unless exporter.export == :already_exported
raise 'default writer must not be called twice' unless default_writer.events == [[:header], [:row, 1], [:row, 2], [:finish]]

exporter.export_to(alternate_writer)
raise 'alternate writer did not receive source rows' unless alternate_writer.events == [[:header], [:row, 1], [:row, 2], [:finish]]
raise 'alternate writer should now be idempotent' unless exporter.export_to(alternate_writer) == :already_exported

third_writer = Writer.new
exporter.export_to(third_writer)
raise 'third writer should receive same source rows' unless third_writer.events == [[:header], [:row, 1], [:row, 2], [:finish]]
raise 'source data must remain unchanged' unless source.rows == rows
