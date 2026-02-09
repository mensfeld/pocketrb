# frozen_string_literal: true

module Pocketrb
  module Planning
    # Represents an execution plan with steps
    class Plan
      attr_reader :name, :description, :steps, :created_at, :metadata
      attr_accessor :status

      # Step statuses
      module StepStatus
        # Step is waiting to be started
        PENDING = "pending"
        # Step is currently being executed
        IN_PROGRESS = "in_progress"
        # Step was completed successfully
        COMPLETED = "completed"
        # Step execution failed
        FAILED = "failed"
        # Step was skipped
        SKIPPED = "skipped"
      end

      # Plan statuses
      module PlanStatus
        # Plan is being drafted
        DRAFT = "draft"
        # Plan is actively being executed
        ACTIVE = "active"
        # Plan completed successfully
        COMPLETED = "completed"
        # Plan execution failed
        FAILED = "failed"
        # Plan was cancelled
        CANCELLED = "cancelled"
      end

      # Plan step data structure
      Step = Data.define(:index, :description, :status, :notes, :completed_at) do
        # Initialize plan step
        # @param index [Integer] Step position in the plan (zero-based)
        # @param description [String] Step description or task to complete
        # @param status [String] Step status (defaults to PENDING)
        # @param notes [String, nil] Additional notes or execution details
        # @param completed_at [Time, nil] Timestamp when step was completed
        def initialize(index:, description:, status: StepStatus::PENDING, notes: nil, completed_at: nil)
          super
        end

        # Check if step is pending
        # @return [Boolean] True if status is PENDING
        def pending?
          status == StepStatus::PENDING
        end

        # Check if step is completed
        # @return [Boolean] True if status is COMPLETED
        def completed?
          status == StepStatus::COMPLETED
        end

        # Check if step failed
        # @return [Boolean] True if status is FAILED
        def failed?
          status == StepStatus::FAILED
        end

        # Convert step to hash
        # @return [Hash] Step data as hash
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

      # Initialize plan
      # @param name [String] Plan name
      # @param description [String, nil] Plan description or goal
      # @param steps [Array<Step, String>] Array of steps (Step objects or strings)
      # @param status [String] Plan status (defaults to DRAFT)
      # @param metadata [Hash] Additional metadata (defaults to empty hash)
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
      # @param description [String] Step description
      # @return [Step] New step instance
      def add_step(description)
        step = Step.new(index: @steps.length, description: description)
        @steps << step
        step
      end

      # Add multiple steps
      # @param descriptions [Array<String>] Array of step descriptions
      # @return [void]
      def add_steps(descriptions)
        descriptions.each { |d| add_step(d) }
      end

      # Update a step's status
      # @param index [Integer] Step index
      # @param status [String] New status value
      # @param notes [String, nil] Optional notes to add
      # @return [Step, nil] Updated step or nil if index invalid
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
      # @param index [Integer] Step index
      # @param notes [String, nil] Optional completion notes
      # @return [Step, nil] Updated step or nil if index invalid
      def complete_step(index, notes: nil)
        update_step(index, status: StepStatus::COMPLETED, notes: notes)
      end

      # Mark a step as failed
      # @param index [Integer] Step index
      # @param notes [String, nil] Optional failure notes
      # @return [Step, nil] Updated step or nil if index invalid
      def fail_step(index, notes: nil)
        update_step(index, status: StepStatus::FAILED, notes: notes)
      end

      # Skip a step
      # @param index [Integer] Step index
      # @param notes [String, nil] Optional skip reason notes
      # @return [Step, nil] Updated step or nil if index invalid
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
      # @param hash [Hash] Hash containing plan data
      # @return [Plan] New plan instance
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
