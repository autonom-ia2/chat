# The inboxes a pending invitation puts the person in, applied when it is accepted: the existing inboxes chosen in the
# invitation and, when asked, a new WhatsApp API inbox connected later by the person (#1931 moved it out of
# Provisioner). Who may still do this is checked by InvitationAccess#inboxes_allowed?.
class Autonomia::Sso::InvitationInboxes
  def initialize(account, pending_invitation, user)
    @account = account
    @invitation = pending_invitation
    @user = user
  end

  # Returns the WhatsApp inbox created for the person, if any.
  def apply!
    assign_existing_inboxes!
    create_whatsapp_api_inbox!
  end

  private

  def assign_existing_inboxes!
    inbox_ids = Array(@invitation['inbox_ids']).filter_map { |value| Integer(value.to_s, 10, exception: false) }.uniq

    @account.inboxes.where(id: inbox_ids).find_each do |inbox|
      InboxMember.find_or_create_by!(inbox: inbox, user: @user)
    end
  end

  def create_whatsapp_api_inbox!
    return unless ActiveModel::Type::Boolean.new.cast(@invitation['create_whatsapp_api_inbox'])

    inbox = Waha::InboxProvisioner.new(
      account: @account,
      phone: @invitation['whatsapp_api_phone'],
      display_name: @user.name,
      api_access_token: api_access_token
    ).perform.inbox

    InboxMember.find_or_create_by!(inbox: inbox, user: @user)
    mark_invite_connection_pending!(inbox)
    inbox
  end

  def api_access_token
    token_owner = User.find_by(id: @invitation['invited_by_user_id']) || @user
    (token_owner.access_token || token_owner.create_access_token).token
  end

  def mark_invite_connection_pending!(inbox)
    channel = inbox.channel
    attrs = (channel.additional_attributes || {}).to_h
    channel.update!(
      additional_attributes: attrs.merge(
        'autonomia_invite_connection' => { 'user_id' => @user.id, 'status' => 'pending', 'created_at' => Time.current.iso8601 }
      )
    )
  end
end
