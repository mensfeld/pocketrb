# frozen_string_literal: true

module Pocketrb
  module Planning
    # Represents an execution plan with steps
    class Plan
      attr_reader :name, :description, :steps, :created_at, :metadata
      attr_accessor :status

      # Step statuses
      module StepStatus
        PENDING = "pending"
        IN_PROGRESS = "in_progress"
        COMPLETED = "completed"
        FAILED = "failed"
        SKIPPED = "skipped"
      end

      # Plan statuses
      module PlanStatus
        DRAFT = "draft"
        ACTIVE = "active"
        COMPLETED = "completed"
        FAILED = "failed"
        CANCELLED = "cancelled"
      end

      Step = Data.define(:index, :description, :status, :notes, :completed_at) do
        def initialize(index:, description:, status: StepStatus::PENDING, notes: nil, completed_at: nil)
          super
        end

        def pending?
          status == StepStatus::PENDING
        end

        def completed?
          status == StepStatus::COMPLETED
        end

        def failed?
          status == StepStatus::FAILED
        end

        def to_h
          {
            index: index,
            description: description,
            status: status,
            notes: notes,
            completed_at: completed_at&.iso8601
          }.compact
        end
      end

      def initialize(name:, description: nil, steps: [], status: PlanStatus::DRAFT, metadata: {})
        @name = name
        @description = description
        @steps = steps.map.with_index do |step, idx|
          step.is_a?(Step) ? step : Step.new(index: idx, description: step.to_s)
        end
        @status = status
        @metadata = metadata
        @created_at = Time.now
      end

      # Add a step to the plan
      def add_step(description)
        step = Step.new(index: @steps.length, description: description)
        @steps << step
        step
      end

      # Add multiple steps
      def add_steps(descriptions)
        descriptions.each { |d| add_step(d) }
      end

      # Update a step's status
      def update_step(index, status:, notes: nil)
        return nil unless @steps[index]

        completed_at = status == StepStatus::COMPLETED ? Time.now : nil

        @steps[index] = Step.new(
          index: index,
          description: @steps[index].description,
          status: status,
          notes: notes || @steps[index].notes,
          completed_at: completed_at
        )

        @steps[index]
      end

      # Mark a step as completed
      def complete_step(index, notes: nil)
        update_step(index, status: StepStatus::COMPLETED, notes: notes)
      end

      # Mark a step as failed
      def fail_step(index, notes: nil)
        update_step(index, status: StepStatus::FAILED, notes: notes)
      end

      # Skip a step
      def skip_step(index, notes: nil)
        update_step(index, status: StepStatus::SKIPPED, notes: notes)
      end

      # Get the next pending step
      def next_step
        @steps.find(&:pending?)
      end

      # Get current step (in progress or next pending)
      def current_step
        @steps.find { |s| s.status == StepStatus::IN_PROGRESS } || next_step
      end

      # Check if plan is complete
      def complete?
        @steps.all?(&:completed?)
      end

      # Check if plan has failed
      def failed?
        @steps.any?(&:failed?)
      end

      # Get progress percentage
      def progress
        return 0 if @steps.empty?

        completed = @steps.count(&:completed?)
        (completed.to_f / @steps.length * 100).round
      end

      # Activate the plan
      def activate!
        @status = PlanStatus::ACTIVE
      end

      # Mark plan as complete
      def mark_complete!
        @status = PlanStatus::COMPLETED
      end

      # Mark plan as failed
      def mark_failed!
        @status = PlanStatus::FAILED
      end

      # Cancel the plan
      def cancel!
        @status = PlanStatus::CANCELLED
      end

      # Format as markdown
      def to_markdown
        lines = ["# Plan: #{@name}"]
        lines << "" << @description if @description
        lines << "" << "Status: #{@status} | Progress: #{progress}%"
        lines << "" << "## Steps" << ""

        @steps.each do |step|
          checkbox = case step.status
                     when StepStatus::COMPLETED then "[x]"
                     when StepStatus::IN_PROGRESS then "[~]"
                     when StepStatus::FAILED then "[!]"
                     when StepStatus::SKIPPED then "[-]"
                     else "[ ]"
                     end

          lines << "#{checkbox} #{step.index + 1}. #{step.description}"
          lines << "   Notes: #{step.notes}" if step.notes
        end

        lines.join("\n")
      end

      # Convert to hash for serialization
      def to_h
        {
          name: @name,
          description: @description,
          steps: @steps.map(&:to_h),
          status: @status,
          metadata: @metadata,
          created_at: @created_at.iso8601,
          progress: progress
        }
      end

      # Create from hash
      def self.from_h(hash)
        steps = (hash[:steps] || hash["steps"] || []).map do |s|
          Step.new(
            index: s[:index] || s["index"],
            description: s[:description] || s["description"],
            status: s[:status] || s["status"] || StepStatus::PENDING,
            notes: s[:notes] || s["notes"],
            completed_at: s[:completed_at] || s["completed_at"] ? Time.parse(s[:completed_at] || s["completed_at"]) : nil
          )
        end

        plan = new(
          name: hash[:name] || hash["name"],
          description: hash[:description] || hash["description"],
          steps: steps,
          status: hash[:status] || hash["status"] || PlanStatus::DRAFT,
          metadata: hash[:metadata] || hash["metadata"] || {}
        )

        if hash[:created_at] || hash["created_at"]
          plan.instance_variable_set(:@created_at, Time.parse(hash[:created_at] || hash["created_at"]))
        end

        plan
      end
    end
  end
end
