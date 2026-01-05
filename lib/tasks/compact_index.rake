namespace :compact_index do
  desc "Sync Compact Index files from upstream RubyGems"
  task sync: :environment do
    puts "Syncing Compact Index from upstream..."

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

    puts "Compact Index sync complete"
  end

  desc "Sync Compact Index if not already present (for first deploy)"
  task sync_if_missing: :environment do
    versions_path = CompactIndexService.storage_path.join("versions")

    if File.exist?(versions_path)
      puts "Compact Index already exists, skipping sync"
    else
      Rake::Task["compact_index:sync"].invoke
    end
  end
end
