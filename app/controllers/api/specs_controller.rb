module Api
  class SpecsController < BaseController
    SPEC_TYPES = {
      "specs.4.8.gz" => :all,
      "latest_specs.4.8.gz" => :latest,
      "prerelease_specs.4.8.gz" => :prerelease
    }.freeze

    def index
      serve_specs("specs.4.8.gz")
    end

    def latest
      serve_specs("latest_specs.4.8.gz")
    end

    def prerelease
      serve_specs("prerelease_specs.4.8.gz")
    end

    private

    def serve_specs(filename)
      filtered_path = filtered_specs_path.join(filename)

      if File.exist?(filtered_path) && fresh_cache?(filtered_path)
        serve_file(filtered_path, filename)
      else
        sync_and_serve(filename, filtered_path)
      end
    end

    def sync_and_serve(filename, filtered_path)
      type = SPEC_TYPES[filename]
      sync_success = false

      begin
        SyncSpecsJob.perform_now(type: type)
        sync_success = true
      rescue => e
        Rails.logger.error("SpecsController: Sync failed: #{e.message}")
      end

      # Prefer serving local file (even if stale) over proxying
      # This ensures offline operation works with cached data
      if File.exist?(filtered_path)
        serve_file(filtered_path, filename, stale: !sync_success)
      elsif sync_success
        # Sync succeeded but no file - unexpected, try proxy
        proxy_from_upstream(filename)
      else
        # No local file and sync failed - try proxy as last resort
        proxy_from_upstream(filename)
      end
    end

    def serve_file(path, filename, stale: false)
      AuditLog.log_spec_request(request: request, spec_type: filename)
      set_cache_headers(File.mtime(path))

      # Indicate when serving stale data (upstream unavailable)
      if stale
        response.headers["X-GemGuard-Stale"] = "true"
        Rails.logger.info("SpecsController: Serving stale #{filename} (upstream unavailable)")
      end

      send_file path, type: "application/x-gzip", disposition: "inline"
    end

    def proxy_from_upstream(filename)
      url = "#{Setting.upstream_source}/#{filename}"
      response = fetch_upstream(url)

      unless response&.success?
        head :bad_gateway
        return
      end

      if response.code == 304
        head :not_modified
        return
      end

      body = response.body
      return head(:bad_gateway) if body.nil? || body.empty?

      # Filter specs before serving to ensure quarantined/blocked gems are never exposed
      filtered_body = filter_specs(body)

      AuditLog.log_spec_request(request: request, spec_type: filename)
      set_cache_headers(Time.current)
      send_data filtered_body, type: "application/x-gzip", disposition: "inline"
    end

    def filter_specs(gzipped_data)
      # Parse the specs
      specs = RubygemsClient.parse_specs(gzipped_data)
      return gzipped_data if specs.empty?

      # Build BLOCKED set - gems explicitly blocked
      blocked_set = GemVersion.blocked
        .joins(:gem_package)
        .pluck("gem_packages.name", :version, :platform)
        .to_set

      # Build ACTIVE QUARANTINE set - gems still in quarantine period
      quarantined_set = QuarantinedVersion.active
        .pluck(:name, :version, :platform)
        .to_set

      # Exclude blocked and actively quarantined gems
      # Unknown gems pass through - we only block what we know about
      excluded_set = blocked_set | quarantined_set

      filtered_specs = specs.reject do |name, version, platform|
        platform_str = platform.to_s.presence || "ruby"
        excluded_set.include?([name, version.to_s, platform_str])
      end

      excluded_count = specs.size - filtered_specs.size
      if excluded_count > 0
        Rails.logger.info("SpecsController: Excluded #{excluded_count} versions (blocked/quarantined)")
      end

      # Re-gzip and return
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      gz.write(Marshal.dump(filtered_specs))
      gz.close
      io.string
    rescue => e
      Rails.logger.error("SpecsController: Failed to filter specs: #{e.message}")
      # On error, pass through unfiltered - prefer availability over blocking
      gzipped_data
    end

    def build_empty_specs
      io = StringIO.new
      gz = Zlib::GzipWriter.new(io)
      gz.write(Marshal.dump([]))
      gz.close
      io.string
    end

    def fetch_upstream(url)
      HTTParty.get(url, timeout: 30, headers: upstream_headers)
    rescue => e
      Rails.logger.error("Failed to fetch #{url}: #{e.message}")
      nil
    end

    def upstream_headers
      headers = {"User-Agent" => "GemGuard/1.0"}
      headers["If-Modified-Since"] = request.headers["If-Modified-Since"] if request.headers["If-Modified-Since"]
      headers["If-None-Match"] = request.headers["If-None-Match"] if request.headers["If-None-Match"]
      headers
    end

    def fresh_cache?(path)
      File.mtime(path) > 5.minutes.ago
    end

    def set_cache_headers(last_modified)
      response.headers["Last-Modified"] = last_modified.httpdate
      response.headers["Cache-Control"] = "public, max-age=300"
      expires_in 5.minutes, public: true
    end

    def filtered_specs_path
      Rails.root.join("storage", "specs")
    end
  end
end
