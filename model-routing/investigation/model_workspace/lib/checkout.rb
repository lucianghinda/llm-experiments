# A dependency-free stand-in for an ActiveRecord-backed Rails service.
# Each method is individually synchronized like a short database statement,
# but the find-then-insert sequence in Checkout#charge is not one transaction.
class PaymentStore
  Payment = Struct.new(:order_id, :provider_key, keyword_init: true)

  attr_reader :payments

  def initialize
    @payments = []
    @lock = Mutex.new
  end

  def find_by_order(order_id)
    @lock.synchronize { @payments.find { |payment| payment.order_id == order_id } }
  end

  def insert(order_id:, provider_key:)
    @lock.synchronize do
      payment = Payment.new(order_id: order_id, provider_key: provider_key)
      @payments << payment
      payment
    end
  end
end

class FakeGateway
  attr_reader :charge_keys

  def initialize
    @charge_keys = []
    @lock = Mutex.new
  end

  def charge(order_id:, idempotency_key:)
    @lock.synchronize { @charge_keys << [order_id, idempotency_key] }
    "charge-#{@charge_keys.length}"
  end
end

class Checkout
  def initialize(store:, gateway:, after_lookup: -> {})
    @store = store
    @gateway = gateway
    @after_lookup = after_lookup
  end

  def charge(order_id)
    payment = @store.find_by_order(order_id)
    return payment if payment

    # Test seam: both callers can be held here after observing no payment.
    @after_lookup.call
    provider_key = "order-#{order_id}"
    @gateway.charge(order_id: order_id, idempotency_key: provider_key)
    @store.insert(order_id: order_id, provider_key: provider_key)
  end
end
