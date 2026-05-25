require "test_helper"

class Agent::TitleGeneratorTest < ActiveSupport::TestCase
  test "returns nil when message content is blank" do
    assert_nil Agent::TitleGenerator.call("")
    assert_nil Agent::TitleGenerator.call(nil)
  end

  test "returns nil when no API key is configured for the deployment provider" do
    with_stub(Rails.application.config.x.agent, :api_keys, -> { {} }) do
      assert_nil Agent::TitleGenerator.call("hello world")
    end
  end

  test "returns nil and logs a warning when the HTTP call raises" do
    with_stub(Rails.application.config.x.agent, :api_keys, -> { { "anthropic" => "test-key" } }) do
      with_stub(Rails.application.config.x.agent, :provider, -> { "anthropic" }) do
        generator = Agent::TitleGenerator.new
        generator.define_singleton_method(:post) { |*, **| raise "connection refused" }
        assert_nil generator.call("What is Ruby?")
      end
    end
  end

  test "parses a successful Anthropic response" do
    fake_response = {
      "content" => [ { "type" => "text", "text" => "  What Is Ruby  " } ]
    }
    with_stub(Rails.application.config.x.agent, :api_keys, -> { { "anthropic" => "test-key" } }) do
      with_stub(Rails.application.config.x.agent, :provider, -> { "anthropic" }) do
        generator = Agent::TitleGenerator.new
        generator.define_singleton_method(:post) { |*, **| fake_response }
        assert_equal "What Is Ruby", generator.call("What is Ruby?")
      end
    end
  end

  test "parses a successful OpenAI response" do
    fake_response = {
      "choices" => [ { "message" => { "content" => "  Ruby Basics  " } } ]
    }
    with_stub(Rails.application.config.x.agent, :api_keys, -> { { "openai" => "test-key" } }) do
      with_stub(Rails.application.config.x.agent, :provider, -> { "openai" }) do
        generator = Agent::TitleGenerator.new
        generator.define_singleton_method(:post) { |*, **| fake_response }
        assert_equal "Ruby Basics", generator.call("Tell me about Ruby")
      end
    end
  end

  test "parses a successful Google response" do
    fake_response = {
      "candidates" => [
        { "content" => { "parts" => [ { "text" => "  Gemini Overview  " } ] } }
      ]
    }
    with_stub(Rails.application.config.x.agent, :api_keys, -> { { "google" => "test-key" } }) do
      with_stub(Rails.application.config.x.agent, :provider, -> { "google" }) do
        generator = Agent::TitleGenerator.new
        generator.define_singleton_method(:post) { |*, **| fake_response }
        assert_equal "Gemini Overview", generator.call("Tell me about Gemini")
      end
    end
  end
end
