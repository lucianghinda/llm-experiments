require_relative 'test_support'
require_relative File.join(Dir.pwd, 'app')
class Acceptance < TestSupport::Test
  def test_cancel_pending_and_reject_other_states
    order = Order.new('pending')
    result = Orders::Cancel.call(order)
    assert result.success?
    assert_nil result.error
    assert_equal 'cancelled', order.status
    %w[shipped cancelled].each do |status|
      order = Order.new(status)
      result = Orders::Cancel.call(order)
      refute result.success?
      refute_nil result.error
      assert_equal status, order.status
    end
  end
end
