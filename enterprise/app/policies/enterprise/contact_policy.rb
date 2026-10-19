module Enterprise::ContactPolicy
  include Relationships::RecordPermissions

  # Without contact_view the base stays closed (#1849). The contact of a conversation the person sees keeps
  # name, phone and e-mail on screen (they come with the conversation), plus calling, a new message and its origin.
  def index?
    relationship_record_read?
  end

  def active?
    index?
  end

  def search?
    index?
  end

  def filter?
    index?
  end

  def summary?
    index?
  end

  def show?
    index?
  end

  # Calling and a new message act on the conversation's contact: they need a conversation the person operates.
  def contactable_inboxes?
    show? || contact_of_visible_conversation?(for_reading: false)
  end

  def call?
    contactable_inboxes?
  end

  # Origin and linking to a CRM card only show the contact, so reading the conversation is enough.
  def origins?
    show? || contact_of_visible_conversation?(for_reading: true)
  end

  def attach?
    origins?
  end

  def create?
    relationship_record_write?
  end

  def update?
    relationship_record_write?
  end

  def avatar?
    update?
  end

  def destroy_custom_attributes?
    update?
  end

  # Exporting the base left contact_manage in #1845; the migration gave contact_export to roles that had it.
  def export?
    @account_user.permission_granted?('contact_export')
  end

  def destroy?
    @account_user.permission_granted?('contact_delete')
  end

  def import?
    @account_user.custom_role&.permissions&.include?('contact_manage') || super
  end

  private

  def contact_of_visible_conversation?(for_reading:)
    return false unless record.is_a?(Contact)

    Conversations::PermissionFilterService.new(record.conversations, user, account, for_reading: for_reading).perform.exists?
  end
end
