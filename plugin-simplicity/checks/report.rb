require_relative 'test_support'
require_relative File.join(Dir.pwd, 'app')
class Acceptance < TestSupport::Test
  def test_filter_and_totals
    report = OrderReport.new([{status: 'paid', total: 12}, {status: 'pending', total: 7}, {status: 'paid', total: 3}])
    assert_equal({count: 3, total: 22}, report.summary)
    assert_equal({count: 2, total: 15}, report.summary(status: 'paid'))
    assert_equal({count: 0, total: 0}, report.summary(status: 'missing'))
  end
end
