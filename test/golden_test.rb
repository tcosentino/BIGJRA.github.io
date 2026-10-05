require_relative 'test_helper'

# The HTML markdown output must stay byte-identical to the baseline,
# apart from the generation timestamp line.
class GoldenTest < Minitest::Test
  TIMESTAMP_RE = /^<h5> Walkthrough last updated .* GMT<\/h5>$/

  def normalize(text)
    text.sub(TIMESTAMP_RE, '<h5> Walkthrough last updated TIMESTAMP GMT</h5>')
  end

  def test_monolithic_markdown_matches_baseline
    expected = File.binread(File.join(TestPaths::BASELINE_DIR, 'reborn.md'))
    actual = File.binread(File.join(GeneratedOutput.dir, 'reborn.md'))
    assert normalize(expected) == normalize(actual), 'reborn.md differs from baseline'
  end

  def test_chapter_files_match_baseline
    baseline_chapters = File.join(TestPaths::BASELINE_DIR, 'reborn-chapters')
    generated_chapters = File.join(GeneratedOutput.dir, 'reborn-chapters')
    expected_files = Dir.children(baseline_chapters).sort
    assert_equal expected_files, Dir.children(generated_chapters).sort
    expected_files.each do |name|
      expected = File.binread(File.join(baseline_chapters, name))
      actual = File.binread(File.join(generated_chapters, name))
      assert expected == actual, "#{name} differs from baseline"
    end
  end
end
