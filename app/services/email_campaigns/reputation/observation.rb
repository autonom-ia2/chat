# Reserve a monotonically increasing generation before collection, then CAS on publication.
# No Account/state lock or surrounding transaction spans expensive metric queries.
class EmailCampaigns::Reputation::Observation
  attr_reader :generation, :feedback_version, :metrics, :fingerprint

  def initialize(account_id)
    @account_id = account_id
  end

  def collect
    state = EmailReputationState.for_account(@account_id)
    state.with_lock do
      state.update!(observation_generation: state.observation_generation + 1)
      @generation = state.observation_generation
      @feedback_version = state.feedback_version
    end
    collector = EmailCampaigns::Reputation::Metrics.new(@account_id)
    @metrics = collector.call
    @fingerprint = collector.harmful_feedback_fingerprint
    self
  end

  def current?(state)
    generation == state.observation_generation && feedback_version == state.feedback_version
  end
end
