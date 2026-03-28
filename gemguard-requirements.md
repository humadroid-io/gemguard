# GemGuard Development Plan

## Overview

Security-focused RubyGems proxy with quarantine periods, caching, and audit logging. Self-hostable on a $5 VPS for SOC2 compliance.

**Core Features**: 72-hour quarantine for new gems, local caching, audit logs, one-line Gemfile change.

## Stack

- Rails 8.1, SQLite (WAL mode), Solid Queue/Cache
- Tailwind CSS v4 + DaisyUI v5
- esbuild + Hotwire (Turbo/Stimulus)
- Docker + Kamal

---

## Architecture

### Design Principles

1. **Transparent proxy**: Bundler works normally - quarantined gems simply don't appear in the index
2. **On-demand tracking**: Only gems actually requested by your team are stored in detail
3. **Lightweight quarantine**: Track only new versions (deltas) for filtering, not all 200k+ gems
4. **Smart auto-approval**: Established gems (published before quarantine period) pass through automatically

### Two-Tier Tracking System

| Table | Purpose | Data | Size |
|-------|---------|------|------|
| `quarantined_versions` | Filter specs | name, version, platform, first_seen_at | ~6k rows (72h window) |
| `gem_packages` / `gem_versions` | Full gem details for audit/management | All gem metadata | Only gems you use |

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SPECS FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  RubyGems.org          SyncSpecsJob              GemGuard                   │
│  ┌──────────┐         ┌────────────┐           ┌──────────────┐             │
│  │specs.4.8 │────────▶│ 1. Download│──────────▶│ raw_specs/   │             │
│  │.gz (raw) │         │ 2. Diff    │           │              │             │
│  └──────────┘         │ 3. Track   │           ├──────────────┤             │
│                       │    new     │──────────▶│ quarantined_ │             │
│                       │    versions│           │ versions     │             │
│                       │ 4. Filter  │           │ (table)      │             │
│                       │ 5. Build   │──────────▶├──────────────┤             │
│                       └────────────┘           │ specs.4.8.gz │             │
│                                                │ (filtered)   │             │
│                                                └──────┬───────┘             │
│                                                       │                     │
│                                                       ▼                     │
│                                                ┌──────────────┐             │
│                                                │   Bundler    │             │
│                                                │ (only sees   │             │
│                                                │  available   │             │
│                                                │  versions)   │             │
│                                                └──────────────┘             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              GEM REQUEST FLOW                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Bundler              GemGuard                 RubyGems.org                 │
│  ┌──────────┐        ┌─────────────────┐      ┌──────────────┐              │
│  │ Request  │───────▶│ 1. Check cache  │      │              │              │
│  │ rails-   │        │ 2. Check DB     │      │              │              │
│  │ 7.2.0.gem│        │                 │      │              │              │
│  └──────────┘        │ If not found:   │      │              │              │
│                      │ 3. Fetch API ───────────▶ /api/v1/    │              │
│                      │    details      │◀──────── gems/rails │              │
│                      │ 4. Create       │      │ /versions/   │              │
│                      │    GemPackage   │      │ 7.2.0.json   │              │
│                      │    GemVersion   │      │              │              │
│                      │                 │      │              │              │
│                      │ 5. Check        │      │              │              │
│                      │    quarantine:  │      │              │              │
│                      │    - In table?  │      │              │              │
│                      │    - Publish    │      │              │              │
│                      │      date?      │      │              │              │
│                      │                 │      │              │              │
│                      │ 6. If approved: │      │              │              │
│       .gem ◀─────────│    proxy gem ◀─────────── /gems/     │              │
│                      │    & cache      │      │ rails-7.2.0 │              │
│                      │                 │      │ .gem        │              │
│                      │ 7. Audit log    │      └──────────────┘              │
│                      └─────────────────┘                                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Quarantine Logic

A gem version is **quarantined** if ANY of these are true:
1. It exists in `quarantined_versions` table with `first_seen_at` within quarantine period
2. Its RubyGems API `created_at` (publish date) is within quarantine period

A gem version is **approved** if:
1. It's explicitly marked approved in `gem_versions.status`
2. It passed quarantine period (auto-approved by background job)
3. It's an established gem (published before quarantine period started)

---

## Database Schema

```
gem_packages: name:uniq, downloads_count, info, homepage_url
gem_versions: gem_package_id, version, platform, checksum, published_at, first_seen_at, status(enum), cached_at, file_size
  - status: quarantined/approved/blocked
  - unique index: [gem_package_id, version, platform]
  - published_at: from RubyGems API (when gem was published)
  - first_seen_at: when GemGuard first saw this version
quarantined_versions: name, version, platform, first_seen_at
  - unique index: [name, version, platform]
  - lightweight table for specs filtering only
  - auto-cleaned after quarantine period expires
  - scopes: active (within quarantine period), expired (past quarantine period)
quarantine_rules: gem_package_id(nullable), rule_type(enum), value, enabled, description
  - rule_type: time_based/version_pattern/manual
audit_logs: gem_name, version, action, ip_address, user_agent, bundle_version, requested_at
settings: key:uniq, value, value_type(string/integer/boolean/json)
```

## API Endpoints

```
# Bundler-required (RubyGems compatible):
GET /specs.4.8.gz              # FILTERED specs (excludes quarantined)
GET /latest_specs.4.8.gz       # FILTERED latest versions
GET /prerelease_specs.4.8.gz   # FILTERED prereleases
GET /gems/{name}-{version}.gem # Download gem (if approved)
GET /quick/Marshal.4.8/{name}-{version}.gemspec.rz

# Admin:
/admin, /admin/gem_packages, /admin/quarantine_rules, /admin/audit_logs, /admin/settings
```

---

## Background Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `SyncSpecsJob` | Every 10 min (latest), 1 hour (prerelease), 6 hours (all) | Download specs, diff, track new versions, build filtered specs |
| `ApproveExpiredQuarantineJob` | Every 5 min | Auto-approve gems past quarantine period |
| `CleanupQuarantinedVersionsJob` | Every hour | Remove expired entries from `quarantined_versions` table |

---

## Progress Tracking

### Phase 1: MVP - Core Proxy ✅
**Goal**: Working proxy that can replace RubyGems.org

- [x] Rails 8 app setup with Tailwind + DaisyUI
- [x] Database schema and models (GemPackage, GemVersion, AuditLog, Setting)
- [x] Basic proxy endpoints (`/specs.4.8.gz`, `/gems/:id`, `/quick/...`)
- [x] Background job: sync specs from RubyGems.org
- [x] Local file storage for specs and gem caches
- [x] On-demand gem lookup from RubyGems API
- [x] Test with real Gemfile

**Success**: `bundle install` works with GemGuard as source ✅

### Phase 2: Security Features ✅
**Goal**: Quarantine logic with filtered specs

- [x] Basic quarantine rules (72-hour default via Setting)
- [x] **QuarantinedVersion model** - lightweight tracking for new versions
- [x] **Filtered specs** - build specs excluding quarantined versions
- [x] **SyncSpecsJob refactor** - diff, track new versions, build filtered specs
- [x] Track first_seen_at for versions
- [x] Track published_at (from RubyGems API) for accurate quarantine timing
- [x] Audit log for every fetch
- [x] Auto-approval job for expired quarantine (ApproveExpiredQuarantineJob)
- [x] Cleanup job for expired quarantine entries (CleanupQuarantinedVersionsJob)
- [x] Atomic file writes for specs to prevent race conditions
- [x] Manual approval/blocking UI
- [ ] Email/Slack alerts for new quarantined gems

**Success**: New gems quarantined for 72 hours, bundler only sees available versions ✅

### Phase 3: Admin Interface
**Goal**: Polished UI for managing proxy

- [x] Dashboard with metrics (gems tracked, quarantined, approved)
- [x] Gem browser with search/filter
- [x] Quarantine rules management
- [x] Audit log viewer + CSV export
- [x] Settings page
- [ ] Basic authentication
- [ ] SOC2 compliance reports

**Success**: Non-technical user can manage rules

### Phase 4: Performance & Reliability
- [ ] Optimize specs endpoint (ETags, compression)
- [ ] Gem download streaming
- [ ] CDN support
- [ ] Cache cleanup job
- [x] Health check endpoint
- [ ] Monitoring/alerting
- [ ] Backup/restore

### Phase 5: Launch Preparation
- [ ] Documentation site
- [ ] One-click Kamal deployment
- [x] Docker Compose example
- [ ] Migration guide
- [ ] Load testing
- [ ] Security audit

### Phase 6+: Future
- Vulnerability scanning, license compliance, team management, API, private gems, webhooks
- Billing, SSO/SAML, multi-region

---

## Implementation Plan for Phase 2 ✅ COMPLETED

### Step 1: Create QuarantinedVersion model ✅
- Created `quarantined_versions` table with unique index on [name, version, platform]
- Model includes `active` and `expired` scopes based on `first_seen_at`

### Step 2: Update SyncSpecsJob ✅
1. Downloads raw specs from RubyGems
2. Parses and saves to `storage/specs/raw/`
3. Loads previous specs and diffs to find new versions
4. Inserts new versions into `quarantined_versions` table
5. Builds filtered specs excluding active quarantined versions
6. Saves filtered specs to `storage/specs/` using atomic writes

### Step 3: Update SpecsController ✅
- Serves filtered specs from `storage/specs/`
- Triggers sync if specs are missing or stale
- Falls back to upstream proxy if needed

### Step 4: Add CleanupQuarantinedVersionsJob ✅
- Removes expired entries (older than quarantine period)
- Runs hourly via Solid Queue

### Step 5: Update GemsController ✅
- Uses `GemVersion#available?` which checks quarantine status
- Returns 404 (not 403) for quarantined gems
- Quarantine based on `published_at` from RubyGems API

### Step 6: Add ApproveExpiredQuarantineJob ✅
- Auto-approves `GemVersion` records past quarantine period
- Runs every 5 minutes

---

## File Structure

```
app/
├── controllers/
│   ├── api/
│   │   ├── base_controller.rb
│   │   ├── specs_controller.rb      # Serves filtered specs
│   │   ├── gems_controller.rb       # Serves gems (checks quarantine)
│   │   └── gemspecs_controller.rb   # Serves gemspecs
│   └── admin/
│       └── ... (Phase 3)
├── jobs/
│   ├── sync_specs_job.rb                    # Downloads, diffs, tracks, filters specs
│   ├── approve_expired_quarantine_job.rb    # Auto-approves GemVersion records
│   └── cleanup_quarantined_versions_job.rb  # Cleans expired quarantine entries
├── models/
│   ├── gem_package.rb
│   ├── gem_version.rb          # has status, published_at, actively_quarantined?
│   ├── quarantined_version.rb  # lightweight tracking for specs filtering
│   ├── quarantine_rule.rb
│   ├── audit_log.rb
│   └── setting.rb
├── services/
│   └── rubygems_client.rb      # API client for RubyGems.org
└── views/admin/... (Phase 3)

storage/
├── specs/
│   ├── raw/                    # Original specs from RubyGems (for diffing)
│   │   ├── specs.4.8.gz
│   │   ├── latest_specs.4.8.gz
│   │   └── prerelease_specs.4.8.gz
│   ├── specs.4.8.gz            # Filtered specs (served to bundler)
│   ├── latest_specs.4.8.gz
│   ├── prerelease_specs.4.8.gz
│   └── quick/                  # Cached gemspecs
└── gems/                       # Cached .gem files
```
