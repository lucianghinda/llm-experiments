require "minitest/autorun"
require_relative "../lib/checkout"

class CheckoutRaceTest < Minitest::Test
  def test_two_requests_can_both_charge_after_observing_no_payment
    arrived = Queue.new
    release = Queue.new
    barrier = lambda do
      arrived << true
      release.pop
    end
    store = PaymentStore.new
    gateway = FakeGateway.new
    checkout = Checkout.new(store: store, gateway: gateway, after_lookup: barrier)

    threads = 2.times.map { Thread.new { checkout.charge(41) } }
    2.times { arrived.pop }
    2.times { release << true }
    threads.each(&:value)

    assert_equal 2, gateway.charge_keys.length
    assert_equal 2, store.payments.length
    assert_equal ["order-41"], gateway.charge_keys.map(&:last).uniq
  end
end
