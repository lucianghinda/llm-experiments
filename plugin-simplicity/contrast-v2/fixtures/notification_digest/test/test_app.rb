require_relative '../app'; require_relative '../test_support'
class BaselineTest
  include TestSupport
  def test_existing_rules_and_format
    assert_equal false, NotificationPipeline::Rule.new.call(system: true)
    assert_equal true, NotificationPipeline::Rule.new.call(system: false)
    assert_equal 'Mina: Hello', NotificationPipeline::Formatter.new.call(actor: 'Mina', message: 'Hello')
  end
end
BaselineTest.new.test_existing_rules_and_format
puts 'baseline passed'
