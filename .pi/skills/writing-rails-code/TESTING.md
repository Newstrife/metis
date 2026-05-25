# Testing Patterns (Minitest)

Metis uses **plain Minitest** — no RSpec, no Mocha. Tests live under
`test/` mirroring `app/`. Run with `bin/rails test`.

## Test structure

```ruby
require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "conv@example.com", password: "password123")
    @conversation = @user.conversations.create!
  end

  test "a conversation defaults its team to the creator's personal team" do
    assert_equal @user.personal_team, @conversation.team
  end
end
```

## No fixtures — build records directly

`test/fixtures/*.yml` is intentionally empty (`# Fixtures cleared —
tests build records directly.`). Construct what each test needs in
its `setup` block.

This avoids shared mutable state across tests and stops fixture drift
from masking failures. Cost: a few extra `.create!` calls per test —
worth it.

## Stubbing — `with_stub`

`test_helper.rb` defines `with_stub(target, method_name, replacement)`
because Minitest 6 dropped `Object#stub`. Use it to swap an external
boundary for the duration of one block:

```ruby
test "destroying a conversation kills its paused e2b sandbox" do
  killed_with = nil
  with_stub(Agent::Runtime::E2b, :kill_sandbox, ->(id) { killed_with = id }) do
    @conversation.update!(e2b_sandbox_id: "sbx_abc")
    @conversation.destroy
  end
  assert_equal "sbx_abc", killed_with
end
```

For something `with_stub` doesn't cover (swapping a lookup method on
a different shape, mocking a per-instance call), reach for
`define_singleton_method` directly with an `ensure` to restore — see
`ChatJobTest#with_adapter` for the pattern.

## Active Record encryption

`Message#content` and `#reasoning` are encrypted. The three encryption
keys are set in `config/environments/test.rb` to literal test strings
— individual tests don't stub credentials, the env loads the keys.

## OmniAuth tests

`test_helper.rb` enables `OmniAuth.config.test_mode = true` globally.
Per-test mocks:

```ruby
test "github callback signs the user in" do
  OmniAuth.config.add_mock(
    :github,
    uid: "42",
    info:  { email: "u@example.com" },
    extra: { raw_info: { email_verified: true } }
  )
  post user_github_omniauth_authorize_path
  follow_redirect!
  # ...
ensure
  OmniAuth.config.mock_auth[:github] = nil
end
```

## Job tests

Include `ActiveJob::TestHelper` for enqueue assertions:

```ruby
class MessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "creating a message enqueues a ChatJob" do
    assert_enqueued_with(job: ChatJob) do
      post conversation_messages_path(@conversation), params: { content: "hi" }
    end
  end
end
```

`ChatJobTest` itself runs jobs synchronously (`ChatJob.perform_now`)
behind a `FakeAdapter` that replays a canned `Agent::UiEvent`
stream. New agent-streaming tests should follow that shape rather than
mocking individual `pi-agent-rb` calls — the FakeAdapter exercises the
job's real branching logic.

## Common assertions

```ruby
assert obj.valid?
assert_not obj.valid?
assert_equal expected, actual
assert_nil value
assert_includes collection, item
assert_raises(ErrorClass) { dangerous_call }
assert_difference("Conversation.count", 1) { create_action }
assert_no_difference("Message.count") { failed_action }
assert_enqueued_with(job: ChatJob) { trigger }
```

## Parallelization — single-process until 500 tests

`test_helper.rb` sets `parallelize(workers: :number_of_processors,
threshold: 500)`. Below the threshold, the suite runs single-process
on purpose: parallel workers share the filesystem but not DB id
sequences, which races per-record scratch paths
(`Agent::Workspace`). Don't lower the threshold "to speed things up"
— it breaks.

## Running tests

```bash
bin/rails test                                    # full suite
bin/rails test test/models                        # one directory
bin/rails test test/jobs/chat_job_test.rb         # one file
bin/rails test test/jobs/chat_job_test.rb:42      # one test by line
```

Run `bin/rubocop` and the relevant tests before committing.
