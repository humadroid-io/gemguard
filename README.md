# GemGuard

A self-hosted security proxy for RubyGems that helps development teams protect against supply chain attacks and achieve SOC2 compliance through intelligent dependency management.

## What is GemGuard?

GemGuard acts as a transparent proxy between your Bundler and RubyGems.org, adding enterprise-grade security controls without changing your development workflow. Simply replace one line in your Gemfile, and GemGuard automatically:

- **Quarantines new gem versions** for 72 hours (configurable) to protect against malicious updates
- **Caches all dependencies locally** to prevent outages and ensure reproducible builds
- **Maintains comprehensive audit logs** for SOC2 compliance and security reviews
- **Alerts on suspicious updates** via email/Slack when new versions are published

## Quick Start

```bash
# Clone and start with Docker Compose
git clone https://github.com/your-org/gemguard.git
cd gemguard
docker compose up -d

# Update your Gemfile
source "http://localhost:9292"  # Instead of "https://rubygems.org"

# Import your current gems (via web UI)
# Go to http://localhost:9292/admin/settings and upload your Gemfile.lock

# Install gems as usual
bundle install
```

That's it! GemGuard automatically bootstraps on first start. Upload your `Gemfile.lock` to approve your current dependencies and start tracking new versions.

> **Don't have Docker Compose?** Install it with `apt install docker-compose-plugin` (Linux) or get [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Mac/Windows). See [plain docker commands](#using-docker-without-compose) if you prefer not to install it.

## Key Features

### Security First

- **Automatic Quarantine**: New gem versions are held for review before becoming available
- **Version Pinning**: Block specific versions or require manual approval
- **Vulnerability Scanning**: Integration with Ruby Advisory Database (coming soon)

### SOC2 Compliance Ready

- **Complete Audit Trail**: Track who installed what, when, and from where
- **Compliance Reports**: Export audit logs for security reviews
- **Change Management**: Demonstrate control over dependency updates

### Developer Friendly

- **100% Bundler Compatible**: Works with your existing tools and workflows
- **Zero Configuration**: Sensible defaults that just work
- **Fast**: Aggressive caching means no performance impact

### Reliable

- **Offline Mode**: Continue working even when RubyGems.org is down (serves cached data)
- **Local Cache**: All gems and index files cached after first download
- **Stale-While-Error**: Automatically serves cached specs when upstream is unavailable
- **Lightweight**: Runs on a $5/month VPS with SQLite

## Who is GemGuard For?

- **Small to Medium Teams** (5-50 developers) who need enterprise-grade security without enterprise complexity
- **Rails Consultancies** managing multiple client applications
- **Regulated Industries** (healthcare, fintech)

## Self-Hosting with Docker

### Using Docker Compose (Recommended)

```bash
# Start GemGuard on port 9292
docker compose up -d

# View logs
docker compose logs -f

# Stop
docker compose down
```

GemGuard will be available at `http://localhost:9292`.

#### Custom Port

```bash
# Run on port 3001
GEMGUARD_PORT=3001 docker compose up -d
```

Or create a `.env` file:

```bash
echo "GEMGUARD_PORT=3001" > .env
docker compose up -d
```

#### Persistent Data

Docker Compose automatically creates named volumes:

- `gemguard_storage` - Specs files and cached gems
- `gemguard_db` - SQLite database and auto-generated secrets

Data persists across container restarts. A unique `SECRET_KEY_BASE` is auto-generated on first run and saved to the db volume, so you don't need to configure any secrets for single-instance deployments.

> **Multi-replica deployments**: If running multiple GemGuard instances behind a load balancer, set `SECRET_KEY_BASE` explicitly in your environment to ensure all instances share the same secret.

### Using Docker Without Compose

If you don't have Docker Compose installed:

```bash
# Build the image
docker build -t gemguard .

# Run on port 9292
docker run -d --name gemguard \
  -p 9292:80 \
  -e SOLID_QUEUE_IN_PUMA=1 \
  -v gemguard_storage:/rails/storage \
  -v gemguard_db:/rails/db \
  gemguard

# View logs
docker logs -f gemguard

# Stop and remove
docker stop gemguard && docker rm gemguard
```

### First Run: Bootstrap

GemGuard automatically bootstraps on first start - it syncs the Compact Index and specs files from RubyGems.org. This establishes the baseline so only NEW versions (published after bootstrap) get quarantined.

### Import Your Application's Gems

After GemGuard is running, import your application's dependencies to:
- Mark your current gem versions as **approved**
- Fetch gem metadata (descriptions, release dates)
- **Quarantine any newer versions** not in your lockfile

**Option 1: Web Upload (Recommended)**

Go to `http://localhost:9292/admin/settings` and upload your `Gemfile.lock` in the "Import from Gemfile.lock" section.

**Option 2: Fresh Bundle Install**

Point your app at GemGuard and re-fetch all gems:

```bash
# Update Gemfile source to GemGuard
# source "http://localhost:9292"

# Clear cache and re-install
rm -rf vendor/bundle .bundle/cache && bundle install
```

This creates GemPackage/GemVersion records as gems are fetched.

### Configuring Your Projects

Update your project's Gemfile to use GemGuard:

```ruby
# Before
source "https://rubygems.org"

# After
source "http://localhost:9292"
```

For team-wide deployment, use a hostname accessible to all developers:

```ruby
source "http://gemguard.internal:9292"
```

## Tech Stack

- **Ruby**: 3.4.8
- **Rails**: 8.1.1
- **Database**: SQLite3
- **Frontend**: Tailwind CSS, Hotwire (Turbo + Stimulus), esbuild
- **Deployment**: Docker, Kamal

## How It Works

GemGuard uses a **filtered index** approach for transparent quarantine:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Bundler   │────▶│  GemGuard   │────▶│ RubyGems.org│
│  (client)   │◀────│   (proxy)   │◀────│  (upstream) │
└─────────────┘     └─────────────┘     └─────────────┘
```

1. **Baseline Import**: Downloads specs files from RubyGems.org (names/versions only, no database records)
2. **Specs Sync**: Background jobs periodically sync specs and detect NEW versions via diff
3. **Quarantine Tracking**: New versions are inserted into lightweight `quarantined_versions` table
4. **Filtered Resolver Metadata**: GemGuard serves filtered legacy specs and Compact Index data, excluding actively quarantined and explicitly blocked versions
5. **On-Demand Tracking**: When a gem is actually requested, GemGuard creates database records for audit/caching
6. **Smart Approval**: Gems past the quarantine period are auto-approved and removed from the active quarantine set

### Why Filtering at Index Level?

Bundler resolves from index metadata first. Depending on client/version, that means the legacy specs files (`specs.4.8.gz`, `latest_specs.4.8.gz`, `prerelease_specs.4.8.gz`) and/or the Compact Index (`/versions` and `/info/:name`).

If a version is removed from those resolver-visible files, Bundler does not know it exists and will not resolve it.

This means:
- Bundler never sees actively quarantined or blocked versions during resolution
- Your database only contains gems your team actually uses
- Quarantine is based on actual RubyGems publish date
- Adding or removing quarantine regenerates filtered specs and compact index data so the resolver view stays in sync

### Database Design

| Table | Purpose | Expected Size |
|-------|---------|---------------|
| `quarantined_versions` | Track new versions for filtering | ~6k rows (72h window) |
| `gem_packages` | Track gems your team uses | 50-500 packages |
| `gem_versions` | Version details for tracked gems | 100-2000 versions |
| `audit_logs` | All gem requests | Grows with usage |

### Storage Structure

```
storage/
├── specs/
│   ├── raw/              # Original specs from RubyGems
│   │   ├── specs.4.8.gz
│   │   ├── latest_specs.4.8.gz
│   │   └── prerelease_specs.4.8.gz
│   ├── specs.4.8.gz      # Filtered (served to Bundler)
│   ├── latest_specs.4.8.gz
│   └── prerelease_specs.4.8.gz
├── compact_index/        # Compact Index files
│   ├── versions          # Filtered resolver-visible versions
│   ├── names             # Gem names only (unfiltered; names do not expose versions)
│   └── info/             # Filtered per-gem dependency info
│       ├── rails
│       ├── nokogiri
│       └── ...
└── gems/                 # Cached .gem files
```

### Offline Operation

GemGuard is designed to work reliably even when RubyGems.org is unavailable:

| Component | Cache Location | Offline Behavior |
|-----------|----------------|------------------|
| **Gem files** | `storage/gems/` | Served from cache if previously downloaded |
| **Legacy specs** | `storage/specs/` | Stale cached version served with `X-GemGuard-Stale: true` header |
| **Compact Index** | `storage/compact_index/` | Stale cached version served with `X-GemGuard-Stale: true` header |

**To ensure full offline capability:**

1. Import your `Gemfile.lock` via Settings to approve current dependencies
2. Run `bundle install` once through GemGuard to cache all gem files
3. The bootstrap task automatically syncs index files on first deploy

When upstream is unavailable, GemGuard:
- Serves cached gems normally
- Serves stale index files (adding `X-GemGuard-Stale: true` response header)
- Returns `502 Bad Gateway` only for gems that were never cached

## Background Jobs

GemGuard uses Solid Queue for background job processing:

| Job | Schedule | Description |
|-----|----------|-------------|
| **Sync All Specs** | Every 6 hours | Full specs sync, tracks new versions, builds filtered specs |
| **Sync Latest Specs** | Every 10 minutes | Latest versions sync for quick detection |
| **Sync Prerelease Specs** | Every hour | Prerelease versions sync |
| **Cleanup Quarantined Versions** | Every hour | Removes expired entries from quarantine |
| **Clear Finished Jobs** | Every hour | Cleans up completed job records |

Jobs are configured in `config/recurring.yml`.

## Development

### Prerequisites

- Ruby 3.4.8
- Node.js 25.2.1
- Yarn

### Setup

```bash
bin/setup
```

### Development Server

Start the development server with asset watchers:

```bash
bin/dev
```

This runs:

- Rails server (Puma)
- JavaScript bundler (esbuild)
- CSS compiler (Tailwind)

#### Running on a Custom Port

To run GemGuard alongside other Rails apps:

```bash
PORT=3001 bin/dev
```

### Testing

```bash
# Unit tests
bin/rails test

# System tests (browser automation)
bin/rails test:system
```

### Code Quality

```bash
# Security vulnerability scan
bin/brakeman

# Check gem vulnerabilities
bin/bundler-audit

# Code style check
bin/rubocop
```

## Rake Tasks

### Baseline Management

```bash
# Import baseline from RubyGems specs (recommended)
bin/rails baseline:import

# Force reimport
bin/rails baseline:reimport

# Check baseline status
bin/rails baseline:status

# Export baseline to CSV
bin/rails baseline:export
```

### Statistics and Cleanup

```bash
# Show database statistics
bin/rails gemguard:stats

# Reset database (deletes all data)
bin/rails gemguard:reset
```

## Production Deployment

Deployment is handled via Kamal:

```bash
bin/kamal deploy
```

See `config/deploy.yml` for configuration.

## License

See [LICENSE.md](LICENSE.md) for details.
