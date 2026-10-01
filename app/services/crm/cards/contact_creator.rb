# Creates only the person for an already existing opportunity (M02).
# The caller authorizes the card/contact and validates the request shape first.
class Crm::Cards::ContactCreator
  def initialize(card:, actor:, attributes:)
    @card = card
    @actor = actor
    @attributes = attributes
  end

  def perform
    # Share RelationshipRegistration's account lock before taking the card lock.
    # NO KEY UPDATE preserves compatibility with the idempotency claim's FK lock.
    @card.account.with_lock('FOR NO KEY UPDATE') do
      @card.with_lock do
        if @card.contact_id.present?
          @card.errors.add(:contact, I18n.t('errors.crm.contact_already_linked'))
          raise ActiveRecord::RecordInvalid, @card
        end

        # This is an intentional registration, not an anonymous widget visitor.
        contact = @card.account.contacts.create!(@attributes.merge(contact_type: :lead))
        Crm::Cards::ContactLinker.new(card: @card, contact: contact, actor: @actor).link
      end
    end
  end
end
