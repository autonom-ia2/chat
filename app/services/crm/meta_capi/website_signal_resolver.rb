# Resolves the Meta browser signals of a card that came from a website button (#1011).
#
# The landing page sends fbc/fbp/IP/user agent with the click (POST /l/:code/clicks),
# only when the visitor gave marketing consent. Ctwa::TrackedLinkAttributor later ties
# that click to the conversation. Here we look for the most recent click with signals
# among the card's conversations (primary + linked) and return them as Meta user_data.
#
# Returns {} when there is nothing to send (no website click, or no consent).
module Crm::MetaCapi::WebsiteSignalResolver
  module_function

  SIGNAL_KEYS = %w[fbc fbp client_ip_address client_user_agent].freeze

  def resolve(card)
    conversation_ids = conversation_ids_for(card)
    return {} if conversation_ids.empty?

    click = Ctwa::TrackedLinkClick
            .where(account_id: card.account_id, conversation_id: conversation_ids)
            .where.not(meta_signals: {})
            .order(created_at: :desc, id: :desc)
            .first
    return {} if click.blank?

    click.meta_signals.to_h.slice(*SIGNAL_KEYS).select { |_key, value| value.is_a?(String) && value.present? }
  end

  def conversation_ids_for(card)
    return [] if card.blank?

    linked = Crm::CardConversation.where(account_id: card.account_id, card_id: card.id).pluck(:conversation_id)
    ([card.conversation_id] + linked).compact.uniq
  end
end
