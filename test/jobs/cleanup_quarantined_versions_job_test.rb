require "test_helper"

class CleanupQuarantinedVersionsJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  test "destroys expired quarantine entries via callbacks" do
    expired = create(:quarantined_version, :expired, name: "old-gem", version: "1.0.0")

    assert_enqueued_with(job: SyncCompactIndexJob, args: [{type: :versions}]) do
      assert_enqueued_jobs 3, only: RegenerateFilteredSpecsJob do
        CleanupQuarantinedVersionsJob.perform_now
      end
    end

    assert_not QuarantinedVersion.exists?(id: expired.id)
  end
end
