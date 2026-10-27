#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds a throwaway git repo with a staged bug fix, ready for an agent to commit.
#
#   ruby fixture.rb <path>
#
# The history is deliberately NON-conventional (plain sentence case) so that any
# Conventional Commits output can only come from the control under test, never
# from the agent imitating the log.

require "fileutils"

ROOT = ARGV[0] or abort "usage: fixture.rb <path>"

CART_BEFORE = <<~CODE
  # frozen_string_literal: true

  class Cart
    Item = Data.define(:name, :price_cents, :quantity)

    def initialize
      @items = []
    end

    def add(name, price_cents, quantity: 1)
      @items << Item.new(name:, price_cents:, quantity:)
      self
    end

    def total_cents
      @items.sum(&:price_cents)
    end
  end
CODE

CART_AFTER = CART_BEFORE.sub(
  "    @items.sum(&:price_cents)\n",
  "    @items.sum { |item| item.price_cents * item.quantity }\n"
)

raise "patch did not apply" if CART_AFTER == CART_BEFORE

README = <<~MD
  # cart

  A shopping cart that adds up line items.
MD

def git(*args)
  ok = system("git", *args, out: File::NULL, err: File::NULL)
  raise "git #{args.join(' ')} failed" unless ok
end

FileUtils.rm_rf(ROOT)
FileUtils.mkdir_p("#{ROOT}/lib")
Dir.chdir(ROOT)

git("init", "-q", "-b", "main")
git("config", "user.name", "Test Dev")
git("config", "user.email", "dev@example.com")
git("config", "commit.gpgsign", "false")

# Three commits of plain, non-conventional history.
File.write("lib/cart.rb", CART_BEFORE.sub(/  def total_cents.*?  end\n/m, ""))
git("add", "-A")
git("commit", "-q", "-m", "Add cart with line items")

File.write("lib/cart.rb", CART_BEFORE)
git("add", "-A")
git("commit", "-q", "-m", "Add total in cents")

File.write("README.md", README)
git("add", "-A")
git("commit", "-q", "-m", "Add readme")

# The change under test: totals ignored quantity, so 3 of an item charged for 1.
File.write("lib/cart.rb", CART_AFTER)
git("add", "-A")

puts ROOT
