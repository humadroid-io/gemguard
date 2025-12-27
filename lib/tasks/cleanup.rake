# frozen_string_literal: true

namespace :gemguard do
  desc "Show database statistics"
  task stats: :environment do
    puts "=" * 60
    puts "GemGuard Statistics"
    puts "=" * 60
    puts ""

    puts "Packages:"
    puts "  Total: #{GemPackage.count}"
    puts "  Tracked: #{GemPackage.tracked.count}"

    puts ""
    puts "Versions:"
    puts "  Total: #{GemVersion.count}"
    puts "  Approved: #{GemVersion.approved.count}"
    puts "  Quarantined: #{GemVersion.quarantined.count}"
    puts "  Blocked: #{GemVersion.blocked.count}"
    puts "  Cached: #{GemVersion.where.not(cached_at: nil).count}"

    puts ""
    puts "Quarantine (lightweight table):"
    puts "  Active: #{QuarantinedVersion.active.count}"
    puts "  Expired: #{QuarantinedVersion.expired.count}"

    puts ""
    puts "Audit Logs:"
    puts "  Total: #{AuditLog.count}"
    puts "  Last 24h: #{AuditLog.where("created_at > ?", 24.hours.ago).count}"

    puts ""
    puts "Storage:"
    specs_size = dir_size(Rails.root.join("storage", "specs"))
    gems_size = dir_size(Rails.root.join("storage", "gems"))
    puts "  Specs: #{format_bytes(specs_size)}"
    puts "  Gems: #{format_bytes(gems_size)}"
    puts "  Total: #{format_bytes(specs_size + gems_size)}"
  end

  desc "Reset database for fresh start"
  task reset: :environment do
    puts "This will delete ALL data and specs files."
    print "Type 'RESET' to confirm: "
    unless $stdin.gets.chomp == "RESET"
      puts "Aborted."
      exit 0
    end

    puts ""
    puts "Deleting database records..."
    GemVersion.delete_all
    GemPackage.delete_all
    QuarantinedVersion.delete_all
    AuditLog.delete_all
    puts "  Done."

    puts ""
    puts "Deleting specs files..."
    FileUtils.rm_rf(Rails.root.join("storage", "specs"))
    puts "  Done."

    puts ""
    puts "Clearing settings..."
    Setting.set(:baseline_imported_at, nil)
    Setting.set(:baseline_source, nil)
    puts "  Done."

    puts ""
    puts "Reset complete! Run 'rake baseline:import' to start fresh."
  end

  private

  def dir_size(path)
    return 0 unless Dir.exist?(path)
    Dir.glob("#{path}/**/*").select { |f| File.file?(f) }.sum { |f| File.size(f) }
  end

  def format_bytes(bytes)
    return "0 B" if bytes == 0
    units = ["B", "KB", "MB", "GB"]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [exp, units.length - 1].min
    "%.2f %s" % [bytes.to_f / 1024**exp, units[exp]]
  end
end
