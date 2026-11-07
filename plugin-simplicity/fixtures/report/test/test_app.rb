require_relative '../test_support'
require_relative '../app'
class ReportTest < TestSupport::Test
  def test_summary
    assert_equal({count: 2, total: 30}, OrderReport.new([{total: 10}, {total: 20}]).summary)
  end
end
