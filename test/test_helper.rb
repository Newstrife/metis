ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Single-process until the suite is large enough to benefit. Parallel
    # workers share the filesystem but not DB id sequences, which races
    # tests that touch per-record scratch paths (Agent::Workspace).
    parallelize(workers: :number_of_processors, threshold: 500)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
