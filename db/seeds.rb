# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Bootstrap specs baseline if not already imported
# This is idempotent - it only runs if the baseline hasn't been imported yet.
#
# The baseline import downloads specs from RubyGems.org and establishes the set of
# "known" gem versions. All versions in the baseline are considered approved.
# Only NEW versions detected after baseline import will be quarantined.

unless Setting.baseline_imported?
  puts "GemGuard: Importing specs baseline from RubyGems.org..."
  puts "  This may take a few minutes depending on your connection."

  count = SpecsBaselineImporter.import(include_prerelease: true)

  puts "GemGuard: Baseline import complete - #{count} versions imported"
  puts "  You can now use GemGuard as your gem source."
end
