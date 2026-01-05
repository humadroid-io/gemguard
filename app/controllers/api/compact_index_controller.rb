module Api
  class CompactIndexController < BaseController
    # GET /versions
    # Returns the versions file with quarantined gems filtered out
    def versions
      path = compact_index_path.join("versions")
      stale = ensure_versions_file(path)

      return head :not_found unless File.exist?(path)

      serve_compact_index_file(path, stale: stale)
    end

    # GET /info/:name
    # Returns dependency info for a specific gem with quarantined versions filtered
    def info
      gem_name = params[:name]
      return head :bad_request if gem_name.blank?

      path, stale = ensure_info_file(gem_name)
      return head :not_found unless path && File.exist?(path)

      serve_compact_index_file(path, stale: stale)
    end

    # GET /names
    # Returns list of all gem names (optional, some clients use this)
    def names
      path = compact_index_path.join("names")
      stale = false

      unless File.exist?(path)
        stale = !sync_names_file
      end

      return head :not_found unless File.exist?(path)

      serve_compact_index_file(path, stale: stale)
    end

    private

    def compact_index_path
      storage_path.join("compact_index")
    end

    def serve_compact_index_file(path, stale: false)
      set_cache_headers(path)

      if stale
        response.headers["X-GemGuard-Stale"] = "true"
        Rails.logger.info("CompactIndexController: Serving stale #{File.basename(path)} (upstream unavailable)")
      end

      send_file path, type: "text/plain", disposition: "inline"
    end

    # Returns true if serving stale data (sync failed but file exists)
    def ensure_versions_file(path)
      # File is fresh - no sync needed
      return false if File.exist?(path) && !file_stale?(path)

      # Queue async refresh
      SyncCompactIndexJob.perform_later(type: :versions)

      if File.exist?(path)
        # File exists but is stale
        file_stale?(path)
      else
        # No file - sync synchronously, return stale=true if sync fails
        !sync_versions_file
      end
    end

    # Returns [path, stale] where stale is true if sync failed but file exists
    def ensure_info_file(gem_name)
      info_path = compact_index_path.join("info", gem_name)
      stale = false

      if !File.exist?(info_path) || file_stale?(info_path)
        success = sync_info_file(gem_name)
        stale = !success && File.exist?(info_path)
      end

      path = File.exist?(info_path) ? info_path : nil
      [path, stale]
    end

    def sync_versions_file
      CompactIndexService.sync_versions
    end

    def sync_info_file(gem_name)
      CompactIndexService.sync_info(gem_name)
    end

    def sync_names_file
      CompactIndexService.sync_names
    end

    def file_stale?(path)
      File.mtime(path) < Setting.sync_interval_minutes.minutes.ago
    end

    def set_cache_headers(path)
      response.headers["ETag"] = Digest::MD5.file(path).hexdigest
      response.headers["Last-Modified"] = File.mtime(path).httpdate
      response.headers["Cache-Control"] = "public, max-age=#{Setting.sync_interval_minutes * 60}"
    end
  end
end
