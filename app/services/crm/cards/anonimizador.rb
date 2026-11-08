# Contato excluído, cards mantidos sem dado pessoal (#2096, decisão 1 do protótipo; LGPD). Roda em toda destruição de
# contato (Contact#destroy!, ver ContactCrmCards): o DELETE contacts/:id de sempre, a exclusão em lote, a exclusão da
# conta e o modo 'keep' de POST crm/contacts/:id/permanent_delete. Na mesclagem os cards já foram para o contato que
# fica (ContactMergeAction#merge_crm_cards) e não há o que limpar.
#
# Cada card vira "Cliente removido #<id do card>" e perde o que identifica ou descreve a pessoa. Ficam valor, moeda,
# funil, etapa, status (e o desfecho do arquivado), datas, dono, equipe, caixa, prioridade e pontuação: números, metas
# e relatórios continuam contando. A lista do que sai e do que fica, coluna a coluna, está no PR #2098.
#
# Só com a flag crm_arquivados ligada na conta (decisão do Rodrigo, 23/10; ver ContactCrmCards). Desligada, excluir o
# contato só solta os cards, como na main.
#
# Ordem:
# 1. cancelar_reunioes!: reunião futura cancelada no calendário (decisão 10: no Google e na Microsoft o cliente recebe
#    o cancelamento; a só do WhatsApp cancela aqui). Fora da transação, por quem pode (modo 'keep' da rota nova e
#    exclusão em lote). Se uma falhar, Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada e nada é limpo.
# 2. perform: dentro da transação de quem chama, com as travas na ordem do resto do CRM (série, reunião, lembrete,
#    card). Cancela o que ainda for futuro, para o caminho que não passou pelo 1 (DELETE contacts/:id, que só sabe do
#    contato online dentro da ação, e exclusão da conta); a falha ali desfaz o destroy inteiro. Sob a trava, nenhuma
#    reunião do contato pode continuar marcada (uma marcada entre o cancelamento e a trava ficaria com o convite num
#    card sem cliente): se houver, Crm::ExclusaoDefinitiva::Mudou ('cards_changed') e nada é limpo, como no
#    Crm::Cards::Excluidor.
class Crm::Cards::Anonimizador
  FLAG = 'crm_arquivados'.freeze

  # Chaves de crm_cards.metadata que ficam: o desfecho do arquivado (Parte A, #2094, Crm::Card::DESFECHO_ARQUIVADO)
  # conta em números, metas e relatórios. O resto (resumo e campos da IA, prospecção, cadência, hash livre da API) sai.
  METADATA_DO_CARD = %w[desfecho_arquivado].freeze
  # Marca do card anonimizado, com a data: a tela e a auditoria sabem que o cliente foi removido.
  MARCA = 'contato_removido_em'.freeze

  CHAVE_DA_CONTA_SAINDO = :crm_anonimizador_conta_saindo

  # A conta inteira está sendo apagada (DeleteObjectJob, via Crm::ContatosSoltamCardsNaExclusaoDaConta): os cards saem
  # com ela. Não há o que anonimizar, e cancelar as reuniões mandaria aviso de cancelamento a cada cliente da conta. Nesse
  # bloco, o ContactCrmCards não faz nada e o contato só solta os cards (`dependent: :nullify`), como na main.
  def self.durante_exclusao_da_conta
    anterior = ActiveSupport::IsolatedExecutionState[CHAVE_DA_CONTA_SAINDO]
    ActiveSupport::IsolatedExecutionState[CHAVE_DA_CONTA_SAINDO] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[CHAVE_DA_CONTA_SAINDO] = anterior
  end

  def self.conta_saindo?
    ActiveSupport::IsolatedExecutionState[CHAVE_DA_CONTA_SAINDO] == true
  end

  def self.ligado?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # As reuniões canceladas por esta instância (no cancelar_reunioes! e no perform), para a Auditoria; e, delas, as
  # canceladas só aqui porque o calendário não se alcança (o evento pode continuar vivo no Google ou na Microsoft).
  attr_reader :reunioes_canceladas, :reunioes_so_aqui

  def initialize(contact:)
    @contact = contact
    @account = contact.account
    @agora = Time.current
    @reunioes_canceladas = []
    @reunioes_so_aqui = []
  end

  def cancelar_reunioes!
    cancelar_futuras!
  end

  # Devolve os ids dos cards anonimizados.
  def perform
    ids = ActiveRecord::Base.transaction do
      cancelar_futuras!
      soltar_cards_de_outra_conta!
      travar!.tap do |travados|
        conferir_reunioes_canceladas!(travados)
        anonimizar!(travados)
      end
    end
    avisar_depois_do_commit(ids)
    ids
  end

  private

  def cancelar_futuras!
    cancelador = Crm::Meetings::CancelarFuturas.new(account: @account, card_ids: card_ids_do_contato)
    canceladas = cancelador.perform
    @reunioes_canceladas |= canceladas
    @reunioes_so_aqui |= cancelador.so_aqui
    canceladas
  end

  def conferir_reunioes_canceladas!(ids)
    return unless Crm::Meeting.where(account_id: @account.id, card_id: ids).upcoming.exists?

    raise Crm::ExclusaoDefinitiva::Mudou.new('cards_changed', canceladas: @reunioes_canceladas)
  end

  def card_ids_do_contato
    @account.crm_cards.where(contact_id: @contact.id).order(:id).pluck(:id)
  end

  # Card de outra conta apontando para este contato é dado inconsistente (a validação do card não deixa), mas a FK em
  # cascata o apagaria junto com o contato. Só solta o vínculo, como o antigo `dependent: :nullify`: o card não é desta
  # conta e não é limpo daqui.
  def soltar_cards_de_outra_conta!
    Crm::Card.where(contact_id: @contact.id).where.not(account_id: @account.id)
             .update_all(contact_id: nil, updated_at: @agora) # rubocop:disable Rails/SkipsModelValidations
  end

  def travar!
    da_conta = { account_id: @account.id, card_id: card_ids_do_contato }
    [Crm::FollowUpSeries, Crm::Meeting, Crm::FollowUp].each { |modelo| modelo.where(da_conta).order(:id).lock.load }
    @account.crm_cards.where(contact_id: @contact.id).order(:id).lock.pluck(:id)
  end

  def anonimizar!(ids)
    return if ids.empty?

    @conversation_ids = conversas_dos(ids)
    Crm::Cards::Anonimizador::Historico.new(account: @account, card_ids: ids, agora: @agora).limpar!
    @account.crm_cards.where(id: ids).find_each { |card| anonimizar_card!(card) }
  end

  # update_columns de propósito: sem as correções da memória (Crm::CardMemoria), o webhook e o histórico de "update"
  # que gravariam o texto apagado em outro lugar.
  # rubocop:disable Rails/SkipsModelValidations
  def anonimizar_card!(card)
    card.update_columns(
      title: I18n.t('crm.cards.anonimizado.title', id: card.id, locale: @account.locale.presence || I18n.default_locale),
      description: nil, lost_reason: nil, custom_attributes: {}, source: nil, external_id: nil,
      contact_id: nil, conversation_id: nil, next_follow_up_at: nil,
      metadata: card.metadata.to_h.slice(*METADATA_DO_CARD).merge(MARCA => @agora.iso8601),
      updated_at: @agora
    )
  end
  # rubocop:enable Rails/SkipsModelValidations

  def conversas_dos(ids)
    primarias = @account.crm_cards.where(id: ids).where.not(conversation_id: nil).pluck(:conversation_id)
    (primarias + Crm::CardConversation.where(account_id: @account.id, card_id: ids).pluck(:conversation_id)).uniq
  end

  # Acesso por funil (#1148): o card dava as conversas a quem cuida do funil dele. E o quadro aberto troca o título.
  def avisar_depois_do_commit(ids)
    return if ids.empty?

    account_id = @account.id
    conversation_ids = @conversation_ids
    ActiveRecord.after_all_transactions_commit do
      Crm::Access::CountInvalidation.card_changed!(account_id, conversation_ids)
      Crm::Card.where(id: ids).find_each { |card| Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED) }
    end
  end
end
