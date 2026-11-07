class OrderReport
  def initialize(orders)
    @orders = orders
  end

  def summary
    {count: @orders.size, total: @orders.sum { |order| order.fetch(:total) }}
  end
end
