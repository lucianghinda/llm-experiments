require_relative '../test_support'
require_relative '../app'
class ShipTest < TestSupport::Test
  def test_ship
    order = Order.new('pending')
    assert Orders::Ship.call(order).success?
    assert_equal 'shipped', order.status
    refute Orders::Ship.call(order).success?
  end
end
