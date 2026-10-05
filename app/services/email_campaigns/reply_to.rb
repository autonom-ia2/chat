# Reply-To of an email campaign (#999, PRD §6.9 and §8.9, acceptance L5). Used by the domain
# (SES) send, the direct inbox send and the test send, so the three always agree.
#
# Order:
#   1. the campaign's "Respostas vão para a caixa X" (reply_to_inbox) → that inbox's address;
#   2. the campaign's typed reply_to address (old side form);
#   3. the verified domain's reply-to inbox (sender identity reply_to_inbox_id, SES only);
#   4. the sender address (domain from_email, or the inbox address in direct mode).
#
# A reply to the inbox address reaches Chatwoot through that email inbox (forwarding or IMAP) and
# becomes a conversation there, with the contact found by the sender's email.
class EmailCampaigns::ReplyTo
  def self.for(campaign)
    new(campaign).address
  end

  def initialize(campaign)
    @campaign = campaign
  end

  def address
    inbox_address(@campaign.reply_to_inbox) || @campaign.reply_to.presence || identity_inbox_address || sender_address
  end

  private

  def identity_inbox_address
    identity = @campaign.sender_identity
    return if @campaign.direct_inbox? || identity&.reply_to_inbox_id.blank?

    inbox_address(@campaign.account.inboxes.find_by(id: identity.reply_to_inbox_id))
  end

  def inbox_address(inbox)
    return unless inbox&.account_id == @campaign.account_id && inbox.channel.is_a?(Channel::Email)

    inbox.channel.email.to_s.strip.downcase.presence
  end

  def sender_address
    return @campaign.from_email.presence if @campaign.direct_inbox?

    @campaign.sender_identity&.from_email.presence
  end
end
