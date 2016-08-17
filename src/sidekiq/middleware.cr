module Sidekiq
  #
  # Middleware is code configured to run before/after
  # a message is processed.  It is patterned after Rack
  # middleware. Middleware exists for the client side
  # (pushing jobs onto the queue) as well as the server
  # side (when jobs are actually processed).
  #
  # Middleware must be thread-safe.
  #
  module Middleware
    abstract class Entry
      abstract def call(job, ctx, &block : -> Bool) : Bool
    end

    # We make these two separate types so users don't
    # accidentally add a server middleware to the client
    # chain and vice versa.  Type safety FTW!

    abstract class ServerEntry < Entry
    end

    abstract class ClientEntry < Entry
    end

    class Chain(T)
      property entries : Array(T)

      def initialize
        @entries = [] of T
      end

      def copy
        Chain(T).new.tap do |c|
          c.entries = @entries.dup
        end
      end

      def remove(klass)
        entries.reject! { |entry| entry.class == klass }
      end

      def add(klass)
        entries.delete klass
        entries.push klass
      end

      def prepend(klass)
        entries.delete(klass)
        entries.insert(0, klass)
      end

      def insert_before(oldklass, newklass)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? newklass : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || 0
        entries.insert(i, new_entry)
      end

      def insert_after(oldklass, newklass)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? newklass : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || entries.count - 1
        entries.insert(i + 1, new_entry)
      end

      def clear
        entries.clear
      end

      def invoke(job, ctx, &block : -> Bool) : Bool
        chain = entries.map { |k| k }
        next_link(chain, job, ctx, &block)
      end

      def next_link(chain, job, ctx, &block : -> Bool) : Bool
        if chain.empty?
          block.call
        else
          chain.shift.call(job, ctx) do
            next_link(chain, job, ctx, &block)
          end
        end
      end
    end
  end
end
