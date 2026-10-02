module Crm::Cards::CompanyFilters
  def apply_company_filter(cards)
    return cards if @params[:company_id].blank? || !company_filter_supported?
    return cards.where("NOT (#{resolved_company_exists_sql})") if @params[:company_id].to_s == 'none'

    company_id = Integer(@params[:company_id], exception: false)
    return cards if company_id.blank? || company_id <= 0

    cards.where(resolved_company_match_sql, company_id, company_id)
  end

  # One search field powers the board and list. Besides the card title it can
  # find the contact and the company that is actually resolved for that card.
  def apply_card_search_filter(cards, raw_search)
    return cards if raw_search.blank?

    search_term = ActiveRecord::Base.sanitize_sql_like(raw_search.to_s.strip.downcase)
    return cards if search_term.blank?

    pattern = "%#{search_term}%"
    predicates = ['LOWER(crm_cards.title) LIKE ?', contact_search_exists_sql]
    binds = [pattern, pattern, pattern, pattern]
    if company_filter_supported?
      predicates << resolved_company_search_sql
      binds.push(pattern, pattern)
    end
    cards.where("(#{predicates.join(' OR ')})", *binds)
  end

  private

  def company_filter_supported?
    defined?(Company)
  end

  def prospecting_company_sql(extra = nil)
    clauses = [
      'filter_prospecting_companies.account_id = crm_cards.account_id',
      "filter_prospecting_companies.id::text = crm_cards.metadata -> 'autonomia_prospecting' -> 'company' ->> 'id'",
      extra
    ].compact.join(' AND ')
    "EXISTS (SELECT 1 FROM companies AS filter_prospecting_companies WHERE #{clauses})"
  end

  def contact_company_sql(extra = nil)
    clauses = [
      'filter_contacts.id = crm_cards.contact_id',
      'filter_contacts.account_id = crm_cards.account_id',
      extra
    ].compact.join(' AND ')
    'EXISTS (SELECT 1 FROM contacts AS filter_contacts INNER JOIN companies AS filter_contact_companies ' \
      'ON filter_contact_companies.id = filter_contacts.company_id ' \
      "AND filter_contact_companies.account_id = crm_cards.account_id WHERE #{clauses})"
  end

  def resolved_company_sql(prospecting_sql, contact_sql)
    "(#{prospecting_sql} OR (NOT (#{prospecting_company_id_present_sql}) AND #{contact_sql}))"
  end

  def resolved_company_exists_sql
    resolved_company_sql(prospecting_company_sql, contact_company_sql)
  end

  def prospecting_company_id_present_sql
    "(crm_cards.metadata -> 'autonomia_prospecting' -> 'company' ->> 'id') IS NOT NULL " \
      "AND (crm_cards.metadata -> 'autonomia_prospecting' -> 'company' ->> 'id') <> ''"
  end

  def resolved_company_match_sql
    resolved_company_sql(
      prospecting_company_sql('filter_prospecting_companies.id = ?'),
      contact_company_sql('filter_contact_companies.id = ?')
    )
  end

  def contact_search_exists_sql
    <<~SQL.squish
      EXISTS (
        SELECT 1 FROM contacts AS filter_search_contacts
        WHERE filter_search_contacts.id = crm_cards.contact_id
          AND filter_search_contacts.account_id = crm_cards.account_id
          AND (
            LOWER(filter_search_contacts.name) LIKE ?
            OR LOWER(filter_search_contacts.phone_number) LIKE ?
            OR LOWER(filter_search_contacts.email) LIKE ?
          )
      )
    SQL
  end

  def resolved_company_search_sql
    resolved_company_sql(
      prospecting_company_sql('LOWER(filter_prospecting_companies.name) LIKE ?'),
      contact_company_sql('LOWER(filter_contact_companies.name) LIKE ?')
    )
  end
end
