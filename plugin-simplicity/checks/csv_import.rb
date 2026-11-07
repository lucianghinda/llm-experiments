require_relative 'test_support'
require_relative File.join(Dir.pwd, 'app')
class Acceptance < TestSupport::Test
  def test_success_and_atomic_failure
    store = Contacts::Store.new
    importer = Contacts::Importer.new(store)
    assert_equal 1, importer.import("name,email\nExisting,e@example.com\n")
    before = store.records.dup
    assert_raises(ArgumentError) { importer.import("name,email\nValid,v@example.com\nBroken,no-at\n") }
    assert_equal before, store.records
    assert_raises(CSV::MalformedCSVError) { importer.import("name,email\nValid,v@example.com\n\"unterminated") }
    assert_equal before, store.records
    assert_equal 2, importer.import("name,email\nA,a@example.com\nB,b@example.com\n")
    assert_equal 3, store.records.size
  end
end
