require "test_helper"

class ApproveExpiredQuarantineJobTest < ActiveJob::TestCase
  include FactoryBot::Syntax::Methods

  test "approves gems past quarantine period" do
    package = create(:gem_package)
    expired_gem = create(:gem_version,
      gem_package: package,
      status: :quarantined,
      first_seen_at: 4.days.ago)

    ApproveExpiredQuarantineJob.perform_now

    assert expired_gem.reload.approved?
    assert_not QuarantinedVersion.exists?(name: package.name, version: expired_gem.version, platform: expired_gem.platform)
  end

  test "does not approve gems still in quarantine period" do
    package = create(:gem_package)
    recent_gem = create(:gem_version,
      gem_package: package,
      status: :quarantined,
      published_at: 1.hour.ago,
      first_seen_at: 1.hour.ago)

    ApproveExpiredQuarantineJob.perform_now

    assert recent_gem.reload.quarantined?
  end

  test "does not affect already approved gems" do
    package = create(:gem_package)
    approved_gem = create(:gem_version,
      gem_package: package,
      status: :approved,
      first_seen_at: 1.day.ago)

    ApproveExpiredQuarantineJob.perform_now

    assert approved_gem.reload.approved?
  end

  test "does not affect blocked gems" do
    package = create(:gem_package)
    blocked_gem = create(:gem_version,
      gem_package: package,
      status: :blocked,
      first_seen_at: 4.days.ago)

    ApproveExpiredQuarantineJob.perform_now

    assert blocked_gem.reload.blocked?
  end

  test "approves multiple expired gems" do
    package = create(:gem_package)
    expired_gems = 3.times.map do |i|
      create(:gem_version,
        gem_package: package,
        version: "1.0.#{i}",
        status: :quarantined,
        first_seen_at: (4 + i).days.ago)
    end

    ApproveExpiredQuarantineJob.perform_now

    expired_gems.each { |gem| assert gem.reload.approved? }
  end
end
