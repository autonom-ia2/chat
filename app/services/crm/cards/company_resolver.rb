class Crm::Cards::CompanyResolver
  PROSPECTING_METADATA_KEY = 'autonomia_prospecting'.freeze
  COMPANY_METADATA_KEY = 'company'.freeze

  class << self
    def for_cards(cards)
      cards = Array(cards).compact
      return {} if cards.empty?

      preload_contact_companies(cards)
      companies = prospecting_companies(cards)
      cards.each_with_object({}) do |card, resolved|
        resolved[card.id] = if prospecting_company_id_present?(card)
                              companies[[card.account_id, prospecting_company_id(card)]]
                            else
                              contact_company(card)
                            end
      end
    end

    def for_card(card)
      for_cards([card])[card.id]
    end

    def payload(company)
      return if company.blank?

      { id: company.id, name: company.name }
    end

    def contact_preload
      associations = { label_taggings: :tag }
      associations[:company] = {} if Contact.reflect_on_association(:company)
      associations
    end

    private

    def prospecting_companies(cards)
      return {} unless defined?(Company)

      ids_by_account = cards.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |card, result|
        company_id = prospecting_company_id(card)
        result[card.account_id] << company_id if company_id.present?
      end

      ids_by_account.each_with_object({}) do |(account_id, company_ids), resolved|
        Company.where(account_id: account_id, id: company_ids.uniq).find_each do |company|
          resolved[[account_id, company.id]] = company
        end
      end
    end

    def preload_contact_companies(cards)
      return unless Contact.reflect_on_association(:company)

      ActiveRecord::Associations::Preloader.new(records: cards, associations: { contact: :company }).call
    end

    def prospecting_company_id(card)
      raw_id = card.metadata.to_h.dig(PROSPECTING_METADATA_KEY, COMPANY_METADATA_KEY, 'id')
      parsed_id = Integer(raw_id, exception: false)
      parsed_id if parsed_id&.positive?
    end

    def prospecting_company_id_present?(card)
      card.metadata.to_h.dig(PROSPECTING_METADATA_KEY, COMPANY_METADATA_KEY, 'id').present?
    end

    def contact_company(card)
      contact = card.contact
      return if contact.blank? || contact.account_id != card.account_id
      return unless contact.respond_to?(:company)

      company = contact.company
      company if company&.account_id == card.account_id
    end
  end
end
