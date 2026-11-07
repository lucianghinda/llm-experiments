class NotificationPipeline
  class Rule; def call(event); !event[:system]; end; end
  class RuleChain
    def initialize(rules); @rules=rules; end
    def eligible?(event); @rules.all? { |rule| rule.call(event) }; end
  end
  class Formatter
    def call(event); "#{event[:actor]}: #{event[:message]}"; end
  end
  class Delivery
    def initialize(sink); @sink=sink; end
    def call(text); @sink << text; end
  end
  def initialize(sink); @rules=RuleChain.new([Rule.new]); @delivery=Delivery.new(sink); @pending=[]; end
  def publish(event)
    return unless @rules.eligible?(event)
    pair=@pending.find { |actor, _| actor == event[:actor] }
    pair ? pair[1] << event[:message] : @pending << [event[:actor], [event[:message]]]
  end
  def flush
    @pending.each { |actor, messages| @delivery.call("#{actor}: #{messages.join('; ')}") }
    @pending.clear
  end
end
