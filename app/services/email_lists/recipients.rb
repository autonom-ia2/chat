# Os destinatários de uma campanha de e-mail com lista (G52, #2760): uma linha de email_campaign_recipients por contato
# que está na lista e pode receber, com contact_id. Molde: CampaignJourney::EmailAudienceRecipients (o público salvo).
#
# Quando: ao escolher a lista no rascunho (EmailLists::CampaignList) e de novo ao agendar, ao mandar agora e no
# agendador, até o primeiro envio (EmailLists::Gate). Depois disso, é o motor de e-mail de sempre: descadastro e
# "não recebe" conferidos na hora de mandar, a checagem de endereço (preflight), a reputação.
#
# Quem entra: contato da conta com a etiqueta da lista, com e-mail e sem ter pedido para não receber (`not_opted_out`).
# Endereço descadastrado, devolvido ou que reclamou (EmailSuppression) entra como `suppressed`, como na planilha. Nunca
# mexe em destinatário já mandado ou com evento.
class EmailLists::Recipients
  BATCH_SIZE = 500
  # A empresa do contato (Contact belongs_to :company vem do Enterprise; a coluna company_id existe nos dois).
  SEM_EMPRESA_OU_COM = 'LEFT JOIN companies ON companies.id = contacts.company_id'.freeze
  # A empresa vem do cadastro da empresa e, sem ele, do campo "empresa" do contato.
  COLUNAS = ['contacts.id', 'contacts.email', 'contacts.name', 'companies.name',
             Arel.sql("contacts.additional_attributes ->> 'company_name'")].freeze

  Candidate = Struct.new(:contact_id, :email, :name, :empresa, keyword_init: true)

  def initialize(campaign)
    @campaign = campaign
    @lista = campaign.email_list
  end

  # Antes do primeiro envio: põe quem entrou na lista e tira o pendente nunca mandado que saiu dela. Sem lista (a
  # campanha deixou de usar uma), tira todos os pendentes nunca mandados: a lista nunca se mistura com a planilha.
  # Idempotente. Quem entrou ganha a checagem de endereço depois do commit. => { added: 2, removed: 1 }
  def sync!
    return { added: 0, removed: 0 } unless syncable?

    removed = remove_stale
    added = add_missing
    @campaign.refresh_counters! if (added + removed).positive?
    ActiveRecord.after_all_transactions_commit { EmailCampaigns::RecipientPreflightJob.enqueue(@campaign.id) } if added.positive?
    { added: added, removed: removed }
  end

  # Há alguém que receberia agora (a campanha ainda sem destinatário pergunta antes de montar): na lista, com e-mail,
  # sem ter pedido para não receber e fora do descadastro e do bloqueio (EmailSuppression). Para no primeiro lote que
  # tiver alguém.
  def candidatos?
    return false if @lista.nil?

    bloqueados = EmailSuppression.suppressed_set_for(@campaign.account)
    @lista.elegiveis.in_batches(of: BATCH_SIZE).any? do |lote|
      lote.pluck(:email).any? { |email| bloqueados.exclude?(email.to_s.strip.downcase) }
    end
  end

  # Quem entra, lote a lote e só com as colunas que o destinatário usa (sem carregar o contato inteiro nem a lista
  # inteira na memória). Pula o endereço já visto: os que a campanha já tem e os repetidos entre contatos.
  def self.each_lote_de_candidatos(lista, vistos = Set.new)
    lista.elegiveis.in_batches(of: BATCH_SIZE) do |lote|
      yield(lote.joins(SEM_EMPRESA_OU_COM).pluck(*COLUNAS).filter_map do |id, email, name, *empresas|
        email = email.to_s.strip.downcase
        next if email.blank? || !vistos.add?(email)

        Candidate.new(contact_id: id, email: email, name: name, empresa: empresas.compact_blank.first.to_s)
      end)
    end
  end

  private

  # Rascunho ou agendada, e nada mandado nem tentado ainda (EmailCampaign#delivery_history?: enviado, falho, evento).
  def syncable?
    (@campaign.draft? || @campaign.scheduled?) && !@campaign.delivery_history?
  end

  # Pendente, nunca mandado, sem evento e fora da lista: a comparação fica no banco.
  def remove_stale
    stale = @campaign.email_campaign_recipients.pending.where(sent_at: nil)
                     .where.not(id: EmailEvent.where(recipient_id: @campaign.email_campaign_recipients.select(:id)).select(:recipient_id))
    stale = stale.where.not(EmailCampaignRecipient.arel_table[:email].lower.in(emails_da_lista.arel)) if @lista
    stale.delete_all
  end

  def emails_da_lista
    @lista.elegiveis.reselect(Arel.sql('lower(trim(contacts.email))'))
  end

  def add_missing
    return 0 if @lista.nil?

    suppressed = EmailSuppression.suppressed_set_for(@campaign.account)
    existing = @campaign.email_campaign_recipients.pluck(:email).to_set(&:downcase)
    added = 0
    self.class.each_lote_de_candidatos(@lista, existing) do |novos|
      next if novos.empty?

      # Outro processo pode ter posto o mesmo endereço: pula (índice único), nunca quebra.
      added += EmailCampaignRecipient.insert_all( # rubocop:disable Rails/SkipsModelValidations
        novos.map { |candidate| attributes(candidate, suppressed) }, unique_by: :idx_email_campaign_recipients_campaign_email
      ).rows.size
    end
    added
  end

  def attributes(candidate, suppressed)
    now = Time.current
    {
      email_campaign_id: @campaign.id, contact_id: candidate.contact_id, email: candidate.email, name: candidate.name.presence,
      custom_data: { 'primeiro_nome' => candidate.name.to_s.split.first.to_s, 'empresa' => candidate.empresa },
      status: EmailCampaignRecipient.statuses[suppressed.include?(candidate.email) ? :suppressed : :pending],
      created_at: now, updated_at: now
    }
  end
end
