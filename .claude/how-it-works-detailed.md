# How GemGuard Works: Complete Technical Walkthrough

## Part 1: How Bundler Works

### What Happens When You Run `bundle install`

```
$ bundle install
```

Bundler performs these steps in order:

#### Step 1: Read Gemfile and Gemfile.lock

```ruby
# Gemfile
source "http://localhost:3000"  # GemGuard proxy

gem "rails", "~> 7.2"
gem "sidekiq", ">= 7.0"
gem "nokogiri"
```

Bundler parses this and knows:
- Where to fetch gems from (GemGuard at localhost:3000)
- What gems are needed with version constraints

#### Step 2: Fetch the Specs Index

Bundler needs to know what gems/versions EXIST on the server.

```
GET http://localhost:3000/specs.4.8.gz
```

This returns a gzipped, marshalled Ruby array:

```ruby
[
  ["rails", Gem::Version.new("7.2.0"), "ruby"],
  ["rails", Gem::Version.new("7.1.5"), "ruby"],
  ["rails", Gem::Version.new("7.1.4"), "ruby"],
  ["sidekiq", Gem::Version.new("7.3.0"), "ruby"],
  ["sidekiq", Gem::Version.new("7.2.0"), "ruby"],
  ["nokogiri", Gem::Version.new("1.16.0"), "ruby"],
  ["nokogiri", Gem::Version.new("1.16.0"), "x86_64-linux"],
  # ... ~4 million entries for all gems on RubyGems
]
```

**Critical:** If a version is NOT in this list, Bundler doesn't know it exists.

#### Step 3: Dependency Resolution (Local)

Bundler now has:
- Your requirements (from Gemfile)
- Available versions (from specs.4.8.gz)

It runs a constraint solver locally to find compatible versions:

```
Input:
  - rails ~> 7.2 (requires >= 7.2.0, < 7.3)
  - sidekiq >= 7.0
  - nokogiri (any version)

Available (from specs):
  - rails: 7.2.0, 7.1.5, 7.1.4, ...
  - sidekiq: 7.3.0, 7.2.0, 7.1.0, ...
  - nokogiri: 1.16.0, 1.15.6, ...

Resolution:
  - rails 7.2.0 ✓
  - sidekiq 7.3.0 ✓
  - nokogiri 1.16.0 ✓
```

But wait - Bundler also needs to resolve DEPENDENCIES of these gems.

#### Step 4: Fetch Gemspecs for Dependency Resolution

For each gem it's considering, Bundler fetches the gemspec to learn dependencies:

```
GET http://localhost:3000/quick/Marshal.4.8/rails-7.2.0.gemspec.rz
```

Returns compressed gemspec with:

```ruby
Gem::Specification.new do |s|
  s.name = "rails"
  s.version = "7.2.0"
  s.add_dependency "actionpack", "= 7.2.0"
  s.add_dependency "activerecord", "= 7.2.0"
  s.add_dependency "railties", "= 7.2.0"
  # ... more dependencies
end
```

Bundler adds these dependencies to its requirements and repeats resolution.

#### Step 5: Download Resolved Gems

Once resolution is complete, Bundler downloads each gem:

```
GET http://localhost:3000/gems/rails-7.2.0.gem
GET http://localhost:3000/gems/actionpack-7.2.0.gem
GET http://localhost:3000/gems/activerecord-7.2.0.gem
GET http://localhost:3000/gems/nokogiri-1.16.0-x86_64-linux.gem
# ... all resolved gems
```

#### Step 6: Install Gems Locally

Bundler unpacks and installs each .gem file to your system.

---

## Part 2: How GemGuard Intercepts This Flow

### GemGuard as a Transparent Proxy

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Bundler   │────▶│  GemGuard   │────▶│ RubyGems.org│
│  (client)   │◀────│   (proxy)   │◀────│  (upstream) │
└─────────────┘     └─────────────┘     └─────────────┘
```

GemGuard sits between Bundler and RubyGems.org, intercepting every request.

### Endpoint Mapping

| Bundler Request | GemGuard Handler | Purpose |
|-----------------|------------------|---------|
| `GET /specs.4.8.gz` | `SpecsController#show` | List available gems |
| `GET /latest_specs.4.8.gz` | `SpecsController#show` | Latest versions only |
| `GET /prerelease_specs.4.8.gz` | `SpecsController#show` | Prerelease versions |
| `GET /quick/Marshal.4.8/*.gemspec.rz` | `GemspecsController#show` | Gem dependencies |
| `GET /gems/*.gem` | `GemsController#show` | Download gem file |

---

## Part 3: The Quarantine Mechanism

### How Quarantine Works (After Fix)

The key insight: **Quarantine happens at the SPECS level, not the download level.**

#### Scenario: Malicious Gem Published

```
Timeline:
─────────────────────────────────────────────────────────────────▶

Day 0, 10:00 AM     Day 0, 10:15 AM              Day 3, 10:00 AM
     │                    │                            │
     ▼                    ▼                            ▼
 Attacker publishes   GemGuard syncs,              Quarantine
 evil-gem 1.0.0       detects new version,         expires,
 on RubyGems.org      adds to quarantine           gem available
```

#### What Happens in GemGuard

**1. SyncSpecsJob runs (every 10 minutes for latest_specs)**

```ruby
# SyncSpecsJob performs:

# a) Download new specs from RubyGems
new_specs = RubygemsClient.fetch_specs(:latest)
# Contains: [..., ["evil-gem", "1.0.0", "ruby"], ...]

# b) Load previous specs from storage
previous_specs = load_from("storage/specs/raw/latest_specs.4.8.gz")
# Does NOT contain evil-gem 1.0.0 (it's new!)

# c) Diff to find new versions
new_versions = new_specs - previous_specs
# Returns: [["evil-gem", "1.0.0", "ruby"]]

# d) Insert into quarantined_versions table
QuarantinedVersion.create!(
  name: "evil-gem",
  version: "1.0.0",
  platform: "ruby",
  first_seen_at: Time.current  # Day 0, 10:15 AM
)

# e) Save new raw specs (for next diff)
save_to("storage/specs/raw/latest_specs.4.8.gz", new_specs)

# f) Build FILTERED specs (excluding quarantined)
filtered_specs = new_specs.reject do |name, version, platform|
  QuarantinedVersion.active.exists?(name:, version:, platform:)
end
# evil-gem 1.0.0 is REMOVED from filtered specs

save_to("storage/specs/latest_specs.4.8.gz", filtered_specs)
```

**2. Developer runs `bundle install` (Day 1)**

```ruby
# Bundler requests specs
GET /specs.4.8.gz

# GemGuard serves FILTERED specs from storage/specs/
# evil-gem 1.0.0 is NOT in the response

# Bundler's resolution:
# - Doesn't know evil-gem 1.0.0 exists
# - If Gemfile has `gem "evil-gem"`, resolves to older safe version
# - If no older version, resolution fails (gem doesn't exist)
```

**3. Quarantine expires (Day 3, 10:15 AM)**

```ruby
# ApproveExpiredQuarantineJob runs every 5 minutes

# Finds quarantined_versions where:
#   first_seen_at < 72.hours.ago

# For evil-gem 1.0.0:
#   first_seen_at = Day 0, 10:15 AM
#   72.hours.ago = Day 3, 10:15 AM
#   Still quarantined until 10:15 AM!

# At 10:20 AM (next job run):
#   first_seen_at (Day 0, 10:15) < 72.hours.ago (Day 3, 10:20)
#   Quarantine expired!

# CleanupQuarantinedVersionsJob removes the record
QuarantinedVersion.expired.delete_all
```

**4. Next sync regenerates specs**

```ruby
# SyncSpecsJob runs
# evil-gem 1.0.0 is no longer in QuarantinedVersion.active
# It appears in filtered specs
# Bundler can now resolve and install it
```

---

## Part 4: Complete Request Flow Diagrams

### Flow A: Fetching Specs (Bundler Discovery)

```
┌─────────────────────────────────────────────────────────────────┐
│                    SPECS REQUEST FLOW                            │
└─────────────────────────────────────────────────────────────────┘

Bundler                    GemGuard                     Storage
   │                          │                            │
   │  GET /specs.4.8.gz       │                            │
   │─────────────────────────▶│                            │
   │                          │                            │
   │                          │  Read filtered specs       │
   │                          │───────────────────────────▶│
   │                          │                            │
   │                          │  storage/specs/specs.4.8.gz│
   │                          │◀───────────────────────────│
   │                          │                            │
   │   Gzipped Marshal data   │                            │
   │   (quarantined EXCLUDED) │                            │
   │◀─────────────────────────│                            │
   │                          │                            │
   │  Parse locally           │                            │
   │  [["rails","7.2.0",...], │                            │
   │   ["sidekiq","7.3.0",...]]                            │
   │                          │                            │
   ▼                          │                            │
 Bundler now knows
 what versions exist
 (quarantined versions
  are invisible!)
```

### Flow B: Fetching Gemspec (Dependency Info)

```
┌─────────────────────────────────────────────────────────────────┐
│                   GEMSPEC REQUEST FLOW                           │
└─────────────────────────────────────────────────────────────────┘

Bundler                    GemGuard                   RubyGems.org
   │                          │                            │
   │ GET /quick/Marshal.4.8/  │                            │
   │   rails-7.2.0.gemspec.rz │                            │
   │─────────────────────────▶│                            │
   │                          │                            │
   │                          │  Check local cache         │
   │                          │  storage/specs/quick/...   │
   │                          │                            │
   │                          │  [Cache miss - first time] │
   │                          │                            │
   │                          │  Proxy to upstream         │
   │                          │─────────────────────────▶  │
   │                          │                            │
   │                          │  Gemspec data              │
   │                          │◀─────────────────────────  │
   │                          │                            │
   │                          │  Cache locally             │
   │                          │  (storage/specs/quick/...) │
   │                          │                            │
   │   Compressed gemspec     │                            │
   │◀─────────────────────────│                            │
   │                          │                            │
   │  Parse dependencies:     │                            │
   │  - actionpack = 7.2.0    │                            │
   │  - activerecord = 7.2.0  │                            │
   │                          │                            │
   ▼                          │                            │
 Add dependencies to
 resolution queue
```

### Flow C: Downloading Gem (On-Demand Tracking)

```
┌─────────────────────────────────────────────────────────────────┐
│                    GEM DOWNLOAD FLOW                             │
└─────────────────────────────────────────────────────────────────┘

Bundler                    GemGuard                   RubyGems.org
   │                          │                            │
   │ GET /gems/               │                            │
   │   rails-7.2.0.gem        │                            │
   │─────────────────────────▶│                            │
   │                          │                            │
   │                          │  1. Parse request          │
   │                          │     name=rails             │
   │                          │     version=7.2.0          │
   │                          │     platform=ruby          │
   │                          │                            │
   │                          │  2. Find or create         │
   │                          │     GemPackage (ON-DEMAND) │
   │                          │     ┌─────────────────┐    │
   │                          │     │ gem_packages    │    │
   │                          │     │ ─────────────── │    │
   │                          │     │ id: 1           │    │
   │                          │     │ name: rails     │    │
   │                          │     │ tracked_at: NOW │◀───┼── First time
   │                          │     └─────────────────┘    │   seeing this
   │                          │                            │   gem!
   │                          │  3. Find or create         │
   │                          │     GemVersion (ON-DEMAND) │
   │                          │     ┌─────────────────┐    │
   │                          │     │ gem_versions    │    │
   │                          │     │ ─────────────── │    │
   │                          │     │ gem_package_id:1│    │
   │                          │     │ version: 7.2.0  │    │
   │                          │     │ status: approved│    │
   │                          │     │ first_seen: NOW │    │
   │                          │     └─────────────────┘    │
   │                          │                            │
   │                          │  4. Check availability     │
   │                          │     version.available? ──▶ │
   │                          │     true (approved)        │
   │                          │                            │
   │                          │  5. Check local cache      │
   │                          │     storage/gems/rails-... │
   │                          │                            │
   │                          │  [Cache miss]              │
   │                          │  6. Proxy to upstream      │
   │                          │─────────────────────────▶  │
   │                          │                            │
   │                          │  .gem file                 │
   │                          │◀─────────────────────────  │
   │                          │                            │
   │                          │  7. Cache locally          │
   │                          │  8. Log to audit_logs      │
   │                          │     ┌─────────────────┐    │
   │                          │     │ audit_logs      │    │
   │                          │     │ ─────────────── │    │
   │                          │     │ action: download│    │
   │                          │     │ gem: rails      │    │
   │                          │     │ version: 7.2.0  │    │
   │                          │     │ ip: 192.168.1.1 │    │
   │                          │     │ time: NOW       │    │
   │                          │     └─────────────────┘    │
   │                          │                            │
   │   .gem file (binary)     │                            │
   │◀─────────────────────────│                            │
   │                          │                            │
   ▼                          │                            │
 Install gem locally
```

### Flow D: Quarantined Gem (Blocked by Specs)

```
┌─────────────────────────────────────────────────────────────────┐
│              QUARANTINED GEM - NORMAL CASE                       │
│         (Blocked at specs level - Bundler never asks)            │
└─────────────────────────────────────────────────────────────────┘

Scenario: evil-gem 1.0.0 was just published (in quarantine)

Bundler                    GemGuard
   │                          │
   │  GET /specs.4.8.gz       │
   │─────────────────────────▶│
   │                          │
   │   Filtered specs         │  evil-gem 1.0.0 is in
   │   (evil-gem NOT included)│  quarantined_versions
   │◀─────────────────────────│  so it's EXCLUDED
   │                          │
   │  Gemfile has:            │
   │  gem "evil-gem"          │
   │                          │
   │  Resolution:             │
   │  - evil-gem 1.0.0? NO    │
   │    (not in specs!)       │
   │  - evil-gem 0.9.0? YES   │
   │    (in specs, safe)      │
   │                          │
   │  Resolves to 0.9.0       │
   │                          │
   ▼                          │
 Developer gets safe
 version without knowing
 1.0.0 even exists!

```

### Flow E: Edge Case - Direct Request for Quarantined Gem

```
┌─────────────────────────────────────────────────────────────────┐
│           QUARANTINED GEM - EDGE CASE                            │
│      (Someone manually requests quarantined version)             │
└─────────────────────────────────────────────────────────────────┘

Scenario: Gemfile.lock has evil-gem 1.0.0 pinned from before quarantine

Bundler                    GemGuard
   │                          │
   │ GET /gems/               │
   │   evil-gem-1.0.0.gem     │
   │─────────────────────────▶│
   │                          │
   │                          │  1. Find/create records │
   │                          │
   │                          │  2. Check availability  │
   │                          │     - QuarantinedVersion│
   │                          │       .quarantined?     │
   │                          │       ("evil-gem",      │
   │                          │        "1.0.0") = TRUE  │
   │                          │
   │                          │  3. version.available?  │
   │                          │     = FALSE             │
   │                          │
   │   404 Not Found          │
   │◀─────────────────────────│
   │                          │
   ▼                          │
 Bundle install fails
 (gem not available)

 Developer must either:
 - Wait for quarantine to end
 - Manually approve in admin UI
 - Use older version
```

---

## Part 5: Background Jobs Timeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    BACKGROUND JOBS SCHEDULE                      │
└─────────────────────────────────────────────────────────────────┘

Time ──────────────────────────────────────────────────────────────▶

Every 10 minutes:
├─ SyncSpecsJob (type: :latest)
│  - Download latest_specs.4.8.gz
│  - Diff against previous
│  - Track NEW versions in quarantined_versions
│  - Build filtered specs
│
Every 1 hour:
├─ SyncSpecsJob (type: :prerelease)
│  - Same as above for prereleases
│
├─ CleanupQuarantinedVersionsJob
│  - Delete expired entries (older than 72h)
│  - Keeps table small (~6k rows max)
│
Every 6 hours:
├─ SyncSpecsJob (type: :all)
│  - Full specs sync
│  - Catches anything missed
│
Every 5 minutes:
├─ ApproveExpiredQuarantineJob
   - Find GemVersion records with status=quarantined
   - If published_at > 72.hours.ago: update to approved
   - (Only matters for gems that were actually requested)
```

---

## Part 6: Database State Examples

### After Fresh Install (Baseline Import Only)

```sql
-- gem_packages: EMPTY (correct!)
SELECT COUNT(*) FROM gem_packages;
-- 0

-- gem_versions: EMPTY (correct!)
SELECT COUNT(*) FROM gem_versions;
-- 0

-- quarantined_versions: EMPTY (no new gems yet)
SELECT COUNT(*) FROM quarantined_versions;
-- 0

-- Storage files exist:
-- storage/specs/raw/specs.4.8.gz (from RubyGems)
-- storage/specs/raw/latest_specs.4.8.gz
-- storage/specs/raw/prerelease_specs.4.8.gz
-- storage/specs/specs.4.8.gz (copy, for serving)
-- storage/specs/latest_specs.4.8.gz
-- storage/specs/prerelease_specs.4.8.gz
```

### After Some Gems Published + Synced

```sql
-- quarantined_versions: New gems in quarantine
SELECT * FROM quarantined_versions;
-- id | name        | version | platform | first_seen_at
-- 1  | new-gem     | 1.0.0   | ruby     | 2024-01-15 10:00:00
-- 2  | other-gem   | 2.5.0   | ruby     | 2024-01-15 10:00:00
-- 3  | evil-gem    | 1.0.0   | ruby     | 2024-01-15 14:30:00

-- gem_packages: Still empty (no one requested these yet)
SELECT COUNT(*) FROM gem_packages;
-- 0
```

### After `bundle install` in a Project

```sql
-- gem_packages: Only gems that were actually requested
SELECT * FROM gem_packages;
-- id | name     | tracked_at          | downloads_count
-- 1  | rails    | 2024-01-15 15:00:00 | NULL
-- 2  | sidekiq  | 2024-01-15 15:00:00 | NULL
-- 3  | nokogiri | 2024-01-15 15:00:00 | NULL
-- 4  | puma     | 2024-01-15 15:00:00 | NULL

-- gem_versions: Only versions that were requested
SELECT gv.*, gp.name FROM gem_versions gv
JOIN gem_packages gp ON gv.gem_package_id = gp.id;
-- id | gem_package_id | version | status   | name
-- 1  | 1              | 7.2.0   | approved | rails
-- 2  | 2              | 7.3.0   | approved | sidekiq
-- 3  | 3              | 1.16.0  | approved | nokogiri
-- 4  | 4              | 6.4.0   | approved | puma

-- audit_logs: Record of all downloads
SELECT * FROM audit_logs WHERE action = 'download';
-- id | gem_name | version | action   | ip_address    | requested_at
-- 1  | rails    | 7.2.0   | download | 192.168.1.100 | 2024-01-15 15:00:01
-- 2  | sidekiq  | 7.3.0   | download | 192.168.1.100 | 2024-01-15 15:00:02
-- ...
```

---

## Part 7: Security Protection Timeline

### Attack Scenario: Supply Chain Compromise

```
┌─────────────────────────────────────────────────────────────────┐
│                WITHOUT GEMGUARD                                  │
└─────────────────────────────────────────────────────────────────┘

Day 0, 10:00 AM - Attacker compromises maintainer account
Day 0, 10:05 AM - Publishes malicious colors-gem 2.0.0
Day 0, 10:10 AM - Your CI runs bundle install
Day 0, 10:11 AM - Malicious code installed and executed
Day 0, 10:12 AM - Credentials exfiltrated, backdoor installed

                  ⚠️ COMPROMISED IN 12 MINUTES ⚠️


┌─────────────────────────────────────────────────────────────────┐
│                 WITH GEMGUARD                                    │
└─────────────────────────────────────────────────────────────────┘

Day 0, 10:00 AM - Attacker compromises maintainer account
Day 0, 10:05 AM - Publishes malicious colors-gem 2.0.0
Day 0, 10:10 AM - GemGuard syncs, detects NEW version
                  → Adds to quarantined_versions
                  → Rebuilds filtered specs (excludes 2.0.0)
Day 0, 10:15 AM - Your CI runs bundle install
                  → GemGuard serves filtered specs
                  → colors-gem 2.0.0 NOT in specs
                  → Bundler resolves to colors-gem 1.9.0 (safe)
                  ✅ PROTECTED

Day 1 - Security community discovers attack
Day 1 - RubyGems yanks malicious version
Day 1 - GemGuard admin blocks gem permanently (optional)

Day 3, 10:10 AM - Quarantine would expire...
                  But gem was yanked, so it won't appear
                  Or admin blocked it, so it stays blocked

                  ✅ NEVER COMPROMISED
```

---

## Summary

### Key Concepts

1. **Bundler asks "what exists?" first** - via specs.4.8.gz
2. **Quarantine = exclusion from specs** - gems don't exist to Bundler
3. **On-demand tracking** - database only grows for YOUR gems
4. **Automatic protection** - no manual intervention needed
5. **72-hour window** - enough time for community to detect attacks

### The Two-Tier System

| Tier | Table | Purpose | Size |
|------|-------|---------|------|
| 1 | `quarantined_versions` | Filter specs | ~6k rows (72h window) |
| 2 | `gem_packages` + `gem_versions` | Track YOUR gems | 50-500 packages |

### Request Types

| Request | Creates DB Records? | Quarantine Check |
|---------|---------------------|------------------|
| `/specs.4.8.gz` | No | Yes (at build time) |
| `/quick/...gemspec.rz` | No | No (specs already filtered) |
| `/gems/...gem` | Yes (on-demand) | Yes (double-check) |
