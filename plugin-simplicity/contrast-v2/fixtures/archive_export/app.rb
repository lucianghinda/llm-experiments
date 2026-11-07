class ArchiveExporter
  def initialize(source, writer)
    @source, @writer = source, writer
  end
  def export
    rows = @source.rows
    @writer.write_header
    rows.each { |row| @writer.write_row(row) }
    @writer.finish
  end
end
