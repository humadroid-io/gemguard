# GemGuard

A self-hosted security proxy for RubyGems that helps development teams protect against supply chain attacks and achieve SOC2 compliance through intelligent dependency management.

## 🎯 What is GemGuard?

GemGuard acts as a transparent proxy between your Bundler and RubyGems.org, adding enterprise-grade security controls without changing your development workflow. Simply replace one line in your Gemfile, and GemGuard automatically:

- **🛡️ Quarantines new gem versions** for 72 hours (configurable) to protect against malicious updates
- **📦 Caches all dependencies locally** to prevent outages and ensure reproducible builds
- **📝 Maintains comprehensive audit logs** for SOC2 compliance and security reviews
- **🚨 Alerts on suspicious updates** via email/Slack when new versions are published

## 🚀 Quick Start

```bash
# Deploy with Docker
docker run -d -p 3000:3000 gemguard/gemguard

# Update your Gemfile
source "http://localhost:3000"  # Instead of "https://rubygems.org"

# Install gems as usual
bundle install
```

That's it! No agents to install, no complex configuration, no changes to your workflow.

## ✨ Key Features

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

## 🏢 Who is GemGuard For?

- **Small to Medium Teams** (5-50 developers) who need enterprise-grade security without enterprise complexity
- **Rails Consultancies** managing multiple client applications
- **Regulated Industries** (healthcare, fintech)

## Tech Stack

- **Ruby**: 3.4.8
- **Rails**: 8.1.1
- **Database**: SQLite3
- **Frontend**: Tailwind CSS, Hotwire (Turbo + Stimulus), esbuild
- **Deployment**: Docker, Kamal

### SQLite Performance

GemGuard uses SQLite, which comfortably handles the full RubyGems baseline (~200k gems, ~4M versions, ~2GB database). SQLite is well-suited for this workload because:

- **Read-heavy**: Most operations are gem lookups, not writes
- **Simple queries**: Lookups by name/version, no complex analytics
- **WAL mode**: Rails 8 enables Write-Ahead Logging by default for concurrent access
- **Proper indexes**: All lookup columns are indexed

SQLite routinely handles 10-100GB databases. If you need to verify performance:

```bash
# Check database stats
sqlite3 storage/production.sqlite3 "SELECT COUNT(*) FROM gem_versions;"

# Verify query uses index
sqlite3 storage/production.sqlite3 "EXPLAIN QUERY PLAN SELECT * FROM gem_versions WHERE gem_package_id = 1;"
```

## Getting Started

### Prerequisites

- Ruby 3.4.8
- Node.js 25.2.1
- Yarn

### Setup

```bash
bin/setup
```

### Development

Start the development server with asset watchers:

```bash
bin/dev
```

This runs:

- Rails server (Puma)
- JavaScript bundler (esbuild)
- CSS compiler (Tailwind)

#### Running on a Custom Port

To run GemGuard alongside other Rails apps, use a different port:

```bash
PORT=3001 bin/dev
```

Then update your app's Gemfile to use GemGuard:

```ruby
source "http://localhost:3001"  # Instead of "https://rubygems.org"
```

## How It Works

GemGuard uses a **filtered specs** approach for transparent quarantine:

1. **Specs sync**: Background jobs sync gem indices from RubyGems.org and detect new versions
2. **Quarantine tracking**: New versions are tracked in a lightweight `quarantined_versions` table
3. **Filtered specs**: GemGuard builds filtered specs excluding quarantined versions - Bundler only sees available gems
4. **On-demand details**: When a gem is requested, GemGuard fetches full metadata from RubyGems API
5. **Smart approval**: Gems past the quarantine period (based on RubyGems publish date) are auto-approved
6. **Local caching**: Downloaded gems are cached locally for offline use and faster subsequent installs

This means:
- Bundler never sees quarantined gems (no confusing errors)
- Your database only contains gems your team actually uses
- Quarantine is based on actual RubyGems publish date, not when you first synced

## Baseline Import

Before GemGuard can properly quarantine gems, it needs to know which gems existed before installation. This is called the "baseline". Gems in the baseline are automatically approved; only new versions released after the baseline are quarantined.

### Import Options

| Method | Data Size | Time | What You Get |
|--------|-----------|------|--------------|
| **From Specs** (Recommended) | ~30MB | 2-5 min | All gem names/versions, ready-to-use specs files |
| **Full RubyGems Dump** | ~900MB | 10-30 min | Complete data with accurate release dates |
| **CSV Baseline** | Varies | 1-2 min | Pre-built baseline (requires external file) |

### Via Admin UI

Navigate to **Admin → Settings** and choose an import option in the "Baseline Database" section.

### Via Rake Tasks

```bash
# Recommended: Import from RubyGems specs files
bin/rails baseline:import_from_specs

# Include prerelease versions
INCLUDE_PRERELEASE=1 bin/rails baseline:import_from_specs

# Full dump with accurate release dates
bin/rails baseline:import_from_dump

# CSV baseline (if you have a baseline file)
bin/rails baseline:import
```

### Which Option Should I Choose?

- **From Specs** (Recommended): Best balance of speed and completeness. Downloads specs files directly from RubyGems, parses all gem versions, and saves the specs for immediate use by the filtering system.

- **Full Dump**: Use if you need accurate original release dates for all gems (for precise quarantine calculations based on when gems were actually published on RubyGems.org).

- **CSV Baseline**: Use if you have a pre-built baseline file from another GemGuard instance or a custom source.

## Background Jobs

GemGuard uses Solid Queue for background job processing. The following jobs run automatically:

| Job | Schedule | Description |
|-----|----------|-------------|
| **Sync All Specs** | Every 6 hours | Downloads full gem index, tracks new versions, builds filtered specs |
| **Sync Latest Specs** | Every 10 minutes | Downloads latest versions index, tracks new versions, builds filtered specs |
| **Sync Prerelease Specs** | Every hour | Downloads prerelease index, tracks new versions, builds filtered specs |
| **Approve Expired Quarantine** | Every 5 minutes | Auto-approves `GemVersion` records past quarantine period |
| **Cleanup Quarantined Versions** | Every hour | Removes expired entries from `quarantined_versions` table |
| **Clear Finished Jobs** | Every hour | Cleans up completed job records (production only) |

Jobs are configured in `config/recurring.yml`.

## Testing

```bash
# Unit tests
bin/rails test

# System tests (browser automation)
bin/rails test:system
```

## Code Quality

```bash
# Security vulnerability scan
bin/brakeman

# Check gem vulnerabilities
bin/bundler-audit

# Code style check
bin/rubocop
```

## Deployment

Deployment is handled via Kamal:

```bash
bin/kamal deploy
```

## License

See [LICENSE.md](LICENSE.md) for details.
