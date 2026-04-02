require 'minitest/autorun'
require 'json'
require 'open3'

# Tests for the C++ binary directly
class TestAnalyzer < Minitest::Test
  _base  = File.expand_path('../../cpp_engine/liquid_analyzer', __FILE__)
  BINARY = File.exist?(_base + '.exe') ? _base + '.exe' : _base
  FIXTURES = File.expand_path('../fixtures', __FILE__)

  def run_analyzer(fixture)
    stdout, _stderr, _status = Open3.capture3(BINARY, File.join(FIXTURES, fixture))
    JSON.parse(stdout)
  end

  def test_clean_file_returns_empty_array
    issues = run_analyzer('clean.liquid')
    assert_empty issues, "Expected no issues in clean.liquid"
  end

  def test_nested_loop_flagged
    issues = run_analyzer('nested_loop.liquid')
    refute_empty issues, "Expected N+1 issues in nested_loop.liquid"

    snippets = issues.map { |i| i['code_snippet'] }
    assert snippets.any? { |s| s.include?('product.variants') },
           "Expected product.variants loop to be flagged"
  end

  def test_lazy_prop_at_depth_one_flagged
    issues = run_analyzer('lazy_prop.liquid')
    refute_empty issues, "Expected N+1 issues in lazy_prop.liquid"

    snippets = issues.map { |i| i['code_snippet'] }
    assert snippets.any? { |s| s.include?('product.metafields') },
           "Expected product.metafields to be flagged"
    assert snippets.any? { |s| s.include?('product.images') },
           "Expected product.images to be flagged"
  end

  def test_eager_prop_not_flagged
    issues = run_analyzer('lazy_prop.liquid')
    snippets = issues.map { |i| i['code_snippet'] }
    refute snippets.any? { |s| s.include?('product.title') },
           "product.title should NOT be flagged (eagerly loaded)"
  end

  def test_multi_level_collection_path
    issues = run_analyzer('multi_level.liquid')
    refute_empty issues, "Expected N+1 issues in multi_level.liquid"

    snippets = issues.map { |i| i['code_snippet'] }
    assert snippets.any? { |s| s.include?('product.metafields') },
           "Expected product.metafields loop to be flagged"
  end

  def test_issue_format
    issues = run_analyzer('nested_loop.liquid')
    issue  = issues.first

    assert issue.key?('line_number'),   "Issue must have line_number"
    assert issue.key?('issue'),         "Issue must have issue"
    assert issue.key?('code_snippet'),  "Issue must have code_snippet"
    assert_kind_of Integer, issue['line_number']
    assert_equal 'N+1 query detected', issue['issue']
  end
end
