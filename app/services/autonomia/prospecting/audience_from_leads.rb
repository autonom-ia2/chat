# "Guardar para mandar mensagem" da Prospecção nova (#2695, F3b): os leads escolhidos viram um Público de Campanhas
# (CampaignImport do fluxo audience, source 'prospecting'), gravado pelo CampaignJourney::AudienceWriter, o mesmo do
# Público por conversa. Substitui o segmento por etiqueta da Prospecção, que saiu (#2695).
#
# - Contato e empresa saem do ContactConverter (que chama o CompanyUpserter), um lead por vez e cada um na própria
#   transação, como o "Criar contatos" (ContactBatch): com decisor, o contato é a pessoa; sem decisor, a empresa, com o
#   mesmo nome; o contato fica ligado à empresa.
# - Fica de fora, com o motivo e sem gravar contato: lead que não existe ou que a pessoa não vê (not_found), o
#   descartado, o que recusou ou cujo contato recusou ou está bloqueado (SegmentEligibility#consent_block_reason), e
#   quem não teria telefone nem e-mail no contato (no_channel, pela mesma regra do conversor: ContactConverter#channel?).
# - Depois do contato vale a régua de todo Público (ConversationAudience::Reach): telefone OU e-mail do contato, e
#   nunca quem pediu para não receber. O contato que ainda assim fica sem canal (o telefone já era de outro contato)
#   sai com no_channel; ele continua criado, como no "Criar contatos". O bloqueado sai com blocked e qualquer outro
#   motivo da régua, com unreachable: nenhum contato que a régua recusa entra no Público.
# - Id que não é número (texto, "0x1A", negativo) não some: sai como not_found, para a tela contar. O vazio e o teto
#   contam o pedido como veio, antes desse filtro.
# - Dois leads que dão no mesmo contato (a mesma pessoa em duas empresas) entram uma vez: o primeiro, na ordem do
#   pedido; o outro sai com same_contact, e fica ligado ao mesmo contato (lead.contact) pelo conversor, porque é a
#   mesma pessoa.
# - Isolamento por lead, de propósito: a falha de um lead (dado recusado ou erro inesperado) fica só nele, em left_out,
#   e os outros entram. Um lead ruim não derruba o pedido inteiro.
# - Lista que já existe (#2775, F6): Autonomia::Prospecting::LeadsIntoAudience, a subclasse que usa este mesmo caminho
#   e troca só o alvo (check_target!, members, no_rows_code e finish).
# - O Público é gravado de uma vez, no fim. Recusa do writer (contato apagado no meio, por exemplo) vira Error com o
#   mesmo código e contacts_saved: os contatos já criados ficam.
class Autonomia::Prospecting::AudienceFromLeads
  # Teto do pedido, síncrono: 100 leads levaram 4,2 s no teste local (método e tempos de 100, 200 e 500 em
  # docs/audit/2026-11-08-prospeccao-publico-teto.md). O front (LIMITE_DO_PUBLICO) usa o mesmo número.
  MAX_LEADS = 100
  SOURCE = 'prospecting'.freeze
  NO_CHANNEL = 'no_channel'.freeze
  # O motivo da régua de todo Público (ConversationAudience::Reach.reason_for) vira o código de left_out. Motivo que o
  # mapa não conhece nunca deixa o contato entrar calado: sai como UNREACHABLE. 'bloqueado' é o motivo que a #2733 cria
  # (ConversationAudience::Reach::BLOCKED); fica como texto até a constante chegar à main.
  REACH_REASONS = {
    ConversationAudience::Reach::OPTED_OUT => 'opt_out',
    ConversationAudience::Reach::NO_CONTACT => NO_CHANNEL,
    'bloqueado' => 'blocked'
  }.freeze
  UNREACHABLE = 'unreachable'.freeze

  # channels_off: só na lista que já existe (LeadsIntoAudience), os canais desligados que ganharam gente.
  Result = Struct.new(:audience, :entered_lead_ids, :left_out, :channels_off, keyword_init: true)

  # Recusa do pedido inteiro. left_out: quem ficou de fora e por quê, para a tela explicar mesmo quando ninguém entra.
  # contacts_saved: a recusa veio depois de criar os contatos (eles ficam gravados).
  class Error < StandardError
    attr_reader :left_out, :contacts_saved

    def initialize(message, left_out: [], contacts_saved: false)
      super(message)
      @left_out = left_out
      @contacts_saved = contacts_saved
    end
  end

  # leads_scope: os leads que quem pede enxerga (Visibility, #732 item 6). O controller sempre passa; sem ele, a conta.
  def initialize(account:, user:, lead_ids:, name:, leads_scope: nil)
    @account = account
    @user = user
    @leads_scope = leads_scope || Autonomia::Prospecting::Lead.where(account: account)
    @requested = Array(lead_ids).uniq
    @lead_ids = @requested.filter_map { |value| lead_id(value) }.uniq
    @name = name.to_s.strip
  end

  def perform
    raise Error, 'no_leads' if @requested.empty?
    raise Error, 'too_many_leads' if @requested.size > MAX_LEADS

    check_target!
    rows = {}
    left_out = invalid_ids.map { |value| left(value, 'not_found') }
    @lead_ids.each { |lead_id| place(lead_id, rows, left_out) }
    raise Error.new(no_rows_code(left_out), left_out: left_out) if rows.empty?

    finish(rows, left_out)
  end

  private

  # O que precisa estar certo no destino antes de criar qualquer contato. No Público novo, o nome.
  def check_target!
    raise Error, 'name_required' if @name.blank?
  end

  # Os contatos que já estão no destino; nenhum no Público novo.
  def members
    Set.new
  end

  # O código da recusa quando ninguém entra; no Público novo, sempre no_rows.
  def no_rows_code(_left_out)
    'no_rows'
  end

  # Grava as linhas e diz quem entrou. No Público novo, todos os de rows entram.
  def finish(rows, left_out)
    Result.new(audience: write(rows, left_out), entered_lead_ids: rows.keys, left_out: left_out, channels_off: [])
  end

  # O que veio no pedido e não é id: sai como not_found, com o valor como veio.
  def invalid_ids
    @requested.reject { |value| lead_id(value) }
  end

  # Só inteiro ou texto de dígitos (base 10) vale como id; o resto (lista, objeto, booleano, "0x1A") não é id.
  def lead_id(value)
    id = case value
         when Integer then value
         when String then Integer(value, 10, exception: false)
         end
    id if id&.positive?
  end

  def write(rows, left_out)
    writer.perform(@name, rows.values)
  rescue CampaignJourney::AudienceWriter::Error => e
    raise Error.new(e.message, left_out: left_out, contacts_saved: true)
  end

  # Põe o lead nas linhas do Público ou em left_out, com o motivo. Mesmo padrão de falha do ContactBatch: dado recusado
  # pelo modelo vira invalid_data; qualquer outra falha do lead vai para o tracker e vira unexpected_error, sem derrubar
  # os outros leads do pedido (o conversor não tem erro de domínio próprio).
  def place(lead_id, rows, left_out)
    lead = leads_by_id[lead_id]
    return left_out << left(lead_id, 'not_found') if lead.nil?

    converter = converter_for(lead)
    reason = eligibility.consent_block_reason(lead) || (NO_CHANNEL unless converter.channel?)
    return left_out << left(lead_id, reason) if reason

    add_row(lead_id, converter.perform.contact, rows, left_out)
  rescue ActiveRecord::RecordInvalid
    left_out << left(lead_id, 'invalid_data')
  rescue StandardError => e
    Rails.logger.error("[prospecting.audience_from_leads] lead=#{lead_id} falhou: #{e.class}")
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    left_out << left(lead_id, 'unexpected_error')
  end

  def add_row(lead_id, contact, rows, left_out)
    reason = reach_reason(contact)
    reason ||= 'already_in_list' if members.include?(contact.id)
    reason ||= 'same_contact' if rows.each_value.any? { |row| row.contact_id == contact.id }
    return left_out << left(lead_id, reason) if reason

    rows[lead_id] = Autonomia::Prospecting::AudienceRows.row_for(contact)
  end

  # nil quando o contato pode receber; senão o código de left_out, e UNREACHABLE para um motivo novo da régua.
  def reach_reason(contact)
    reason = ConversationAudience::Reach.reason_for(contact)
    REACH_REASONS.fetch(reason, UNREACHABLE) unless reason.nil?
  end

  def converter_for(lead)
    Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user, consent_veto: eligibility.consent_veto)
  end

  def left(lead_id, reason_code)
    { lead_id: lead_id, reason_code: reason_code, message: I18n.t("autonomia.prospecting.audience.left_out.#{reason_code}") }
  end

  # O que o conversor e a régua leem de cada lead, numa consulta por associação.
  def leads_by_id
    @leads_by_id ||= @leads_scope.where(id: @lead_ids).includes(:account, :contact).index_by(&:id)
  end

  def eligibility
    @eligibility ||= Autonomia::Prospecting::SegmentEligibility.new(account: @account, user: @user)
  end

  def writer
    CampaignJourney::AudienceWriter.new(@account, user: @user, source: SOURCE)
  end
end
