require "test_helper"

class RegenerateFilteredSpecsJobTest < ActiveJob::TestCase
  setup do
    @specs_dir = Rails.root.join("storage", "specs")
    @raw_specs_dir = @specs_dir.join("raw")
    FileUtils.mkdir_p(@raw_specs_dir)

    # Create sample raw specs
    @sample_specs = [
      ["rails", Gem::Version.new("7.0.0"), "ruby"],
      ["rails", Gem::Version.new("7.1.0"), "ruby"],
      ["nokogiri", Gem::Version.new("1.15.0"), "ruby"]
    ]

    save_raw_specs(:all, @sample_specs)
  end

  teardown do
    FileUtils.rm_rf(@specs_dir)
  end

  test "regenerates filtered specs without quarantined versions" do
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")

    RegenerateFilteredSpecsJob.perform_now(type: :all)

    filtered_specs = load_filtered_specs(:all)
    gem_names_versions = filtered_specs.map { |n, v, _| [n, v.to_s] }

    assert_includes gem_names_versions, ["rails", "7.0.0"]
    assert_not_includes gem_names_versions, ["rails", "7.1.0"]
    assert_includes gem_names_versions, ["nokogiri", "1.15.0"]
  end

  test "regenerates filtered specs without blocked versions" do
    gem_package = create(:gem_package, name: "rails")
    create(:gem_version, :blocked, gem_package: gem_package, version: "7.1.0", platform: "ruby")

    RegenerateFilteredSpecsJob.perform_now(type: :all)

    filtered_specs = load_filtered_specs(:all)
    gem_names_versions = filtered_specs.map { |n, v, _| [n, v.to_s] }

    assert_includes gem_names_versions, ["rails", "7.0.0"]
    assert_not_includes gem_names_versions, ["rails", "7.1.0"]
  end

  test "does nothing when no raw specs exist" do
    FileUtils.rm_rf(@raw_specs_dir)

    assert_nothing_raised do
      RegenerateFilteredSpecsJob.perform_now(type: :all)
    end
  end

  private

  def save_raw_specs(type, specs)
    filename = {
      all: "specs.4.8.gz",
      latest: "latest_specs.4.8.gz",
      prerelease: "prerelease_specs.4.8.gz"
    }[type]

    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)
    gz.write(Marshal.dump(specs))
    gz.close

    File.binwrite(@raw_specs_dir.join(filename), io.string)
  end

  def load_filtered_specs(type)
    filename = {
      all: "specs.4.8.gz",
      latest: "latest_specs.4.8.gz",
      prerelease: "prerelease_specs.4.8.gz"
    }[type]

    path = @specs_dir.join(filename)
    return [] unless File.exist?(path)

    data = File.binread(path)
    gz = Zlib::GzipReader.new(StringIO.new(data))
    Marshal.load(gz.read)
  end
end
