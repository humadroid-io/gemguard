# frozen_string_literal: true

require "test_helper"

class RubygemsDumpImporterTest < ActiveSupport::TestCase
  test "import_sql parses COPY statements for rubygems and versions" do
    sql_content = <<~SQL
      -- PostgreSQL dump
      COPY public.rubygems (id, name, created_at, updated_at) FROM stdin;
      1	rails	2005-01-01 00:00:00	2024-01-01 00:00:00
      2	nokogiri	2008-01-01 00:00:00	2024-01-01 00:00:00
      \\.

      COPY public.versions (id, rubygem_id, number, platform, created_at, indexed) FROM stdin;
      1	1	7.0.0	ruby	2022-01-01 00:00:00	t
      2	1	7.1.0	ruby	2023-01-01 00:00:00	t
      3	2	1.15.0	ruby	2023-06-01 00:00:00	t
      4	2	1.15.0	x86_64-linux	2023-06-01 00:00:00	t
      5	1	6.0.0	ruby	2019-01-01 00:00:00	f
      \\.
    SQL

    Dir.mktmpdir do |tmpdir|
      sql_path = File.join(tmpdir, "test.sql")
      File.write(sql_path, sql_content)

      count = RubygemsDumpImporter.import_sql(sql_path)

      assert_equal 4, count # Only indexed versions

      assert_equal 2, GemPackage.count
      assert GemPackage.exists?(name: "rails")
      assert GemPackage.exists?(name: "nokogiri")

      rails_versions = GemVersion.joins(:gem_package).where(gem_packages: { name: "rails" })
      assert_equal 2, rails_versions.count
      assert rails_versions.all?(&:approved?)

      # Check timestamps are preserved
      rails_7_0 = rails_versions.find_by(version: "7.0.0")
      assert_equal Time.parse("2022-01-01 00:00:00"), rails_7_0.first_seen_at

      # Non-indexed version should not be imported
      refute GemVersion.exists?(version: "6.0.0")
    end
  end

  test "import_sql handles nil platform" do
    sql_content = <<~SQL
      COPY public.rubygems (id, name, created_at, updated_at) FROM stdin;
      1	test-gem	2020-01-01 00:00:00	2024-01-01 00:00:00
      \\.

      COPY public.versions (id, rubygem_id, number, platform, created_at, indexed) FROM stdin;
      1	1	1.0.0	\\N	2022-01-01 00:00:00	t
      \\.
    SQL

    Dir.mktmpdir do |tmpdir|
      sql_path = File.join(tmpdir, "test.sql")
      File.write(sql_path, sql_content)

      RubygemsDumpImporter.import_sql(sql_path)

      version = GemVersion.first
      assert_equal "ruby", version.platform
    end
  end

  test "import_sql skips duplicate versions" do
    gem_package = create(:gem_package, name: "existing-gem")
    create(:gem_version, gem_package: gem_package, version: "1.0.0", status: :blocked)

    sql_content = <<~SQL
      COPY public.rubygems (id, name, created_at, updated_at) FROM stdin;
      1	existing-gem	2020-01-01 00:00:00	2024-01-01 00:00:00
      \\.

      COPY public.versions (id, rubygem_id, number, platform, created_at, indexed) FROM stdin;
      1	1	1.0.0	ruby	2022-01-01 00:00:00	t
      2	1	2.0.0	ruby	2023-01-01 00:00:00	t
      \\.
    SQL

    Dir.mktmpdir do |tmpdir|
      sql_path = File.join(tmpdir, "test.sql")
      File.write(sql_path, sql_content)

      RubygemsDumpImporter.import_sql(sql_path)

      assert_equal 2, GemVersion.count

      # Original blocked version should stay blocked
      original = GemVersion.find_by(version: "1.0.0")
      assert original.blocked?

      # New version should be approved
      new_version = GemVersion.find_by(version: "2.0.0")
      assert new_version.approved?
    end
  end

  test "parse_copy_columns extracts column names" do
    line = "COPY public.versions (id, rubygem_id, number, platform, created_at, indexed) FROM stdin;"
    columns = RubygemsDumpImporter.send(:parse_copy_columns, line)

    assert_equal %w[id rubygem_id number platform created_at indexed], columns
  end
end
