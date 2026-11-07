module TestSupport
  class Source
    attr_reader :rows
    def initialize(rows); @rows=rows; end
  end
  class Writer
    attr_reader :events, :failure
    def initialize(fail_on: nil)
      @events=[]; @fail_on=fail_on; @failure=IOError.new("failure at #{fail_on}")
    end
    def fail_if!(phase)
      return unless @fail_on == phase || @fail_on == :row && phase.is_a?(Integer)
      @fail_on=nil
      raise @failure
    end
    def publish(entries)
      entries.each { |entry| fail_if!(entry[0] == :row ? entry[1] : entry[0]) }
      @events.concat(entries)
    end
    def write_header; fail_if!(:header); @events << [:header]; end
    def write_row(row); fail_if!(row[:id]); @events << [:row, row[:id]]; end
    def finish; fail_if!(:finish); @events << [:finish]; end
  end
  def assert_equal(expected, actual)
    raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end
end
