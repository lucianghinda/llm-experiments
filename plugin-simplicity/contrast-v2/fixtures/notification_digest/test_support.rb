module TestSupport
  def assert(value, message='assertion failed')
    raise message unless value
  end
  def assert_equal(expected, actual)
    raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end
  def assert_raises(type)
    yield
    raise "expected #{type}"
  rescue type
    true
  end
end
