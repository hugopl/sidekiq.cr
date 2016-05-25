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
      abstract def call(job, ctx, &block)
    end

    class Chain
      property entries : Array(Entry)

      def initialize
        @entries = [] of Entry
      end

      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
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

      def invoke(job, ctx, &block)
        chain = entries.map { |k| k }
        next_link(chain, job, ctx, &block)
      end

      def next_link(chain, job, ctx, &block)
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
