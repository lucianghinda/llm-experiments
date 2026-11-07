class CheckoutShipping
  def quote(region:, subtotal:, weight_kg:)
    threshold = region == :north ? 50.0 : 75.0
    return 0.0 if subtotal >= threshold
    if region == :north
      4.0 + weight_kg * 1.5
    else
      6.0 + weight_kg * 1.0 + 1.0
    end
  end
end

class DeliveryEstimate
  def quote(region:, subtotal:, weight_kg:)
    threshold = region == :north ? 50.0 : 75.0
    return 0.0 if subtotal >= threshold
    if region == :north
      4.0 + weight_kg * 1.5
    else
      6.0 + weight_kg * 1.0
    end
  end
end
