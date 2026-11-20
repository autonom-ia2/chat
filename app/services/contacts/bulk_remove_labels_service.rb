class Contacts::BulkRemoveLabelsService
  def initialize(account:, contact_ids:, labels:)
    @account = account
    @contact_ids = Array(contact_ids)
    @labels = Array(labels).compact_blank
  end

  def perform
    return { success: true, updated_contact_ids: [] } if @contact_ids.blank? || @labels.blank?

    updated_contact_ids = []
    # Contact without any of the labels is left untouched, so its updated_at does not move (#3062).
    @account.contacts.where(id: @contact_ids).find_each do |contact|
      next unless contact.label_list.intersect?(@labels)

      contact.update!(label_list: contact.label_list - @labels)
      updated_contact_ids << contact.id
    end

    { success: true, updated_contact_ids: updated_contact_ids }
  end
end
