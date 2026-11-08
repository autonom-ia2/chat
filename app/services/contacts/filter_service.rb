class Contacts::FilterService < FilterService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  def initialize(account, user, params)
    @account = account
    # TODO: Change the order of arguments in FilterService maybe?
    # account, user, params makes more sense
    super(params, user)
  end

  def perform
    validate_query_operator
    @contacts = query_builder(@filters['contacts'])

    {
      contacts: @contacts,
      count: @contacts.count
    }
  end

  def filter_values(query_hash)
    current_val = query_hash['values'][0]
    if query_hash['attribute_key'] == 'phone_number'
      "+#{current_val&.delete('+')}"
    elsif query_hash['attribute_key'] == 'country_code'
      current_val.downcase
    elsif query_hash['attribute_key'] == 'relacao'
      relacao_value(query_hash['values'])
    else
      current_val.is_a?(String) ? current_val.downcase : current_val
    end
  end

  def base_relation
    @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
  end

  def filter_config
    {
      entity: 'Contact',
      table_name: 'contacts'
    }
  end

  private

  # Este contato é (#2084/#2085): a tela manda um nome ("parceiro"); a coluna guarda o número do enum. Só com a flag
  # contato_relacao, e um valor só (o filtro é `=`, não `IN`): o resto dá InvalidValue em vez de filtrar pela metade.
  def relacao_value(valores)
    nomes = Array.wrap(valores)
    invalido = -> { raise CustomExceptions::CustomFilter::InvalidValue.new(attribute_name: 'relacao') }
    invalido.call unless nomes.one? && ::Crm::Relacao.ligada?(@account)

    Contact.defined_enums.fetch('relacao').fetch(nomes.first.to_s.downcase) { invalido.call }
  end

  def equals_to_filter_string(filter_operator, current_index)
    return "= :value_#{current_index}" if filter_operator == 'equal_to'

    "!= :value_#{current_index}"
  end
end
