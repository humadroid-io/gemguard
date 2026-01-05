namespace :deploy do
  desc "Bootstrap GemGuard on first deploy (syncs all index files)"
  task bootstrap: :environment do
    puts "Bootstrapping GemGuard..."

    # Check if already bootstrapped
    if bootstrapped?
      puts "Already bootstrapped, skipping."
      next
    end

    # Sync Compact Index (modern Bundler)
    puts ""
    puts "Syncing Compact Index..."
    sync_compact_index

    # Sync legacy specs (fallback for older Bundler)
    puts ""
    puts "Syncing legacy specs..."
    sync_legacy_specs

    # Mark baseline as imported (this is what SyncSpecsJob checks)
    # All versions in the current specs are considered "known/approved"
    # Only NEW versions (published after this) will be quarantined
    Setting.set(:baseline_imported_at, Time.current.iso8601)
    Setting.set(:baseline_source, "specs")
    Setting.set(:bootstrapped_at, Time.current.iso8601)

    puts ""
    puts "Bootstrap complete!"
    puts "Baseline established - existing gem versions are approved."
    puts "New versions published after this point will be quarantined."
  end

  desc "Force re-bootstrap (re-syncs all index files)"
  task rebootstrap: :environment do
    puts "Re-bootstrapping GemGuard..."

    puts ""
    puts "Syncing Compact Index..."
    sync_compact_index

    puts ""
    puts "Syncing legacy specs..."
    sync_legacy_specs

    Setting.set(:baseline_imported_at, Time.current.iso8601)
    Setting.set(:baseline_source, "specs")
    Setting.set(:bootstrapped_at, Time.current.iso8601)

    puts ""
    puts "Re-bootstrap complete!"
    puts "Baseline re-established."
  end

  def bootstrapped?
    compact_index_exists? && specs_exist?
  end

  def compact_index_exists?
    versions_path = Rails.root.join("storage", "compact_index", "versions")
    File.exist?(versions_path)
  end

  def specs_exist?
    specs_path = Rails.root.join("storage", "specs", "specs.4.8.gz")
    File.exist?(specs_path)
  end

  def sync_compact_index
    print "  Syncing versions file... "
    if CompactIndexService.sync_versions
      puts "done"
    else
      puts "failed"
    end

    print "  Syncing names file... "
    if CompactIndexService.sync_names
      puts "done"
    else
      puts "failed"
    end
  end

  def sync_legacy_specs
    %i[all latest prerelease].each do |type|
      print "  Syncing #{type} specs... "
      if sync_specs_file(type)
        puts "done"
      else
        puts "failed"
      end
    end
  end

  def sync_specs_file(type)
    filenames = {
      all: "specs.4.8.gz",
      latest: "latest_specs.4.8.gz",
      prerelease: "prerelease_specs.4.8.gz"
    }

    filename = filenames[type]
    data = RubygemsClient.fetch_specs(type)
    return false unless data

    # Save to both raw and filtered paths (no filtering on fresh deploy)
    raw_path = Rails.root.join("storage", "specs", "raw")
    filtered_path = Rails.root.join("storage", "specs")

    FileUtils.mkdir_p(raw_path)
    FileUtils.mkdir_p(filtered_path)

    File.binwrite(raw_path.join(filename), data)
    File.binwrite(filtered_path.join(filename), data)

    true
  rescue => e
    Rails.logger.error("Failed to sync #{type} specs: #{e.message}")
    false
  end
end
