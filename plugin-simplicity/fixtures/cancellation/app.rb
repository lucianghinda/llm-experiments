Order = Struct.new(:status)
Result = Struct.new(:success?, :error, keyword_init: true)

module Orders
  class Ship
    def self.call(order)
      return Result.new(success?: false, error: 'order cannot be shipped') unless order.status == 'pending'
      order.status = 'shipped'
      Result.new(success?: true, error: nil)
    end
  end
end
