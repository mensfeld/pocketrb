# frozen_string_literal: true

require "async"
require "async/queue"

module Pocketrb
  module Bus
    # Thread-safe async message bus for agent communication
    class MessageBus
      attr_reader :stats

      def initialize
        @inbound = Async::Queue.new
        @outbound = Async::Queue.new
        @tool_events = Async::Queue.new
        @state_events = Async::Queue.new
        @subscribers = { inbound: [], outbound: [], tool: [], state: [] }
        @mutex = Mutex.new
        @stats = Stats.new
        @running = false
      end

      # Publish an inbound message from a channel
      def publish_inbound(message)
        raise ArgumentError, "Expected InboundMessage" unless message.is_a?(InboundMessage)

        @stats.increment(:inbound)
        @inbound.enqueue(message)
        notify_subscribers(:inbound, message)
      end

      # Consume the next inbound message (blocking)
      def consume_inbound
        @inbound.dequeue
      end

      # Publish an outbound message to a channel
      def publish_outbound(message)
        raise ArgumentError, "Expected OutboundMessage" unless message.is_a?(OutboundMessage)

        @stats.increment(:outbound)
        @outbound.enqueue(message)
        notify_subscribers(:outbound, message)
      end

      # Consume the next outbound message (blocking)
      def consume_outbound
        @outbound.dequeue
      end

      # Publish a tool execution event
      def publish_tool_event(event)
        raise ArgumentError, "Expected ToolExecution" unless event.is_a?(ToolExecution)

        @stats.increment(:tool_executions)
        @tool_events.enqueue(event)
        notify_subscribers(:tool, event)
      end

      # Consume the next tool event (blocking)
      def consume_tool_event
        @tool_events.dequeue
      end

      # Publish a state change event
      def publish_state_event(event)
        raise ArgumentError, "Expected StateChange" unless event.is_a?(StateChange)

        @stats.increment(:state_changes)
        @state_events.enqueue(event)
        notify_subscribers(:state, event)
      end

      # Subscribe to events
      def subscribe(type, &block)
        raise ArgumentError, "Unknown event type: #{type}" unless @subscribers.key?(type)

        @mutex.synchronize do
          @subscribers[type] << block
        end
      end

      # Unsubscribe from events
      def unsubscribe(type, block)
        @mutex.synchronize do
          @subscribers[type].delete(block)
        end
      end

      # Check if queues have pending messages
      def pending_inbound?
        !@inbound.empty?
      end

      def pending_outbound?
        !@outbound.empty?
      end

      # Clear all queues
      def clear!
        @inbound = Async::Queue.new
        @outbound = Async::Queue.new
        @tool_events = Async::Queue.new
        @state_events = Async::Queue.new
        @stats.reset!
      end

      private

      def notify_subscribers(type, event)
        subscribers = @mutex.synchronize { @subscribers[type].dup }
        subscribers.each do |handler|
          handler.call(event)
        rescue StandardError => e
          Pocketrb.logger.error("Subscriber error for #{type}: #{e.message}")
        end
      end

      # Statistics tracker
      class Stats
        attr_reader :data

        def initialize
          @data = { inbound: 0, outbound: 0, tool_executions: 0, state_changes: 0 }
          @mutex = Mutex.new
        end

        def increment(key)
          @mutex.synchronize { @data[key] += 1 }
        end

        def [](key)
          @mutex.synchronize { @data[key] }
        end

        def reset!
          @mutex.synchronize do
            @data.transform_values! { 0 }
          end
        end

        def to_h
          @mutex.synchronize { @data.dup }
        end
      end
    end
  end
end
