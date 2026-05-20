require "test_helper"

class Agent::Runtime::E2bTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "e2b@example.com", password: "password123")
    @conversation = @user.conversations.create!(backend: :pi)
    @runtime = Agent::Runtime::E2b.new(conversation: @conversation)
  end

  class FakeCommands
    def run(*_args, **_kwargs) = nil
  end

  # Minimal fake E2B sandbox.
  class FakeSandbox
    attr_reader :sandbox_id

    def initialize(sandbox_id)
      @sandbox_id = sandbox_id
      @paused = false
    end

    def commands = FakeCommands.new
    def resume(**) = self
    def pause = (@paused = true)
    def paused? = @paused
  end

  def fake_session
    session = Object.new
    def session.close = nil
    session
  end

  # Swap PiAgent.session and only the requested E2B::Sandbox class methods
  # for the block (:skip leaves a method untouched).
  def with_e2b(create: :skip, connect: :skip, session:)
    originals = {}
    if create != :skip
      originals[:create] = E2B::Sandbox.method(:create)
      E2B::Sandbox.define_singleton_method(:create) { |**| create }
    end
    if connect != :skip
      originals[:connect] = E2B::Sandbox.method(:connect)
      E2B::Sandbox.define_singleton_method(:connect) { |*, **| connect }
    end
    session_original = PiAgent.method(:session)
    PiAgent.define_singleton_method(:session) { |*, **| session }
    yield
  ensure
    originals.each { |name, method| E2B::Sandbox.define_singleton_method(name, method) }
    PiAgent.define_singleton_method(:session, session_original)
  end

  test "session_dir is the in-sandbox session path" do
    assert_equal Agent::Runtime::E2b::SESSION_DIR, @runtime.session_dir.to_s
  end

  test "creates a sandbox on the first turn and records its id" do
    sandbox = FakeSandbox.new("sbx-new")

    with_e2b(create: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert_equal "sbx-new", @conversation.reload.runtime_state["e2b_sandbox_id"]
    assert sandbox.paused?
  end

  test "resumes the recorded sandbox on a later turn" do
    @conversation.update!(runtime_state: { "e2b_sandbox_id" => "sbx-existing" })
    sandbox = FakeSandbox.new("sbx-existing")

    with_e2b(connect: sandbox, session: fake_session) do
      @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
    end

    assert sandbox.paused?
  end

  test "falls back to a fresh sandbox when resume fails" do
    @conversation.update!(runtime_state: { "e2b_sandbox_id" => "sbx-expired" })
    fresh = FakeSandbox.new("sbx-fresh")

    connect_original = E2B::Sandbox.method(:connect)
    E2B::Sandbox.define_singleton_method(:connect) { |*, **| raise E2B::NotFoundError, "gone" }
    begin
      with_e2b(create: fresh, session: fake_session) do
        @runtime.run(pi_args: [ "--mode", "rpc" ]) { |_s| nil }
      end
    ensure
      E2B::Sandbox.define_singleton_method(:connect, connect_original)
    end

    assert_equal "sbx-fresh", @conversation.reload.runtime_state["e2b_sandbox_id"]
  end
end
