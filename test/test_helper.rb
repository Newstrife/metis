ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Tests never reach GitHub — every omniauth callback uses a mock_auth
# set up by the test (or returns OmniAuth's default invalid_credentials).
OmniAuth.config.test_mode = true

module ActiveSupport
  class TestCase
    # Single-process until the suite is large enough to benefit. Parallel
    # workers share the filesystem but not DB id sequences, which races
    # tests that touch per-record scratch paths (Agent::Workspace).
    parallelize(workers: :number_of_processors, threshold: 500)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Replace a singleton method on `target` (typically a class) with `replacement`
    # for the duration of the block, then restore. Minitest 6 dropped Object#stub,
    # so tests that fake out an external boundary use this instead.
    def with_stub(target, method_name, replacement)
      original = target.method(method_name)
      target.singleton_class.send(:define_method, method_name, replacement)
      yield
    ensure
      target.singleton_class.send(:define_method, method_name, original)
    end
  end
end
