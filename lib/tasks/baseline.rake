# frozen_string_literal: true

namespace :baseline do
  desc "Generate a baseline file from current RubyGems specs"
  task generate: :environment do
    output_path = ENV.fetch("OUTPUT", Rails.root.join("tmp", "baseline.csv.gz").to_s)

    puts "Generating baseline to #{output_path}..."
    count = BaselineService.generate_baseline(output_path)
    puts "Done! Generated baseline with #{count} gems."
  end

  desc "Import baseline from URL (uses BASELINE_URL env var or setting)"
  task import: :environment do
    if Setting.baseline_imported?
      puts "Baseline already imported at #{Setting.baseline_imported_at}"
      puts "Source: #{Setting.get(:baseline_source) || 'csv'}"
      puts "To reimport, run: rake baseline:reimport"
      exit 0
    end

    url = ENV.fetch("BASELINE_URL", Setting.baseline_url)

    puts "Importing baseline from #{url}..."
    count = BaselineService.import_from_url(url)
    Setting.set(:baseline_imported_at, Time.current.iso8601)
    Setting.set(:baseline_source, "csv")
    puts "Done! Imported #{count} gems as approved."
  end

  desc "Import full RubyGems database dump (includes release dates)"
  task import_rubygems_dump: :environment do
    if Setting.baseline_imported?
      puts "Baseline already imported at #{Setting.baseline_imported_at}"
      puts "Source: #{Setting.get(:baseline_source) || 'csv'}"
      puts "To reimport, run: rake baseline:reimport_rubygems_dump"
      exit 0
    end

    puts "=" * 60
    puts "RubyGems Database Dump Import"
    puts "=" * 60
    puts ""
    puts "This will download and import the full RubyGems.org database dump."
    puts "The dump is ~900MB compressed and contains all gem release dates."
    puts ""
    puts "Benefits over CSV baseline:"
    puts "  - Accurate release timestamps for all gems"
    puts "  - Complete historical data"
    puts ""
    puts "Estimated time: 10-30 minutes depending on connection speed"
    puts ""
    print "Continue? [y/N] "

    response = $stdin.gets.chomp.downcase
    unless response == "y"
      puts "Aborted."
      exit 0
    end

    puts ""
    RubygemsDumpImporter.import
    puts ""
    puts "Done! Imported #{GemVersion.approved.count} gem versions with release dates."
  end

  desc "Force reimport from RubyGems dump"
  task reimport_rubygems_dump: :environment do
    puts "WARNING: This will delete all existing GemVersion records and reimport from RubyGems dump."
    print "Continue? [y/N] "
    response = $stdin.gets.chomp.downcase
    unless response == "y"
      puts "Aborted."
      exit 0
    end

    puts "Clearing existing gem versions..."
    GemVersion.delete_all
    GemPackage.where.missing(:versions).delete_all
    Setting.set(:baseline_imported_at, nil)

    RubygemsDumpImporter.import
    puts "Done! Imported #{GemVersion.approved.count} gem versions."
  end

  desc "Force reimport baseline (clears existing approved gems first)"
  task reimport: :environment do
    url = ENV.fetch("BASELINE_URL", Setting.baseline_url)

    puts "WARNING: This will delete all existing GemVersion records and reimport."
    print "Continue? [y/N] "
    response = $stdin.gets.chomp.downcase
    unless response == "y"
      puts "Aborted."
      exit 0
    end

    puts "Clearing existing gem versions..."
    GemVersion.delete_all
    GemPackage.where.missing(:versions).delete_all

    puts "Importing baseline from #{url}..."
    count = BaselineService.import_from_url(url)
    Setting.set(:baseline_imported_at, Time.current.iso8601)
    Setting.set(:baseline_source, "csv")
    puts "Done! Imported #{count} gems as approved."
  end

  desc "Import baseline from local file"
  task import_file: :environment do
    path = ENV.fetch("FILE") { raise "FILE env var required" }

    unless File.exist?(path)
      puts "File not found: #{path}"
      exit 1
    end

    puts "Importing baseline from #{path}..."
    count = BaselineService.import_from_file(path)
    Setting.set(:baseline_imported_at, Time.current.iso8601)
    Setting.set(:baseline_source, "csv")
    puts "Done! Imported #{count} gems as approved."
  end

  desc "Import baseline from RubyGems specs files (recommended)"
  task import_from_specs: :environment do
    if Setting.baseline_imported?
      puts "Baseline already imported at #{Setting.baseline_imported_at}"
      puts "Source: #{Setting.get(:baseline_source) || 'csv'}"
      puts "To reimport, run: rake baseline:reimport_from_specs"
      exit 0
    end

    puts "=" * 60
    puts "RubyGems Specs Import"
    puts "=" * 60
    puts ""
    puts "This will download and import gem data from RubyGems specs files."
    puts "The specs files are ~30MB and contain all gem names and versions."
    puts ""
    puts "Benefits:"
    puts "  - Faster than full database dump (~30MB vs ~900MB)"
    puts "  - More complete than CSV baseline"
    puts "  - Also saves raw specs for immediate use"
    puts ""
    puts "Estimated time: 2-5 minutes"
    puts ""
    print "Include prerelease versions? [y/N] "
    include_prerelease = $stdin.gets.chomp.downcase == "y"

    puts ""
    puts "Starting import..."
    count = SpecsBaselineImporter.import(include_prerelease: include_prerelease)
    puts ""
    puts "Done! Imported #{count} gem versions."
    puts "Specs files are now available for filtering."
  end

  desc "Force reimport from specs files"
  task reimport_from_specs: :environment do
    puts "WARNING: This will delete all existing GemVersion records and reimport from specs."
    print "Continue? [y/N] "
    response = $stdin.gets.chomp.downcase
    unless response == "y"
      puts "Aborted."
      exit 0
    end

    print "Include prerelease versions? [y/N] "
    include_prerelease = $stdin.gets.chomp.downcase == "y"

    puts "Clearing existing gem versions..."
    GemVersion.delete_all
    GemPackage.where.missing(:versions).delete_all
    Setting.set(:baseline_imported_at, nil)

    puts "Starting import..."
    count = SpecsBaselineImporter.import(include_prerelease: include_prerelease)
    puts "Done! Imported #{count} gem versions."
  end

  desc "Check baseline status"
  task status: :environment do
    if Setting.baseline_imported?
      source = Setting.get(:baseline_source) || "csv"
      puts "Baseline imported at: #{Setting.baseline_imported_at}"
      puts "Source: #{source}"
      puts ""
      puts "Statistics:"
      puts "  Approved versions: #{GemVersion.approved.count}"
      puts "  Blocked versions: #{GemVersion.blocked.count}"
      puts "  Quarantined versions: #{GemVersion.quarantined.count}"
      puts "  Unique packages: #{GemPackage.count}"
      puts ""
      puts "Specs availability:"
      puts "  Status: #{SpecsAvailabilityService.status}"
      puts "  #{SpecsAvailabilityService.status_message}"
    else
      puts "Baseline not yet imported."
      puts ""
      puts "Import options:"
      puts "  rake baseline:import_from_specs    - From specs files (recommended)"
      puts "  rake baseline:import               - Quick CSV baseline (minimal)"
      puts "  rake baseline:import_rubygems_dump - Full RubyGems dump (complete)"
    end
  end
end
