require_relative '../app'; require_relative '../test_support'
class BaselineTest
  include TestSupport
  def test_exports_all_rows
    w=Writer.new; ArchiveExporter.new(Source.new([{id:1},{id:2}]),w).export
    assert_equal [[:header],[:row,1],[:row,2],[:finish]], w.events
  end
end
BaselineTest.new.test_exports_all_rows
puts 'baseline passed'
