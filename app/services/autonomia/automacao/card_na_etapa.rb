# Põe o cliente da conversa numa etapa (#2414 F1.4): move o card que já existe ou, se a conversa não tem card nenhum,
# cria um ali, sem duplicar. É o "mover" de qualquer motor de automação.
#
# - Com card, segue a regra de sempre (#1141): o card aberto do funil da etapa; senão o assunto atual. Card ganho ou
#   perdido não é movido (como no Kanban), nem ganha um card novo: isso é a ação "criar card" (#1197).
# - Sem card, cria na etapa, como o "criar card" (#1142): trava da conversa e nova conferência dentro dela, para duas
#   automações juntas não criarem dois. Contato fora do funil (#2084) não vira card.
# - O card criado "entrou na etapa": as automações de entrada dela rodam, como depois de mover.
class Autonomia::Automacao::CardNaEtapa
  include Events::Types

  def initialize(conversation:, stage:, actor: nil)
    @conversation = conversation
    @account = conversation.account
    @stage = stage
    @actor = actor
  end

  def perform
    return unless Crm::Config.enabled? && etapa_da_conta?

    cards = finder.all(@conversation).to_a
    return criar if cards.empty?

    mover(cards.find { |card| card.open? && card.pipeline_id == @stage.pipeline_id } || cards.first)
  end

  private

  def etapa_da_conta?
    @stage.present? && @stage.account_id == @account.id
  end

  def finder
    Crm::Cards::ConversationCardFinder.new(account: @account)
  end

  def mover(card)
    return unless card.open?

    Crm::Cards::Mover.new(card: card, actor: @actor, target_stage: @stage).perform
    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_MOVED)
    card
  end

  def criar
    return if Crm::Relacao.fora_do_funil?(@conversation.contact)

    card = nil
    @conversation.with_lock do
      next if finder.all(@conversation).exists?

      card = Crm::Cards::Creator.new(
        account: @account, user: @actor, conversation: @conversation,
        params: { pipeline_id: @stage.pipeline_id, stage_id: @stage.id }
      ).perform
    end
    return if card.blank?

    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_CREATED)
    Crm::StageAutomations::Runner.new(card: card, actor: @actor, from_stage_id: nil, to_stage_id: card.stage_id).perform
    card
  end
end
