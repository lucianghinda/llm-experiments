require_relative '../test_support'
require_relative '../app'
class IdentifiersTest < TestSupport::Test
  def test_existing_callers
    assert_equal ['abc'], Importer.new.import(['ABC'])
    assert_equal 'abc', ManualEntry.new.create('ABC')
  end
end
