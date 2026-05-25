# Testing Patterns (Minitest + Mocha)

## Test Structure

```ruby
require "test_helper"

class MyServiceTest < ActiveSupport::TestCase
  def setup
    @project = projects(:acme_api)  # Fixture reference
  end

  test "descriptive name of what is tested" do
    assert_equal "expected", actual
  end
end
```

## Fixtures

All test data lives in `test/fixtures/*.yml`. Reference with `model_name(:fixture_key)`.

```yaml
# test/fixtures/projects.yml
acme_api:
  owner: acme
  name: api
  default_branch: main
  auto_review: true
```

## Credential Stubbing

`test_helper.rb` stubs credentials globally:

```ruby
setup do
  Rails.application.credentials.stubs(:themis).returns(OpenStruct.new)

  # GitHub App is stubbed "configured" so the :github channel behaves as
  # enabled without requiring a real RSA private key in test credentials.
  GithubApp::Config.stubs(:configured?).returns(true)
  GithubApp::Config.stubs(:app_slug).returns("themis-ai-agent")
  GithubApp::TokenService.stubs(:installation_token).returns("ghs_test_installation_token")
end
```

To test with Linear credentials, re-stub in your test:

```ruby
test "with linear credentials" do
  creds = OpenStruct.new(linear_api_key: "test-linear-key")
  Rails.application.credentials.stubs(:themis).returns(creds)
  # ...
end
```

## Mocha Mocking Patterns

### Simple mock with expectations

```ruby
git_mock = mock("GitService")
git_mock.expects(:push).with("branch-name").once
git_mock.expects(:staged_changes?).returns(true)
```

### Sequences for ordered calls

```ruby
seq = sequence("ordered_calls")
mock.expects(:first_call).in_sequence(seq)
mock.expects(:second_call).in_sequence(seq)
```

### Stubbing class methods

```ruby
GithubAPIService.any_instance.stubs(:get_pull_request).returns({ title: "PR" })
```

## Job Testing

Use `include ActiveJob::TestHelper` for job assertions:

```ruby
class MyJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues downstream job" do
    assert_enqueued_with(job: DownstreamJob) do
      MyJob.perform_now(args)
    end
  end
end
```

## Common Assertions

```ruby
assert obj.valid?
assert_not obj.valid?
assert_equal expected, actual
assert_nil value
assert_includes collection, item
assert_not_includes collection, item
assert_raises(ErrorClass) { dangerous_call }
assert_difference("Model.count", 1) { create_action }
assert_no_difference("Model.count") { failed_action }
```

## Running Tests

```bash
bin/rails test                           # All tests
bin/rails test test/models/              # Directory
bin/rails test test/models/project_test.rb:42  # Single test by line
```
