# Rastro do "excluir de vez" (#2096): quem apagou, quando, o quê e quantos. Só ids, contagens e códigos, nunca nome,
# telefone, título ou valor: o que foi apagado não volta por aqui.
#
# Vai para a trilha de Auditoria da conta (tabela `audits`, a mesma do Guia, #536), não para um lugar novo. É a única
# trilha que sobrevive ao apagado: a atividade do card some com ele, e o log do servidor some com a máquina no deploy.
# Gravado na mesma transação que apaga: se a auditoria falhar, nada é apagado.
#
# O funil com cards é excluído num job (Crm::Pipelines::ExcluirDeVezJob), depois de a API já ter respondido 202. Quando
# o job desiste, o desfecho também fica aqui (FALHOU), com o motivo em código, para a tela mostrar o que aconteceu.
module Crm::ExclusaoDefinitiva
  ACAO = 'crm_hard_delete'.freeze
  FALHOU = 'crm_hard_delete_failed'.freeze
  ALVOS = %w[cards funil contato].freeze

  # O que era para sair mudou entre a conferência e as travas, e nada foi apagado. `motivo`:
  # - not_archived: um card ou o funil foi restaurado (não está mais arquivado);
  # - cards_changed: um card sumiu ou entrou no funil nesse meio tempo;
  # - pipeline_has_cards: o funil vazio ganhou card antes de ser apagado;
  # - target_unavailable: o funil de destino dos cards foi arquivado ou apagado;
  # - already_deleted: outro pedido igual já apagou o funil (dois cliques).
  # `canceladas`: reuniões futuras que já tinham sido canceladas no calendário antes da desistência. Ficam canceladas
  # (o cliente já foi avisado), com a atividade "reunião cancelada" no card.
  class Mudou < StandardError
    attr_reader :motivo, :canceladas

    def initialize(motivo, canceladas: [])
      @motivo = motivo
      @canceladas = canceladas
      super("permanent delete aborted: #{motivo}")
    end
  end

  # Uma reunião futura não cancelou no calendário (Crm::Meetings::CancelarFuturas), e nada foi apagado. `canceladas`: as
  # que já tinham sido canceladas antes dela.
  class ReuniaoNaoCancelada < StandardError
    attr_reader :meeting_id, :canceladas

    def initialize(meeting_id, canceladas = [])
      @meeting_id = meeting_id
      @canceladas = canceladas
      super("meeting #{meeting_id} could not be canceled at the calendar provider")
    end
  end

  # O que fazer com os cards ao excluir o contato (decisão 1 do protótipo, sem padrão: quem exclui escolhe).
  CARDS_APAGAR = 'delete'.freeze
  CARDS_MANTER = 'keep'.freeze
  MODOS_DO_CONTATO = [CARDS_APAGAR, CARDS_MANTER].freeze
  # Só na Auditoria: o contato excluído pelo DELETE de sempre, sem card nem reunião, levou só leads da Prospecção (#2143).
  LEADS = 'leads'.freeze

  module_function

  # Excluir o contato (LGPD). modo:
  # - 'delete': apaga de vez os cards dele (abertos, ganhos ou arquivados);
  # - 'keep': mantém os cards sem dado pessoal (Crm::Cards::Anonimizador): valor, funil, etapa, datas e desfecho ficam.
  # Nos dois modos, o lead da Prospecção que é desta pessoa sai de vez, e o que recusou contato fica só com a prova da
  # recusa (Autonomia::Prospecting::LeadsDoContatoExcluido, #2143).
  # Os cards, os leads, o contato e o rastro saem juntos ou nada sai. Devolve { deleted_card_ids:, anonymized_card_ids: }.
  #
  # Nos dois modos, o contato é travado primeiro dentro da transação: dois cliques (ou duas abas) não gravam duas linhas
  # na Auditoria, o segundo espera o primeiro e encontra o contato já excluído (Mudou 'already_deleted').
  #
  # Trava longa não há, mas a ordem das travas cruza com a conversão de lead (lead, depois contato): um impasse
  # (ActiveRecord::Deadlocked) desfaz tudo, e o pedido é refeito do começo, até TENTATIVAS vezes (com_retentativa).
  def contato!(contact:, user:, modo:)
    raise ArgumentError, "modo desconhecido: #{modo}" unless MODOS_DO_CONTATO.include?(modo)
    return contato_mantendo_cards!(contact: contact, user: user) if modo == CARDS_MANTER

    com_retentativa { contato_apagando_cards!(contact: contact, user: user, modo: modo) }
  end

  def contato_apagando_cards!(contact:, user:, modo:)
    account = contact.account
    card_ids = account.crm_cards.where(contact_id: contact.id).order(:id).pluck(:id)
    leads = nil
    # Sob a trava do contato e antes de os cards saírem (o que soltaria o lead deles): os leads desta pessoa.
    conferir = lambda do |ids|
      conferir_cards_do_contato!(contact, ids)
      leads = Autonomia::Prospecting::LeadsDoContatoExcluido.new(contact: contact)
    end
    apagados = Crm::Cards::Excluidor.new(account: account, card_ids: card_ids, somente_arquivados: false)
                                    .perform(conferir: conferir) do |ids|
      leads.perform
      auditar!(account: account, user: user, alvo: 'contato', card_ids: ids, contact_id: contact.id, modo: modo, **dos_leads(leads))
      # Por último, dentro da transação: as conversas do contato saem num job que só é enfileirado depois do commit
      # (dependent: :destroy_async), então uma falha aqui desfaz tudo, sem job solto.
      contact.destroy!
    end
    { deleted_card_ids: apagados, anonymized_card_ids: [] }
  end

  # As reuniões futuras são canceladas antes, fora da transação (o calendário não volta atrás). Dentro dela, o contato é
  # travado, os cards perdem o dado pessoal sob a trava e o contato sai; o Contact#destroy! não acha mais card dele para
  # limpar nem audita de novo.
  def contato_mantendo_cards!(contact:, user:)
    anonimizador = Crm::Cards::Anonimizador.new(contact: contact)
    anonimizador.cancelar_reunioes!
    mantidos = com_retentativa { anonimizar_e_excluir!(contact, user, anonimizador) }
    { deleted_card_ids: [], anonymized_card_ids: mantidos }
  end

  def anonimizar_e_excluir!(contact, user, anonimizador)
    ActiveRecord::Base.transaction do
      travar_contato!(contact)
      leads = Autonomia::Prospecting::LeadsDoContatoExcluido.new(contact: contact)
      anonimizador.perform.tap do |ids|
        leads.perform
        auditar!(account: contact.account, user: user, alvo: 'contato', card_ids: [], contact_id: contact.id,
                 modo: CARDS_MANTER, cards_mantidos: ids.size, card_ids_mantidos: ids,
                 reunioes_canceladas: anonimizador.reunioes_canceladas.size,
                 reunioes_so_aqui: anonimizador.reunioes_so_aqui.size, **dos_leads(leads))
        contact.destroy!
      end
    end
  end

  # Impasse com outra transação (a conversão de um lead trava o lead e depois o contato; a exclusão, o contato e depois
  # os leads): o Postgres desfaz uma das duas. Se foi esta, ela é refeita do começo, com uma pausa curta, até TENTATIVAS
  # vezes. Dentro de uma transação de quem chama não dá para refazer só este pedaço: o erro sobe.
  TENTATIVAS = 3
  PAUSA_ENTRE_TENTATIVAS = 0.1

  def com_retentativa
    return yield if ActiveRecord::Base.connection.transaction_open?

    tentativa = 0
    begin
      tentativa += 1
      yield
    rescue ActiveRecord::Deadlocked
      raise if tentativa >= TENTATIVAS

      sleep(PAUSA_ENTRE_TENTATIVAS * tentativa)
      retry
    end
  end

  # Sob a trava do contato, os cards dele são relidos: card criado ou movido para outro contato entre a conferência e a
  # trava faz o pedido inteiro desistir, em vez de apagar uma lista velha.
  def conferir_cards_do_contato!(contact, ids)
    travar_contato!(contact)
    atuais = contact.account.crm_cards.where(contact_id: contact.id).order(:id).pluck(:id)
    raise Mudou, 'cards_changed' unless atuais == ids.sort
  end

  def travar_contato!(contact)
    raise Mudou, 'already_deleted' if Contact.where(id: contact.id).lock.pluck(:id).empty?
  end

  # Contato excluído por qualquer caminho, com a flag crm_arquivados (ContactCrmCards): quem excluiu pode não ver os
  # cards. Só ids e contagens.
  # reunioes_so_aqui: canceladas só no sistema porque o calendário não se alcança (o evento pode seguir no provedor).
  # Sem card nem reunião, só com leads, a linha tem frase própria (modo LEADS): não houve card para manter.
  def auditar_contato_excluido!(contact:, user:, card_ids:, anonimizador:, leads:)
    reunioes = anonimizador.reunioes_canceladas
    so_leads = card_ids.empty? && reunioes.empty?
    auditar!(account: contact.account, user: user, alvo: 'contato', card_ids: [], contact_id: contact.id,
             modo: so_leads ? LEADS : CARDS_MANTER, cards_mantidos: card_ids.size, card_ids_mantidos: card_ids,
             reunioes_canceladas: reunioes.size, reunioes_so_aqui: anonimizador.reunioes_so_aqui.size,
             canceled_meeting_ids: reunioes.presence, **dos_leads(leads))
  end

  # Os leads da Prospecção que saíram com o contato e os que ficaram só com a prova da recusa: só ids e contagens. Sem
  # lead nenhum, a linha fica como era antes do #2143.
  def dos_leads(leads)
    return {} if leads.apagados.empty? && leads.minimizados.empty?

    { leads_apagados: leads.apagados.size, lead_ids_apagados: leads.apagados.presence,
      leads_minimizados: leads.minimizados.size, lead_ids_minimizados: leads.minimizados.presence }
  end

  # Contato que a exclusão em lote não conseguiu excluir (Contacts::BulkDeleteService): ficou inteiro. Só ids e o
  # motivo em código.
  def contato_falhou!(contact:, user:, motivo:, **extras)
    falhou!(account: contact.account, user: user, alvo: 'contato', motivo: motivo, contact_id: contact.id, **extras)
  end

  # alvo: 'cards' (Arquivados), 'funil' (Funis arquivados) ou 'contato' (excluir contato com os cards, LGPD).
  # extras: ids do funil, do contato e contagens, sem texto.
  def auditar!(account:, user:, alvo:, card_ids:, **extras)
    raise ArgumentError, "alvo desconhecido: #{alvo}" unless ALVOS.include?(alvo)

    Audited.audit_class.create!(
      auditable: account, user: user, action: ACAO,
      audited_changes: { 'alvo' => alvo, 'cards_apagados' => card_ids.size, 'card_ids' => card_ids }
                         .merge(extras.compact.transform_keys(&:to_s))
    )
  end

  # O job do funil desistiu: nada foi apagado. motivo: um código de Mudou, meeting_cancel_failed ou card_rejected.
  # extras: só ids e nomes de campo, sem texto do card.
  def falhou!(account:, user:, alvo:, motivo:, **extras)
    raise ArgumentError, "alvo desconhecido: #{alvo}" unless ALVOS.include?(alvo)

    Audited.audit_class.create!(
      auditable: account, user: user, action: FALHOU,
      audited_changes: { 'alvo' => alvo, 'motivo' => motivo }.merge(extras.compact.transform_keys(&:to_s))
    )
  end
end
