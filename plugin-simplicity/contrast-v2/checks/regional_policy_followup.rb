require File.expand_path('app.rb', Dir.pwd)
raise 'north boundary is inclusive' unless CheckoutShipping.new.quote(region: :north, subtotal: 50, weight_kg: 1) == 0.0
raise 'south boundary is inclusive' unless DeliveryEstimate.new.quote(region: :south, subtotal: 75, weight_kg: 1) == 0.0
raise 'north below boundary' unless DeliveryEstimate.new.quote(region: :north, subtotal: 49, weight_kg: 2) == 7.0
raise 'south below boundary' unless CheckoutShipping.new.quote(region: :south, subtotal: 74, weight_kg: 2) == 9.0
raise 'checkout fee applies to south small parcel' unless CheckoutShipping.new.quote(region: :south, subtotal: 20, weight_kg: 1) == 10.0
raise 'estimator must omit checkout handling fee' unless DeliveryEstimate.new.quote(region: :south, subtotal: 20, weight_kg: 1) == 7.0

raise "south free shipping must waive all charges" unless CheckoutShipping.new.quote(region: :south, subtotal: 75, weight_kg: 1) == 0.0
raise "exactly 2 kg excludes the extra charge" unless CheckoutShipping.new.quote(region: :south, subtotal: 74, weight_kg: 2) == 9.0
raise "north checkout quote remains unchanged" unless CheckoutShipping.new.quote(region: :north, subtotal: 20, weight_kg: 1) == 5.5
