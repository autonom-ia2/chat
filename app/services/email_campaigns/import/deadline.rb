# A monotonic deadline for the import flow (#1099, delivery B): the job's 90 seconds, sliced for the address (15 s) and
# the images (30 s), and handed to SafeFetch as `total_timeout:` so no single download can outlive the job.
class EmailCampaigns::Import::Deadline
  def initialize(seconds, clock: nil)
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    @ends_at = @clock.call + seconds
  end

  def remaining
    [@ends_at - @clock.call, 0].max
  end

  def expired?
    remaining <= 0
  end

  def check!
    raise EmailCampaigns::Import::Error, :too_slow if expired?
  end

  # A shorter deadline inside this one.
  def slice(seconds)
    self.class.new([seconds, remaining].min, clock: @clock)
  end
end
