# GemGuard

A self-hosted security proxy for RubyGems that protects against supply chain attacks and helps achieve SOC2 compliance.

## Code Style

Always use the `dhh-ruby-style` skill when writing Ruby code.

## Architecture

- Rails 8.1 with SQLite
- Hotwire (Turbo + Stimulus) for frontend
- Docker + Kamal for deployment

## Key Concepts

- **Transparent Proxy**: Acts as a drop-in replacement gem source for Bundler
- **Quarantine System**: Holds new gem versions before making them available
- **Local Caching**: Caches all gems for offline use and reproducibility
- **Audit Logging**: Tracks all gem installations for compliance
