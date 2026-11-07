require_relative 'test_support'
require_relative File.join(Dir.pwd, 'app')
class Acceptance < TestSupport::Test
  def test_normalization_and_callers
    assert_equal 'ab-12', Identifiers.normalize('  Ab-12  ')
    assert_nil Identifiers.normalize('   ')
    assert_equal ['ab-12', 'x'], Importer.new.import([' Ab-12 ', ' X '])
    assert_equal 'ab-12', ManualEntry.new.create(' Ab-12 ')
    assert_raises(ArgumentError) { Importer.new.import(['  ']) }
    assert_raises(ArgumentError) { ManualEntry.new.create('  ') }
  end
end
