require File.expand_path('app.rb', Dir.pwd)
[CheckoutShipping.new, DeliveryEstimate.new].each do |policy|
  raise 'north free threshold changed' unless policy.quote(region: :north, subtotal: 50, weight_kg: 2) == 0.0
  raise 'south has separate free threshold' unless policy.quote(region: :south, subtotal: 75, weight_kg: 2) == 0.0
  raise 'north should charge below threshold' unless policy.quote(region: :north, subtotal: 49, weight_kg: 2) == 7.0
  expected = policy.class == CheckoutShipping ? 9.0 : 8.0
    raise 'south should charge below threshold' unless policy.quote(region: :south, subtotal: 74, weight_kg: 2) == expected
end
