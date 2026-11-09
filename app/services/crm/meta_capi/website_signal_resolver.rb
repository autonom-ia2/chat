# Resolves the Meta browser signals of a card that came from a website button (#1011).
#
# The landing page sends fbc/fbp/IP/user agent with the click (POST /l/:code/clicks),
# only when the visitor gave marketing consent. Ctwa::TrackedLinkAttributor later ties
# that click to the conversation. Here we look for the most recent click with signals
# among the card's conversations (primary + linked) and return them as Meta user_data.
#
# `up_to` keeps only the clicks made by that instant (#2799), the same cut as the WhatsApp
# click (#2738): a website click after the sale did not bring it.
#
# Returns {} when there is nothing to send (no website click, or no consent).
module Crm::MetaCapi::WebsiteSignalResolver
  module_function

  SIGNAL_KEYS = %w[fbc fbp client_ip_address client_user_agent].freeze

  def resolve(card, up_to: nil)
    conversation_ids = conversation_ids_for(card)
    return {} if conversation_ids.empty?

    click = clicks(card, conversation_ids, up_to)
            .where.not(meta_signals: {})
            .order(created_at: :desc, id: :desc)
            .first
    return {} if click.blank?

    click.meta_signals.to_h.slice(*SIGNAL_KEYS).select { |_key, value| value.is_a?(String) && value.present? }
  end

  # Whether a website button click, with or without signals, is tied to the card by `up_to`.
  def website_click?(card, up_to: nil)
    conversation_ids = conversation_ids_for(card)
    conversation_ids.any? && clicks(card, conversation_ids, up_to).joins(:tracked_link).exists?(ctwa_tracked_links: { usage: 'website' })
  end

  # The website clicks tied to the card conversations, only those made by `up_to` when given.
  def clicks(card, conversation_ids, up_to = nil)
    scope = Ctwa::TrackedLinkClick.where(account_id: card.account_id, conversation_id: conversation_ids)
    up_to ? scope.where(created_at: ..up_to) : scope
  end

  def conversation_ids_for(card)
    return [] if card.blank?

    linked = Crm::CardConversation.where(account_id: card.account_id, card_id: card.id).pluck(:conversation_id)
    ([card.conversation_id] + linked).compact.uniq
  end
end
