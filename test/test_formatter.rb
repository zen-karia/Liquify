require 'minitest/autorun'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'liquify'

class TestFormatter < Minitest::Test
  def test_renders_header
    output = Liquify::Formatter.render('test.liquid', [], nil)
    assert_includes output, 'LIQUIFY'
    assert_includes output, 'N+1 Analyzer'
  end

  def test_clean_file_shows_success_message
    output = Liquify::Formatter.render('test.liquid', [], nil)
    assert_includes output, 'No N+1 issues found'
  end

  def test_issues_shown_with_line_numbers
    issues = [
      { 'line_number' => 5, 'issue' => 'N+1 query detected', 'code_snippet' => '{% for v in product.variants %}' }
    ]
    output = Liquify::Formatter.render('test.liquid', issues, nil)
    assert_includes output, 'ISSUE #1'
    assert_includes output, 'Line 5'
    assert_includes output, 'product.variants'
  end

  def test_optimized_code_shown
    issues = [
      {
        'line_number'    => 5,
        'issue'          => 'N+1 query detected',
        'code_snippet'   => '{% for v in product.variants %}',
        'optimized_code' => '{% assign variants = product.variants %}'
      }
    ]
    output = Liquify::Formatter.render('test.liquid', issues, :openai)
    assert_includes output, 'Optimized Code'
    assert_includes output, '{% assign variants = product.variants %}'
  end

  def test_no_key_shows_hint
    issues = [
      { 'line_number' => 5, 'issue' => 'N+1 query detected', 'code_snippet' => '{% for v in product.variants %}' }
    ]
    output = Liquify::Formatter.render('test.liquid', issues, nil)
    assert_includes output, 'Set an API key'
  end

  def test_auto_fixed_shows_fixed_message
    issues = [
      { 'line_number' => 5, 'issue' => 'N+1 query detected', 'code_snippet' => '{% for v in product.variants %}', 'auto_fixed' => true }
    ]
    output = Liquify::Formatter.render('test.liquid', issues, :openai, backup_path: 'test.liquid.bak')
    assert_includes output, 'Auto-fixed'
    assert_includes output, 'test.liquid.bak'
  end

  def test_issue_count_shown
    issues = [
      { 'line_number' => 5, 'issue' => 'N+1 query detected', 'code_snippet' => 'a' },
      { 'line_number' => 9, 'issue' => 'N+1 query detected', 'code_snippet' => 'b' }
    ]
    output = Liquify::Formatter.render('test.liquid', issues, nil)
    assert_includes output, '2 issue(s)'
  end
end
