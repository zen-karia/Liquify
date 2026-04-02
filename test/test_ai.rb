require 'minitest/autorun'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'liquify'

class TestAI < Minitest::Test
  def setup
    # Clear all keys before each test
    @original_anthropic = ENV.delete('ANTHROPIC_API_KEY')
    @original_openai    = ENV.delete('OPENAI_API_KEY')
    @original_gemini    = ENV.delete('GEMINI_API_KEY')
  end

  def teardown
    # Restore original keys
    ENV['ANTHROPIC_API_KEY'] = @original_anthropic if @original_anthropic
    ENV['OPENAI_API_KEY']    = @original_openai    if @original_openai
    ENV['GEMINI_API_KEY']    = @original_gemini    if @original_gemini
  end

  def test_no_provider_when_no_keys
    assert_nil Liquify::AI.detect_provider
  end

  def test_anthropic_takes_priority
    ENV['ANTHROPIC_API_KEY'] = 'test-key'
    ENV['OPENAI_API_KEY']    = 'test-key'
    ENV['GEMINI_API_KEY']    = 'test-key'
    assert_equal :anthropic, Liquify::AI.detect_provider
  end

  def test_openai_second_priority
    ENV['OPENAI_API_KEY'] = 'test-key'
    ENV['GEMINI_API_KEY'] = 'test-key'
    assert_equal :openai, Liquify::AI.detect_provider
  end

  def test_gemini_third_priority
    ENV['GEMINI_API_KEY'] = 'test-key'
    assert_equal :gemini, Liquify::AI.detect_provider
  end

  def test_sanitize_removes_formatting_markers
    raw = "⚠  N+1 detected\n↳  some code\n{% assign x = y %}\n✦  fixed"
    result = Liquify::AI.sanitize(raw)
    refute_match(/[⚠↳✦]/, result, "Sanitize should strip formatting markers")
    assert_includes result, '{% assign x = y %}'
  end

  def test_sanitize_handles_nil
    assert_nil Liquify::AI.sanitize(nil)
  end

  def test_sanitize_strips_whitespace
    result = Liquify::AI.sanitize("  {% assign x = y %}  ")
    assert_equal '{% assign x = y %}', result
  end
end
