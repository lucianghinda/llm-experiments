require 'csv'
module Contacts
  class Store
    attr_reader :records
    def initialize
      @records = []
    end
    def add(name:, email:)
      @records << {name: name, email: email}
    end
  end

  class Importer
    def initialize(store)
      @store = store
    end
    def import(csv)
      count = 0
      CSV.parse(csv, headers: true).each do |row|
        name, email = row['name'], row['email']
        raise ArgumentError, 'invalid contact' if name.to_s.strip.empty? || email.to_s.strip.empty? || !email.include?('@')
        @store.add(name: name, email: email)
        count += 1
      end
      count
    end
  end
end
