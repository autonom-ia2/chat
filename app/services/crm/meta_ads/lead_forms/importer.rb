# Um lead do formulário instantâneo do anúncio (#2195) vira contato e card no funil e na etapa escolhidos, com a origem
# (formulário, anúncio, campanha) e as respostas em metadata['meta_lead_form'], que o card mostra (OrigemAnuncioMeta).
#
# - O lead é reservado pelo leadgen_id antes de tudo, na mesma transação do card: o webhook repetido, ou o "trazer os
#   antigos" depois do webhook, devolve :duplicate sem criar nada.
# - O contato é o mesmo quando o telefone (E.164) ou o e-mail já existe na conta.
# - Quem já tem card aberto naquele funil não ganha outro (:existing_card); o lead fica ligado ao card que já existe.
# - Card criado pelo sistema: sem usuário, dono pela regra do Crm::Cards::Creator. O título é o nome que a pessoa
#   escreveu, se não parecer e-mail nem telefone; sem ele, o nome do formulário; sem os dois, "Lead <id>". Nunca
#   telefone nem e-mail: o título e o nome do contato vão à IA (Decisor, IA de etapa) e a quem não vê o contato.
# - E-mail que o contato não aceita fica só nas respostas; o lead entra do mesmo jeito.
# - Lead que não dá para gravar (:failed) vai para o rastreador de erros e não para os outros do mesmo lote. A recusa
#   fica lembrada em `refused` (RefusedLeads, #2740), quando quem chama passa um, com o tipo dela (#2804): do próprio
#   lead, do destino (funil ou etapa) ou passageira (corrida no banco). O tipo diz quando a reconciliação tenta de novo.
class Crm::MetaAds::LeadForms::Importer
  SOURCE = 'meta_lead_form'.freeze
  # O que o card recebe do lead e não do destino: recusa só nesses campos é do lead.
  LEAD_CARD_ATTRIBUTES = %i[title metadata contact].freeze
  # Corrida com outro processo, prazo do banco ou conexão caída: some na próxima tentativa.
  TRANSIENT_ERRORS = [ActiveRecord::RecordNotUnique, ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout,
                      ActiveRecord::QueryCanceled, ActiveRecord::ConnectionFailed].freeze
  NAME_KEYS = %w[full_name first_name last_name].freeze
  PHONE_KEY = 'phone_number'.freeze
  EMAIL_KEY = 'email'.freeze
  E164_DIGITS = (8..15)

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, pipeline:, stage:, form_name:, page_id: nil, questions: [], refused: nil)
    @account = account
    @refused = refused
    @page_id = page_id
    @pipeline = pipeline
    @stage = stage
    @form_name = form_name
    @labels = Array(questions).each_with_object({}) { |question, labels| labels[question['key'].to_s] = question['label'] }
  end
  # rubocop:enable Metrics/ParameterLists

  def import(lead)
    ActiveRecord::Base.transaction(requires_new: true) do
      record = claim!(lead)
      next :duplicate if record.nil?

      phone = e164(answer(lead, PHONE_KEY))
      email = answer(lead, EMAIL_KEY).presence
      lock_person!(phone || email&.downcase)
      contact, new_contact = find_or_create_contact(lead, phone, email)
      card = open_card_for(contact)
      outcome = card ? :existing_card : :created
      card ||= create_card(lead, contact)
      record.update!(contact: contact, card: card, new_contact: new_contact)
      outcome
    end
  rescue ActiveRecord::RecordInvalid => e
    refused!(lead, e, refusal_kind(e.record))
  rescue *TRANSIENT_ERRORS => e
    refused!(lead, e, :transient)
  rescue ActiveRecord::StatementInvalid => e
    # Outra recusa do banco (ex.: um caractere que o Postgres não grava) vem do dado do lead.
    refused!(lead, e, :lead)
  end

  private

  def refused!(lead, error, kind)
    ChatwootExceptionTracker.new(error, account: @account).capture_exception
    @refused&.remember!(lead['id'], kind)
    :failed
  end

  # Unicidade (:taken) é o contato que outro processo gravou no mesmo instante: passageira. O card recusado por outro
  # campo que não os do lead, ou sem dizer o campo, é do destino (funil, etapa, dono). O resto (o contato, a linha do
  # lead) é do lead.
  def refusal_kind(record)
    errors = record.errors
    return :transient if errors.details.values.flatten.any? { |detail| detail[:error] == :taken }
    return :lead unless record.is_a?(Crm::Card)

    names = errors.attribute_names
    names.any? && (names - LEAD_CARD_ATTRIBUTES).empty? ? :lead : :destination
  end

  # Reserva o lead no seu próprio savepoint: só o índice único do leadgen_id vira :duplicate; qualquer outra recusa do
  # banco no contato ou no card sobe como erro.
  def claim!(lead)
    Crm::MetaAdsLead.transaction(requires_new: true) do
      Crm::MetaAdsLead.create!(
        account: @account, leadgen_id: lead['id'].to_s, page_id: @page_id&.to_s, form_id: lead['form_id'].to_s.presence,
        ad_id: lead['ad_id'].to_s.presence, ad_name: lead['ad_name'].to_s.first(Crm::MetaAdsLead::NAME_LIMIT).presence,
        campaign_name: lead['campaign_name'].to_s.first(Crm::MetaAdsLead::NAME_LIMIT).presence,
        received_at: received_at(lead)
      )
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Dois leads da mesma pessoa ao mesmo tempo (dois formulários, ou o webhook junto do "trazer antigos"): o segundo
  # espera o primeiro terminar e acha o contato e o card que ele criou. Sem telefone nem e-mail não há o que travar.
  def lock_person!(key)
    return if key.nil?

    sql = Crm::MetaAdsLead.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', "crm_meta_ads_lead:#{@account.id}:#{key}"])
    Crm::MetaAdsLead.connection.execute(sql)
  end

  def find_or_create_contact(lead, phone, email)
    existing = (@account.contacts.find_by(phone_number: phone) if phone) || (@account.contacts.from_email(email) if email)
    return [existing, false] if existing

    contact = @account.contacts.new(name: title_name(lead), phone_number: phone, email: email, contact_type: :lead)
    contact.email = nil if !contact.valid? && contact.errors.include?(:email)
    contact.save!
    [contact, true]
  end

  def open_card_for(contact)
    @account.crm_cards.open.where(pipeline_id: @pipeline.id, contact_id: contact.id).order(:id).first
  end

  def create_card(lead, contact)
    Crm::Cards::Creator.new(
      account: @account, user: nil,
      params: { pipeline_id: @pipeline.id, stage_id: @stage.id, contact_id: contact.id, source: SOURCE,
                # #2562: sem nome, nunca o do formulário: ele costuma repetir a campanha e o título todos veem (#2558).
                title: title_name(lead) || "Lead #{lead['id']}",
                metadata: { 'meta_lead_form' => origin(lead) } }
    ).perform
  end

  def origin(lead)
    {
      'leadgen_id' => lead['id'].to_s, 'form_id' => lead['form_id'].to_s, 'form_name' => @form_name,
      'ad_id' => lead['ad_id'], 'ad_name' => lead['ad_name'], 'campaign_name' => lead['campaign_name'],
      'captured_at' => received_at(lead).utc.iso8601, 'fields' => fields(lead)
    }.compact
  end

  def fields(lead)
    field_data(lead).filter_map do |field|
      value = Array(field['values']).join(', ')
      next if value.blank?

      key = field['name'].to_s
      { 'key' => key, 'label' => @labels[key], 'value' => value }.compact
    end
  end

  def field_data(lead)
    Array(lead['field_data']).select { |field| field.is_a?(Hash) }
  end

  def answer(lead, key)
    field_data(lead).find { |field| field['name'] == key }&.dig('values')&.first.to_s.strip
  end

  # Nome que parece e-mail ou telefone (a pessoa digitou o contato no campo do nome) não vai para o título.
  def title_name(lead)
    name = name_of(lead)
    name unless Autonomia::DadoDeContato.contato?(name)
  end

  def name_of(lead)
    full = answer(lead, NAME_KEYS.first)
    return full if full.present?

    NAME_KEYS.drop(1).map { |key| answer(lead, key) }.compact_blank.join(' ').presence
  end

  # Só o número que já vem com o código do país ("+55 11 98765-1201"): sem ele não dá para saber o país, e o número fica
  # só nas respostas do card.
  def e164(value)
    return if value.blank? || !value.start_with?('+')

    digits = value.each_char.select { |char| char.between?('0', '9') }.join
    "+#{digits}" if E164_DIGITS.cover?(digits.length) && !digits.start_with?('0')
  end

  def received_at(lead)
    Time.zone.parse(lead['created_time'].to_s) || Time.current
  rescue ArgumentError
    Time.current
  end
end
