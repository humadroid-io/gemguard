# frozen_string_literal: true

namespace :baseline do
  desc "Import baseline from RubyGems specs files"
  task import: :environment do
    if SpecsBaselineImporter.baseline_imported?
      puts "Baseline already imported at #{Setting.get(:baseline_imported_at)}"
      puts "To reimport, run: rake baseline:reimport"
      exit 0
    end

    puts "=" * 60
    puts "GemGuard Baseline Import"
    puts "=" * 60
    puts ""
    puts "This will download specs from RubyGems.org and save them locally."
    puts "All versions in the specs are considered 'known' and approved."
    puts "Only NEW versions (published after this import) will be quarantined."
    puts ""
    puts "Estimated time: 2-5 minutes"
    puts ""
    print "Include prerelease versions? [y/N] "
    include_prerelease = $stdin.gets.chomp.downcase == "y"

    puts ""
    puts "Starting import..."
    count = SpecsBaselineImporter.import(include_prerelease: include_prerelease)
    puts ""
    puts "Done! Baseline established with #{count} gem versions."
  end

  desc "Force reimport baseline (overwrites existing specs files)"
  task reimport: :environment do
    puts "This will re-download specs from RubyGems.org."
    print "Continue? [y/N] "
    unless $stdin.gets.chomp.downcase == "y"
      puts "Aborted."
      exit 0
    end

    print "Include prerelease versions? [y/N] "
    include_prerelease = $stdin.gets.chomp.downcase == "y"

    puts ""
    puts "Starting import..."
    count = SpecsBaselineImporter.import(include_prerelease: include_prerelease)
    puts "Done! Baseline re-established with #{count} gem versions."
  end

  desc "Check baseline status"
  task status: :environment do
    puts "=" * 60
    puts "GemGuard Baseline Status"
    puts "=" * 60
    puts ""

    if SpecsBaselineImporter.baseline_imported?
      puts "Baseline imported: YES"
      puts "  Imported at: #{Setting.get(:baseline_imported_at)}"
    else
      puts "Baseline imported: NO"
      puts "  Run 'rake baseline:import' to establish baseline."
    end

    puts ""
    puts "Specs Files:"
    puts "  Status: #{SpecsAvailabilityService.status}"
    puts "  #{SpecsAvailabilityService.status_message}"

    puts ""
    puts "Storage:"
    raw_path = Rails.root.join("storage", "specs", "raw")
    filtered_path = Rails.root.join("storage", "specs")

    %w[specs.4.8.gz latest_specs.4.8.gz prerelease_specs.4.8.gz].each do |file|
      raw_file = raw_path.join(file)
      filtered_file = filtered_path.join(file)

      raw_size = File.exist?(raw_file) ? "#{(File.size(raw_file) / 1024.0 / 1024.0).round(2)} MB" : "missing"
      filtered_size = File.exist?(filtered_file) ? "#{(File.size(filtered_file) / 1024.0 / 1024.0).round(2)} MB" : "missing"

      puts "  #{file}: raw=#{raw_size}, filtered=#{filtered_size}"
    end

    puts ""
    puts "Database:"
    puts "  Packages: #{GemPackage.count} (tracked: #{GemPackage.tracked.count})"
    puts "  Versions: #{GemVersion.count}"
    puts "  Quarantine: #{QuarantinedVersion.active.count} active"
  end

  desc "Generate baseline export CSV"
  task export: :environment do
    output_path = ENV.fetch("OUTPUT", Rails.root.join("tmp", "baseline-export.csv.gz").to_s)

    puts "Generating baseline export to #{output_path}..."

    if File.exist?(Rails.root.join("storage", "specs", "raw", "specs.4.8.gz"))
      count = BaselineService.generate_baseline_from_local(output_path)
      puts "Done! Exported #{count} gem versions from local specs."
    else
      puts "No local specs found. Fetching from RubyGems.org..."
      count = BaselineService.generate_baseline(output_path)
      puts "Done! Exported #{count} gem versions."
    end
  end
end
