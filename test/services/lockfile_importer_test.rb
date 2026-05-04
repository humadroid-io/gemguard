require "test_helper"

class LockfileImporterTest < ActiveJob::TestCase
  test "import approves lockfile version and removes matching quarantine row" do
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")

    assert_difference "GemVersion.count", 1 do
      LockfileImporter.import(lockfile_for("rails", "7.1.0"))
    end

    version = GemPackage.find_by!(name: "rails").versions.find_by!(version: "7.1.0", platform: "ruby")
    assert version.approved?
    assert_not QuarantinedVersion.exists?(name: "rails", version: "7.1.0", platform: "ruby")
  end

  test "import does not unblock blocked existing version" do
    gem_package = create(:gem_package, name: "rails")
    version = create(:gem_version, :blocked, gem_package: gem_package, version: "7.1.0", platform: "ruby")
    create(:quarantined_version, name: "rails", version: "7.1.0", platform: "ruby")

    LockfileImporter.import(lockfile_for("rails", "7.1.0"))

    assert version.reload.blocked?
    assert QuarantinedVersion.exists?(name: "rails", version: "7.1.0", platform: "ruby")
  end

  private

  def lockfile_for(name, version)
    <<~LOCKFILE
      GEM
        specs:
          #{name} (#{version})
    LOCKFILE
  end
end
