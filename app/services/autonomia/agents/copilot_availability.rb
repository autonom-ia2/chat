class Autonomia::Agents::CopilotAvailability
  BOOLEAN = ActiveModel::Type::Boolean.new

  Result = Struct.new(:available, :reasons, :can_choose_internal, keyword_init: true)

  def initialize(account:)
    @account = account
  end

  def call
    gates = {
      crm: ::Crm::Config.enabled?,
      autonomia: ::Autonomia::Agents::Config.enabled?(@account),
      copilot: BOOLEAN.cast(ENV.fetch('CRM_COPILOT_ENABLED', false)),
      crm_ai: ::Crm::Ai::Config.enabled?
    }
    reasons = gates.filter_map { |name, enabled| name unless enabled }
    available = reasons.empty?

    Result.new(available: available, reasons: reasons, can_choose_internal: available)
  end
end
