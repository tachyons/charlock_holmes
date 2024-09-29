# frozen_string_literal: true

require "charlock_holmes"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  RSpec.configure do |config|
    # Use the GitHub Annotations formatter for CI
    if ENV["GITHUB_ACTIONS"] == "true"
      require "rspec/github"
      config.add_formatter RSpec::Github::Formatter
    end
  end
end
