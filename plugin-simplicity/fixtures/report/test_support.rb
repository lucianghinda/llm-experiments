module TestSupport
  class Test
    def self.inherited(child)
      at_exit do
        child.instance_methods(false).grep(/^test_/).each { |name| child.new.public_send(name) }
        puts "#{child}: passed"
      end
    end
    def assert(value)
      raise 'assertion failed' unless value
    end
    def refute(value)
      assert(!value)
    end
    def assert_equal(expected, actual)
      raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
    end
    def assert_nil(value)
      assert_equal nil, value
    end
    def refute_nil(value)
      refute value.nil?
    end
    def assert_raises(error)
      begin
        yield
      rescue error
        return
      end
      raise "expected #{error}"
    end
  end
end
