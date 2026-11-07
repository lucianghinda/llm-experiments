module Identifiers
  def self.normalize(value)
    value.downcase
  end
end

class Importer
  def import(values)
    values.map { |value| Identifiers.normalize(value) }
  end
end

class ManualEntry
  def create(value)
    Identifiers.normalize(value)
  end
end
