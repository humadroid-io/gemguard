ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods

    parallelize(workers: :number_of_processors)

    # Clean database between tests
    setup do
      GemPackage.delete_all
      GemVersion.delete_all
      QuarantineRule.delete_all
      QuarantinedVersion.delete_all
      AuditLog.delete_all
      Setting.delete_all
    end
  end
end

class ActionDispatch::IntegrationTest
  include FactoryBot::Syntax::Methods
end
