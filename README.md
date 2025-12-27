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

# Install gems as usual
bundle install
```

That's it! No agents to install, no complex configuration, no changes to your workflow.

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

- **Offline Mode**: Continue working even when RubyGems.org is down
- **Local Cache**: All gems cached after first download
- **Lightweight**: Runs on a $5/month VPS with SQLite

## Who is GemGuard For?

- **Small to Medium Teams** (5-50 developers) who need enterprise-grade security without enterprise complexity
- **Rails Consultancies** managing multiple client applications
- **Regulated Industries** (healthcare, fintech)

## Self-Hosting with Docker

### Using Docker Compose (Recommended)

The easiest way to run GemGuard locally or on a server:

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

To use a different port, set the `GEMGUARD_PORT` environment variable:

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

Docker Compose automatically creates volumes for:

- `gemguard_storage` - Specs files and cached gems
- `gemguard_db` - SQLite database

Data persists across container restarts.

### Using Docker Directly

```bash
# Build the image
docker build -t gemguard .

# Run on port 9292
docker run -d \
  --name gemguard \
  -p 9292:80 \
  -v gemguard_storage:/rails/storage \
  -v gemguard_db:/rails/db \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  gemguard

# View logs
docker logs -f gemguard

# Stop
docker stop gemguard && docker rm gemguard
```

### First Run: Import Baseline

After starting GemGuard for the first time, you need to import the baseline from RubyGems.org. This tells GemGuard which gems existed before your installation, so only NEW versions get quarantined.

#### Via Admin UI

1. Navigate to `http://localhost:9292/admin/settings`
2. Click "Import Baseline"
3. Wait 2-5 minutes for the import to complete

#### Via Rake Task

```bash
# If using Docker Compose
docker compose exec web bin/rails baseline:import

# If using Docker directly
docker exec -it gemguard bin/rails baseline:import
```

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

GemGuard uses a **filtered specs** approach for transparent quarantine:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Bundler   │────▶│  GemGuard   │────▶│ RubyGems.org│
│  (client)   │◀────│   (proxy)   │◀────│  (upstream) │
└─────────────┘     └─────────────┘     └─────────────┘
```

1. **Baseline Import**: Downloads specs files from RubyGems.org (names/versions only, no database records)
2. **Specs Sync**: Background jobs periodically sync specs and detect NEW versions via diff
3. **Quarantine Tracking**: New versions are inserted into lightweight `quarantined_versions` table
4. **Filtered Specs**: GemGuard serves filtered specs excluding quarantined versions - Bundler only sees available gems
5. **On-Demand Tracking**: When a gem is actually requested, GemGuard creates database records for audit/caching
6. **Smart Approval**: Gems past the quarantine period are auto-approved

### Why Filtering at Specs Level?

Bundler fetches the specs index (`specs.4.8.gz`) first to know what versions exist, then resolves dependencies locally. If a version isn't in the specs, Bundler doesn't know it exists.

This means:
- Bundler never sees quarantined gems (no confusing errors)
- Your database only contains gems your team actually uses
- Quarantine is based on actual RubyGems publish date

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
└── gems/                 # Cached .gem files
```

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
