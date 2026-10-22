# Excluir de vez (#2096, Parte C): apaga o card e todo o histórico dele. A conversa do cliente e as mensagens não são
# tocadas: só o vínculo do card com elas (crm_card_conversations) sai.
#
# Quem decide se pode (administrador, card arquivado, confirmação) é quem chama. Este serviço só apaga, em lote, os
# cards da conta que receber, e roda o bloco do chamador na mesma transação (a auditoria, o contato da LGPD, o funil).
#
# Ordem:
# 1. Reunião futura é cancelada no calendário antes de apagar (o cliente recebe o cancelamento do Google ou da
#    Microsoft). Se o calendário falhar, nada é apagado: ReuniaoNaoCancelada. Reunião já cancelada antes da falha fica
#    cancelada, como no "Cancelar" da agenda.
# 2. Numa transação só: as tabelas que apontam para o card sem chave estrangeira, as reuniões (os convidados não têm
#    cascata no banco), o card (o Rails apaga atividades, retornos, sugestões e vínculos de conversa; o banco apaga
#    séries, memória do card, execuções de automação e decisões do agente, e solta passagens, decisões de assunto,
#    convites e leads de prospecção) e o bloco do chamador.
class Crm::Cards::Excluidor
  class ReuniaoNaoCancelada < StandardError
    attr_reader :meeting_id

    def initialize(meeting_id)
      @meeting_id = meeting_id
      super("meeting #{meeting_id} could not be canceled at the calendar provider")
    end
  end

  def initialize(account:, card_ids:)
    @account = account
    @card_ids = Array(card_ids)
  end

  # Devolve os ids apagados. O bloco recebe esses ids e roda dentro da transação.
  def perform
    ids = @account.crm_cards.where(id: @card_ids).order(:id).pluck(:id)
    conversation_ids = conversas_dos(ids)
    cancelar_reunioes_futuras!(ids)

    ActiveRecord::Base.transaction do
      limpar_registros_sem_chave!(ids)
      Crm::Meeting.where(account_id: @account.id, card_id: ids).find_each(&:destroy!)
      @account.crm_cards.where(id: ids).find_each(&:destroy!)
      yield ids if block_given?
    end

    avisar_acesso_por_funil(conversation_ids)
    ids
  end

  private

  def conversas_dos(ids)
    primarias = @account.crm_cards.where(id: ids).where.not(conversation_id: nil).pluck(:conversation_id)
    (primarias + Crm::CardConversation.where(account_id: @account.id, card_id: ids).pluck(:conversation_id)).uniq
  end

  def cancelar_reunioes_futuras!(ids)
    Crm::Meeting.where(account_id: @account.id, card_id: ids).upcoming.find_each do |meeting|
      Crm::Meetings::CancelService.new(meeting: meeting).perform
    rescue *erros_do_calendario
      raise ReuniaoNaoCancelada, meeting.id
    end
  end

  # Os mesmos erros de calendário que o "Cancelar" da agenda trata (MeetingsController#calendar_provider_error?).
  # Google::CalendarError e Microsoft::CalendarError moram no arquivo do serviço de cada um: carregar o serviço os define.
  def erros_do_calendario
    [Google::CalendarEventService, Microsoft::CalendarEventService].map { |servico| servico.module_parent::CalendarError } +
      [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED]
  end

  # Tabelas que guardam o id do card sem chave estrangeira. Sem isto, sobrariam linhas apontando para um card que não
  # existe mais.
  # - Uso de IA: o custo continua na conta (Configurações › Uso de IA); só o vínculo com o card sai.
  # - Ferramenta do agente de IA: o registro é da conversa, que fica; só o vínculo com o card sai.
  # - Conversões de anúncio (Meta e Google): o registro só existe para o card (selo da gaveta e o feed do Google). O que
  #   já foi enviado fica com a Meta e o Google; a fila de envio ao Google perde o card que não existe mais.
  # - Decisão de assunto: tira o card da lista de cards tocados (o card principal o banco já solta).
  # - Memória do cliente: o pedido encerrado que veio deste card ("ganho · item · data").
  # rubocop:disable Rails/SkipsModelValidations
  def limpar_registros_sem_chave!(ids)
    return if ids.empty?

    da_conta = { account_id: @account.id }
    Crm::AiUsageEvent.where(da_conta).where(card_id: ids).update_all(card_id: nil)
    Autonomia::Agents::ToolRun.where(da_conta).where(card_id: ids).update_all(card_id: nil, updated_at: Time.current)
    Crm::MetaConversionEvent.where(da_conta).where(card_id: ids).delete_all
    Crm::GoogleConversionEvent.where(da_conta).where(card_id: ids).delete_all
    tirar_dos_cards_tocados!(ids)
    Crm::MemoriaFato.where(da_conta).where(escopo: 'contato', item_ref: ids.map { |id| "card:#{id}" }).delete_all
  end

  def tirar_dos_cards_tocados!(ids)
    Crm::SubjectDecision.where(account_id: @account.id).where('touched_card_ids && ARRAY[?]::bigint[]', ids)
                        .update_all([
                                      'touched_card_ids = ARRAY(SELECT tocado FROM unnest(touched_card_ids) AS tocado ' \
                                      'WHERE tocado <> ALL(ARRAY[?]::bigint[])), updated_at = ?', ids, Time.current
                                    ])
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Acesso por funil (#1148): o card dava a conversa a quem cuida do funil dele. Depois do commit, como o próprio card.
  def avisar_acesso_por_funil(conversation_ids)
    account_id = @account.id
    ActiveRecord.after_all_transactions_commit { Crm::Access::CountInvalidation.card_changed!(account_id, conversation_ids) }
  end
end
