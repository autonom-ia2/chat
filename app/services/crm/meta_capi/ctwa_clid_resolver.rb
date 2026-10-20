# Resolves the ctwa_clid (Click-to-WhatsApp click id) that attributes a card back to a
# Meta ad click. Written by Ctwa::CampaignBuilder onto each conversation: the `campaign`
# origin holds the first touch, `campaign_touches` the later clicks, each with `touched_at`.
#
# A card has a primary conversation and linked ones, possibly in different inboxes
# (#1940): a client who comes back through another number lands in a linked
# conversation while the primary stays the old one. So the clid is searched in all of
# them, and the most recent click wins (its `touched_at`, else the conversation start).
# Within a conversation the origin clid is preferred over the latest touch.
#
# `sources` also returns each click's conversation, newest first: the event must go out
# through THAT inbox (token, WABA and dataset), or Meta cannot tie the clid to the WABA.
module Crm::MetaCapi::CtwaClidResolver
  module_function

  Source = Struct.new(:conversation, :ctwa_clid, :clicked_at, keyword_init: true)

  def resolve(card)
    sources(card).first&.ctwa_clid
  end

  def sources(card)
    return [] if card.blank?

    [card.primary_conversation, *card.linked_conversations].compact.uniq
                                                           .filter_map { |conversation| source_for(conversation) }
                                                           .sort_by { |source| [-source.clicked_at.to_f, -source.conversation.id] }
  end

  def source_for(conversation)
    attrs = conversation.additional_attributes || {}
    touch = from_campaign(attrs) || from_touches(attrs)
    return if touch.nil?

    Source.new(conversation: conversation, ctwa_clid: touch['ctwa_clid'], clicked_at: clicked_at(touch, conversation))
  end

  def from_campaign(attrs)
    origin = attrs['campaign']
    origin if origin.is_a?(Hash) && origin['ctwa_clid'].present?
  end

  def from_touches(attrs)
    Array(attrs['campaign_touches']).reverse.find { |touch| touch.is_a?(Hash) && touch['ctwa_clid'].present? }
  end

  def clicked_at(touch, conversation)
    Time.zone.parse(touch['touched_at'].to_s) || conversation.created_at
  rescue ArgumentError
    conversation.created_at
  end
end
