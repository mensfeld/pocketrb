# frozen_string_literal: true

# Pocketrb: Ruby AI agent with multi-LLM support and advanced planning capabilities
module Pocketrb
  # Tool implementations for agent capabilities
  module Tools
    # PARA-based memory tool for structured knowledge management
    class ParaMemory < Base
      # Tool name
      # @return [String]
      def name
        "para_memory"
      end

      # Tool description
      # @return [String]
      def description
        <<~DESC.strip
          Structured memory using PARA method. Store and retrieve facts about people, projects,
          companies, and topics. Facts are organized, decay over time, and build a knowledge graph.
          Use this for durable information that should persist across conversations.
        DESC
      end

      # Parameter schema
      # @return [Hash]
      def parameters
        {
          type: "object",
          properties: {
            action: {
              type: "string",
              enum: %w[store search entity_info create_entity list_entities context preferences learn_preference],
              description: "Action to perform"
            },
            # For store action
            content: {
              type: "string",
              description: "Fact content to store"
            },
            category: {
              type: "string",
              enum: %w[relationship milestone status preference context],
              description: "Fact category (for store)"
            },
            entity_type: {
              type: "string",
              enum: %w[projects areas resources archives],
              description: "PARA entity type"
            },
            entity_name: {
              type: "string",
              description: "Entity name (e.g., 'zakiya', 'people/john', 'companies/acme')"
            },
            # For search action
            query: {
              type: "string",
              description: "Search query"
            },
            # For create_entity
            entity_subtype: {
              type: "string",
              enum: %w[project person company topic],
              description: "What kind of entity to create"
            },
            # For learn_preference
            preference_category: {
              type: "string",
              enum: %w[communication_preferences working_style tool_preferences rules_and_boundaries],
              description: "Preference category"
            },
            preference_key: {
              type: "string",
              description: "Preference key (e.g., 'verbosity', 'timezone')"
            },
            preference_value: {
              type: "string",
              description: "Preference value"
            }
          },
          required: ["action"]
        }
      end

      # Check if tool is available
      # @return [Boolean] true if PARA manager is configured
      def available?
        !para_manager.nil?
      end

      # Execute memory action
      # @param action [String] Action to perform (store, search, entity_info, create_entity, list_entities, context, preferences, learn_preference)
      # @option args [String] :content Fact content to store
      # @option args [String] :category Fact category (relationship, milestone, status, preference, context)
      # @option args [String] :entity_type PARA entity type (projects, areas, resources, archives)
      # @option args [String] :entity_name Entity name
      # @option args [String] :query Search query
      # @option args [String] :entity_subtype Entity subtype for creation (project, person, company, topic)
      # @option args [String] :preference_category Preference category
      # @option args [String] :preference_key Preference key
      # @option args [String] :preference_value Preference value
      # @return [String] Action result or error message
      def execute(action:, **args)
        return error("PARA memory not available. Configure memory_dir in agent settings.") unless para_manager

        case action
        when "store"
          store_fact(args)
        when "search"
          search_memory(args[:query])
        when "entity_info"
          get_entity_info(args[:entity_type], args[:entity_name])
        when "create_entity"
          create_entity(args)
        when "list_entities"
          list_entities(args[:entity_type])
        when "context"
          get_context(args[:query])
        when "preferences"
          get_preferences
        when "learn_preference"
          learn_preference(args)
        else
          error("Unknown action: #{action}")
        end
      end

      private

      def para_manager
        @context[:para_manager]
      end

      def store_fact(args)
        content = args[:content]
        return error("Content required") if content.nil? || content.empty?

        category = (args[:category] || "context").to_sym
        entity_type = args[:entity_type]&.to_sym
        entity_name = args[:entity_name]

        if entity_type && entity_name
          fact = para_manager.store_fact(
            entity_type: entity_type,
            entity_name: entity_name,
            content: content,
            category: category
          )
          success("Stored fact in #{entity_type}/#{entity_name}: #{content[0..50]}... (ID: #{fact.id})")
        else
          para_manager.remember(content: content, category: category)
          success("Stored fact: #{content[0..50]}...")
        end
      end

      def search_memory(query)
        return error("Query required") if query.nil? || query.empty?

        results = para_manager.search(query)

        lines = ["Search results for: #{query}\n"]

        if results[:knowledge_graph].any?
          lines << "**Knowledge Graph:**"
          results[:knowledge_graph].each do |r|
            lines << "  #{r[:entity]}:"
            r[:facts].first(3).each { |f| lines << "    - #{f}" }
          end
        end

        if results[:daily_notes].any?
          lines << "\n**Daily Notes:**"
          results[:daily_notes].first(5).each do |r|
            lines << "  #{r[:date]}:"
            r[:matches].first(2).each { |m| lines << "    - #{m}" }
          end
        end

        if results[:tacit].any?
          lines << "\n**Preferences:**"
          results[:tacit].each do |r|
            lines << "  #{r[:category]}/#{r[:key]}: #{r[:value]}"
          end
        end

        lines << "No results found." if lines.size == 1

        lines.join("\n")
      end

      def get_entity_info(entity_type, entity_name)
        return error("Entity type and name required") unless entity_type && entity_name

        summary = para_manager.entity_summary(type: entity_type.to_sym, name: entity_name)
        return error("Entity not found: #{entity_type}/#{entity_name}") unless summary

        summary
      end

      def create_entity(args)
        subtype = args[:entity_subtype]
        name = args[:entity_name]
        content = args[:content]

        return error("Entity subtype and name required") unless subtype && name

        case subtype
        when "project"
          para_manager.create_project(name: name, description: content)
          success("Created project: #{name}")
        when "person"
          para_manager.create_person(name: name, relationship: content)
          success("Created person: #{name}")
        when "company"
          para_manager.create_company(name: name, context: content)
          success("Created company: #{name}")
        when "topic"
          para_manager.knowledge_graph.create_entity(
            type: :resources,
            name: name,
            initial_facts: content ? [{ content: content, category: :context }] : []
          )
          success("Created topic: #{name}")
        else
          error("Unknown entity subtype: #{subtype}")
        end
      end

      def list_entities(entity_type)
        if entity_type
          entities = para_manager.knowledge_graph.list_entities(entity_type.to_sym)
          return "No #{entity_type} entities found." if entities.empty?

          lines = ["#{entity_type.capitalize}:"]
          entities.each do |e|
            e.load!
            lines << "  - #{e.name} (#{e.active_facts.size} facts)"
          end
          lines.join("\n")
        else
          para_manager.full_context_summary
        end
      end

      def get_context(query)
        if query && !query.empty?
          para_manager.relevant_context(query)
        else
          para_manager.full_context_summary
        end
      end

      def get_preferences
        prefs = para_manager.get_preferences
        return "No learned preferences yet." if prefs.empty?

        lines = ["User Preferences:"]
        prefs.each do |category, items|
          lines << "\n#{category.to_s.tr("_", " ").capitalize}:"
          items.each do |key, pref|
            conf = (pref[:confidence] * 100).to_i
            lines << "  - #{key}: #{pref[:value]} (#{conf}% confident)"
          end
        end
        lines.join("\n")
      end

      def learn_preference(args)
        category = args[:preference_category]
        key = args[:preference_key]
        value = args[:preference_value]

        return error("Category, key, and value required") unless category && key && value

        para_manager.learn_preference(
          category: category.to_sym,
          key: key.to_sym,
          value: value,
          source: "conversation"
        )

        success("Learned preference: #{key} = #{value}")
      end
    end
  end
end
