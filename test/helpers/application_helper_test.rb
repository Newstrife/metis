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
end
