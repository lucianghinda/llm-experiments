class NotificationPipeline
  class Rule; def call(event); !event[:system]; end; end
  class RuleChain
    def initialize(rules); @rules = rules; end
    def eligible?(event); @rules.all? { |rule| rule.call(event) }; end
  end
  class Formatter
    def call(event); "#{event[:actor]}: #{event[:message]}"; end
  end
  class Delivery
    def initialize(sink); @sink = sink; end
    def call(text); @sink << text; end
  end
  def initialize(sink)
    @rules = RuleChain.new([Rule.new])
    @formatter = Formatter.new
    @delivery = Delivery.new(sink)
  end
  def publish(event)
    @delivery.call(@formatter.call(event)) if @rules.eligible?(event)
  end
end
