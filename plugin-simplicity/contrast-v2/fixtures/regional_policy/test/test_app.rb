require_relative '../app'; require_relative '../test_support'
class BaselineTest
  include TestSupport
  def test_existing_quotes
    [CheckoutShipping.new, DeliveryEstimate.new].each do |policy|
      assert_equal 10.0, policy.quote(region: :north, subtotal: 20.0, weight_kg: 4.0)
      expected = policy.class == CheckoutShipping ? 11.0 : 10.0
        assert_equal expected, policy.quote(region: :south, subtotal: 20.0, weight_kg: 4.0)
    end
  end
end
BaselineTest.new.test_existing_quotes
puts 'baseline passed'
