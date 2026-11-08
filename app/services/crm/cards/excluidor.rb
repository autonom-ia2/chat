# Excluir de vez (#2096, Parte C): apaga o card e todo o histórico dele. A conversa do cliente e as mensagens não são
# tocadas: só o vínculo do card com elas (crm_card_conversations) sai.
#
# Quem decide se pode (administrador, confirmação) é quem chama. Este serviço apaga, em lote, os cards da conta que
# receber, e roda o bloco do chamador na mesma transação (a auditoria, o contato da LGPD, o funil).
#
# `somente_arquivados` (o padrão): só apaga card arquivado, conferido duas vezes. A conferência do chamador vem antes das
# chamadas ao calendário, que levam segundos; alguém pode restaurar o card nesse meio tempo. Por isso o status é relido
# logo antes de cancelar as reuniões e de novo sob a trava, dentro da transação: se um card não estiver mais arquivado
# (ou tiver sumido), nada é apagado (Crm::ExclusaoDefinitiva::Mudou). O contato da LGPD e o funil com "apagar os cards"
# passam `somente_arquivados: false`: ali o card aberto também sai, por decisão de quem apaga o contato ou o funil.
#
# `conferir`: roda primeiro dentro da transação, com os ids, antes das travas dos cards. O funil o usa para se travar e
# conferir que continua arquivado e com os mesmos cards (Crm::Pipelines::Excluidor).
#
# Ordem:
# 1. Reunião futura é cancelada no calendário antes de apagar (o cliente recebe o cancelamento do Google ou da
#    Microsoft, e o card ganha a atividade "reunião cancelada"). Se o calendário falhar, nada é apagado:
#    ReuniaoNaoCancelada, com as reuniões que já tinham sido canceladas antes da falha (essas ficam canceladas, como no
#    "Cancelar" da agenda).
# 2. Numa transação só, com as travas na ordem do resto do CRM (série, reunião, lembrete, card; ver
#    Crm::Cards::Archiver da Parte A e Crm::Meetings::CancelService): a releitura dos cards, as tabelas que apontam
#    para o card sem chave estrangeira, as reuniões (os convidados não têm cascata no banco), o histórico do card de uma
#    vez (atividades, retornos, sugestões e vínculos de conversa, em vez de um por um), o card (o banco apaga séries,
#    memória do card, execuções de automação e decisões do agente, e solta passagens, decisões de assunto, convites e
#    leads de prospecção) e o bloco do chamador.
class Crm::Cards::Excluidor
  # O erro mora em Crm::ExclusaoDefinitiva: o contato excluído com os cards mantidos também cancela as reuniões.
  ReuniaoNaoCancelada = Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada

  def initialize(account:, card_ids:, somente_arquivados: true)
    @account = account
    @card_ids = Array(card_ids)
    @somente_arquivados = somente_arquivados
    @canceladas = []
  end

  # Devolve os ids apagados. O bloco recebe esses ids e roda dentro da transação.
  def perform(conferir: nil, &)
    ids = @account.crm_cards.where(id: @card_ids).order(:id).pluck(:id)
    conferir_antes!(ids)
    conversation_ids = conversas_dos(ids)
    cancelar_reunioes_futuras!(ids)
    apagar!(ids, conferir, &)
    avisar_acesso_por_funil(conversation_ids)
    ids
  end

  private

  def apagar!(ids, conferir)
    ActiveRecord::Base.transaction do
      conferir&.call(ids)
      travar!(ids)
      limpar_registros_sem_chave!(ids)
      Crm::Meeting.where(account_id: @account.id, card_id: ids).find_each(&:destroy!)
      apagar_historico!(ids)
      @account.crm_cards.where(id: ids).find_each(&:destroy!)
      yield ids if block_given?
    end
  rescue Crm::ExclusaoDefinitiva::Mudou => e
    raise Crm::ExclusaoDefinitiva::Mudou.new(e.motivo, canceladas: @canceladas)
  end

  # Antes do calendário e sob a trava: card que voltou ao quadro (ou sumiu) faz o pedido inteiro desistir.
  def conferir_antes!(ids)
    return unless @somente_arquivados

    conferir_arquivados!(@account.crm_cards.where(id: ids).select(:id, :status).to_a, ids.size)
  end

  def conferir_arquivados!(cards, esperados)
    return unless @somente_arquivados
    return if cards.size == esperados && cards.all?(&:archived?)

    raise Crm::ExclusaoDefinitiva::Mudou.new('not_archived', canceladas: @canceladas)
  end

  def travar!(ids)
    da_conta = { account_id: @account.id, card_id: ids }
    Crm::FollowUpSeries.where(da_conta).order(:id).lock.load
    Crm::Meeting.where(da_conta).order(:id).lock.load
    Crm::FollowUp.where(da_conta).order(:id).lock.load
    travados = @account.crm_cards.where(id: ids).order(:id).lock.to_a
    raise Crm::ExclusaoDefinitiva::Mudou.new('cards_changed', canceladas: @canceladas) if travados.size != ids.size

    conferir_arquivados!(travados, ids.size)
    conferir_reunioes_canceladas!(da_conta)
  end

  # Uma reunião marcada entre o cancelamento no calendário e a trava seria apagada daqui sem cancelar lá, e o cliente
  # ficaria com o convite. Sob a trava, nenhuma pode estar marcada: se estiver, nada é apagado.
  def conferir_reunioes_canceladas!(da_conta)
    return unless Crm::Meeting.where(da_conta).upcoming.exists?

    raise Crm::ExclusaoDefinitiva::Mudou.new('cards_changed', canceladas: @canceladas)
  end

  # Tudo isto tem cascata no banco e nenhum callback que importe ao apagar (o aviso do acesso por funil que o vínculo de
  # conversa daria, avisar_acesso_por_funil dá). Um DELETE por tabela, em vez de um por linha.
  def apagar_historico!(ids)
    da_conta = { account_id: @account.id, card_id: ids }
    [Crm::Activity, Crm::AiStageSuggestion, Crm::FollowUp, Crm::CardConversation].each { |modelo| modelo.where(da_conta).delete_all }
  end

  def conversas_dos(ids)
    primarias = @account.crm_cards.where(id: ids).where.not(conversation_id: nil).pluck(:conversation_id)
    (primarias + Crm::CardConversation.where(account_id: @account.id, card_id: ids).pluck(:conversation_id)).uniq
  end

  def cancelar_reunioes_futuras!(ids)
    @canceladas = Crm::Meetings::CancelarFuturas.new(account: @account, card_ids: ids).perform
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
