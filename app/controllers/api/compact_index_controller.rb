module Api
  class CompactIndexController < BaseController
    # GET /versions
    # Returns the resolver-visible compact index version list.
    # This file is filtered so bundler never sees actively quarantined
    # or blocked versions during dependency resolution.
    def versions
      path = compact_index_path.join("versions")
      stale = ensure_versions_file(path)

      return head :not_found unless File.exist?(path)

      log_compact_index_request(endpoint: "versions")
      serve_compact_index_file(path, stale: stale)
    end

    # GET /info/:name
    # Returns per-gem compact index info filtered with the same exclusion rules
    # as /versions so the checksum and dependency payload stay consistent.
    def info
      gem_name = params[:name]
      return head :bad_request if gem_name.blank?

      path, stale = ensure_info_file(gem_name)
      return head :not_found unless path && File.exist?(path)

      log_compact_index_request(endpoint: "info", gem_name: gem_name)
      serve_compact_index_file(path, stale: stale)
    end

    # GET /names
    # Returns gem names only.
    # Names are intentionally unfiltered because the resolver decides from
    # /versions and /info/:name; hiding a name is only necessary when every
    # version line disappears from /versions.
    def names
      path = compact_index_path.join("names")
      stale = false

      unless File.exist?(path)
        stale = !sync_names_file
      end

      return head :not_found unless File.exist?(path)

      log_compact_index_request(endpoint: "names")
      serve_compact_index_file(path, stale: stale)
    end

    private

    def compact_index_path
      storage_path.join("compact_index")
    end

    def serve_compact_index_file(path, stale: false)
      etag = Digest::MD5.file(path).hexdigest

      # Handle conditional GET - return 304 if content unchanged
      if request.headers["If-None-Match"] == %("#{etag}")
        head :not_modified
        return
      end

      set_cache_headers(path, etag)

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

      # Quarantine changes can happen outside of upstream sync cadence, so we
      # always re-run filtering when the cached file is stale.
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

    def set_cache_headers(path, etag)
      response.headers["ETag"] = %("#{etag}")
      response.headers["Last-Modified"] = File.mtime(path).httpdate
      # Force revalidation - bundler must check with GemGuard before using cached data
      # This ensures quarantine changes take effect immediately
      response.headers["Cache-Control"] = "public, no-cache"
    end

    def log_compact_index_request(endpoint:, gem_name: nil)
      AuditLog.log_compact_index_request(
        request: request,
        endpoint: endpoint,
        gem_name: gem_name
      )
    end
  end
end
