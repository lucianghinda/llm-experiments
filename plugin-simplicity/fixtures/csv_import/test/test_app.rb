require_relative '../test_support'
require_relative '../app'
class ImportTest < TestSupport::Test
  def test_import
    store = Contacts::Store.new
    assert_equal 1, Contacts::Importer.new(store).import("name,email\nAda,ada@example.com\n")
    assert_equal [{name: 'Ada', email: 'ada@example.com'}], store.records
  end
end
