require "minitest/autorun"
require_relative "../model_workspace/lib/checkout"

# A deliberately narrow reference proving serialization prevents the fixture's
# thread race. In production, replace this process-local lock with a durable
# per-order coordination mechanism plus the database unique constraint described
# in answer_key.md; this test does not claim cross-process safety.
class SerializedCheckout < Checkout
  def initialize(**args)
    super
    @workflow_lock = Mutex.new
  end

  def charge(order_id)
    @workflow_lock.synchronize { super }
  end
end

class ReferenceSolutionTest < Minitest::Test
  def test_serialized_solution_reuses_existing_payment_for_concurrent_calls
    store = PaymentStore.new
    gateway = FakeGateway.new
    checkout = SerializedCheckout.new(store: store, gateway: gateway)

    results = 2.times.map { Thread.new { checkout.charge(41) } }.map(&:value)

    assert_equal 1, gateway.charge_keys.length
    assert_equal 1, store.payments.length
    assert_same results.first, results.last
  end
end
