require_relative 'test_support'
require_relative File.join(Dir.pwd, 'app')
class FollowupAcceptance < TestSupport::Test
  def test_both_formats_and_atomicity
    store = Contacts::Store.new
    importer = Contacts::Importer.new(store)
    assert_equal 1, importer.import("name,email\nA,a@example.com\n")
    assert_equal 1, importer.import("full_name,email_address\nB,b@example.com\n")
    before = store.records.dup
    assert_raises(ArgumentError) { importer.import("full_name,email_address\nC,c@example.com\nD,bad\n") }
    assert_equal before, store.records
    assert_equal ['A', 'B'], store.records.map { |record| record.fetch(:name) }
  end
end
