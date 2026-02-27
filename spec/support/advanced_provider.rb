# frozen_string_literal: true

# Test subclass with custom supported features
class AdvancedProvider < Pocketrb::Providers::Base
  def name
    :advanced
  end

  def default_model
    "advanced-model"
  end

  def available_models
    ["advanced-model"]
  end

  def chat(messages:, **_kwargs)
    Pocketrb::Providers::LLMResponse.new(content: "Response", model: default_model)
  end

  protected

  def supported_features
    %i[tools streaming vision thinking]
  end

  def format_message(message)
    message
  end

  def parse_response(response)
    response
  end
end
