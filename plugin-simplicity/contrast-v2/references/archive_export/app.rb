class ArchiveExporter
  def initialize(source, writer); @source, @writer, @exported = source, writer, false; end
  def export
    return :already_exported if @exported
    staged = []
    staged << [:header]
    @source.rows.each do |row|
      raise IOError, 'writer failed' if @writer.respond_to?(:fail_on) && @writer.fail_on == row[:id]
      staged << [:row, row[:id]]
    end
    staged << [:finish]
    @writer.publish(staged)
    @exported = true
    :exported
  end
end
