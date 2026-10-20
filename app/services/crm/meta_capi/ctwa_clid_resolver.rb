# Resolves the ctwa_clid (Click-to-WhatsApp click id) that attributes a card back to a
# Meta ad click. Written by Ctwa::CampaignBuilder onto each conversation: the `campaign`
# origin holds the first touch, `campaign_touches` the later clicks, each with `touched_at`.
#
# A card has a primary conversation and linked ones, possibly in different inboxes
# (#1940): a client who comes back through another number lands in a linked
# conversation while the primary stays the old one. So the clid is searched in all of
# them, and the most recent click wins (its `touched_at`, else the conversation start),
# inside a conversation too: the origin is the FIRST click, so a later touch beats it.
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

  # The newest click of the conversation, among the origin and the later touches. Touches
  # are appended in order, so a tie (missing touched_at) goes to the later one.
  def source_for(conversation)
    attrs = conversation.additional_attributes || {}
    clicks = [attrs['campaign'], *Array(attrs['campaign_touches'])].select { |touch| touch.is_a?(Hash) && touch['ctwa_clid'].present? }
    return if clicks.empty?

    newest = clicks.each_with_index.max_by { |touch, index| [clicked_at(touch, conversation).to_f, index] }.first
    Source.new(conversation: conversation, ctwa_clid: newest['ctwa_clid'], clicked_at: clicked_at(newest, conversation))
  end

  def clicked_at(touch, conversation)
    Time.zone.parse(touch['touched_at'].to_s) || conversation.created_at
  rescue ArgumentError
    conversation.created_at
  end
end
