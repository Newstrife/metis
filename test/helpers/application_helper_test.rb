require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "renders blank input as an empty string" do
    assert_equal "", markdown(nil)
    assert_equal "", markdown("")
  end

  test "renders inline emphasis and code" do
    html = markdown("**bold** and `code`")
    assert_includes html, "<strong>bold</strong>"
    assert_includes html, "<code>code</code>"
  end

  test "renders GitHub-flavored tables" do
    html = markdown("| A | B |\n|---|---|\n| 1 | 2 |")
    assert_includes html, "<table>"
    assert_includes html, "<th>A</th>"
    assert_includes html, "<td>1</td>"
  end

  test "escapes raw HTML in the source" do
    html = markdown("<script>alert(1)</script>")
    assert_not_includes html, "<script>"
  end

  test "neutralizes javascript: links" do
    html = markdown("[click](javascript:alert(1))")
    assert_not_includes html, "javascript:"
  end

  test "opens links in a new tab" do
    html = markdown("[example](https://example.com)")
    assert_includes html, 'target="_blank"'
    assert_includes html, 'rel="noopener"'
  end

  test "returns an html-safe string" do
    assert_predicate markdown("hello"), :html_safe?
  end

  test "format_tokens abbreviates counts of a thousand or more" do
    assert_equal "940", format_tokens(940)
    assert_equal "1.5k", format_tokens(1530)
    assert_equal "272k", format_tokens(272000)
  end

  test "token_summary is blank when no tokens were recorded" do
    assert_equal "", token_summary(Message.new)
  end

  test "token_summary lists the recorded token counts" do
    summary = token_summary(Message.new(input_tokens: 1200, output_tokens: 340, cache_read_tokens: 0))
    assert_includes summary, "1.2k in"
    assert_includes summary, "340 out"
    assert_not_includes summary, "cached"
  end

  test "format_duration shows seconds under a minute and m/s above" do
    assert_equal "2.3s", format_duration(2.34)
    assert_equal "9.0s", format_duration(9.0)
    assert_equal "1m 05s", format_duration(65.7)
  end

  test "message_meta is blank with no duration or tokens" do
    assert_equal "", message_meta(Message.new)
  end

  test "message_meta joins the turn duration and token counts" do
    now = Time.current
    message = Message.new(started_at: now, finished_at: now + 3.seconds, input_tokens: 1200)
    meta = message_meta(message)
    assert_includes meta, "3.0s"
    assert_includes meta, "1.2k in"
    assert_includes meta, " · "
  end
end
