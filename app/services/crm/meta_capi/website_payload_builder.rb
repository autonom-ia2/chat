# Builds one Pixel Conversions API event for a card that came from a website button
# (#1011, docs/crm/ponte-lp-atribuicao.md section 6). The CTWA path keeps using
# Crm::MetaCapi::PayloadBuilder untouched; this one only covers the website mode.
#
# Differences from the CTWA event:
# - action_source 'system_generated' (Meta guidance for CRM stage changes) and no
#   messaging_channel;
# - user_data carries the browser signals the page captured with consent
#   (fbc, fbp, client_ip_address, client_user_agent) instead of ctwa_clid/WABA;
# - its own event map: the page already fires `Lead` when the form is sent, so the
#   'lead' stage sends nothing here, and 'lost' has no website equivalent.
#
# event_time and custom_data follow the CTWA rules (same card, same value), so both
# modes report the same moment and the same amount.
module Crm::MetaCapi::WebsitePayloadBuilder
  module_function

  ACTION_SOURCE = 'system_generated'.freeze
  RESULT_EVENT_NAMES = { 'won' => 'Purchase' }.freeze
  FUNNEL_EVENT_NAMES = {
    'qualified' => 'QualifiedLead',
    'opportunity' => 'AddToCart',
    'negotiation' => 'InitiateCheckout'
  }.freeze

  # Meta event name for the website mode, or nil when this event must not be sent.
  def canonical_event_name(event_type:, stage_type:)
    return RESULT_EVENT_NAMES[event_type] if Crm::MetaCapi::PayloadBuilder::RESULT_EVENT_NAMES.key?(event_type)
    return FUNNEL_EVENT_NAMES[stage_type.to_s] if Crm::MetaCapi::PayloadBuilder::MOVEMENT_EVENT_TYPES.include?(event_type)

    nil
  end

  # signals: the hash from Crm::MetaCapi::WebsiteSignalResolver.
  def build(card:, event_name:, event_type:, event_id:, signals:)
    {
      'event_name' => event_name,
      'event_time' => Crm::MetaCapi::PayloadBuilder.occurred_at(card, event_type).to_i,
      'event_id' => event_id,
      'action_source' => ACTION_SOURCE,
      'user_data' => user_data(signals),
      'custom_data' => Crm::MetaCapi::PayloadBuilder.custom_data(card).presence
    }.compact
  end

  def user_data(signals)
    signals.to_h.slice(*Crm::MetaCapi::WebsiteSignalResolver::SIGNAL_KEYS).compact_blank
  end
end
