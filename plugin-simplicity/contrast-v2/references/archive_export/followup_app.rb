class ArchiveExporter
  def initialize(source, writer)
    @source, @writer = source, writer
    @published_writers = {}.compare_by_identity
  end

  def export
    export_to(@writer)
  end

  def export_to(writer)
    return :already_exported if @published_writers.key?(writer)

    entries = [[:header]]
    @source.rows.each { |row| entries << [:row, row[:id]] }
    entries << [:finish]
    writer.publish(entries)
    @published_writers[writer] = true
    :exported
  end
end
