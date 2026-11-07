# Põe o cliente da conversa numa etapa (#2414 F1.4): move o card que já existe ou, se a conversa não tem card nenhum,
# cria um ali, sem duplicar. É o "mover" de qualquer motor de automação.
#
# - Com card, segue a regra de sempre (#1141): o card aberto do funil da etapa; senão o assunto atual. Card ganho ou
#   perdido não é movido (como no Kanban), nem ganha um card novo: isso é a ação "criar card" (#1197).
# - Sem card, cria na etapa, como o "criar card" (#1142), pelo CardNovo: trava da conversa e nova conferência dentro
#   dela, para duas automações juntas não criarem dois. Contato fora do funil (#2084) não vira card.
# - O card criado "entrou na etapa": as automações de entrada dela rodam, como depois de mover.
class Autonomia::Automacao::CardNaEtapa
  include Events::Types

  # automacao: quem pediu o movimento (`{ origem:, id: }`, Crm::Cards::Mover), para a IA do funil respeitá-lo (#2428).
  def initialize(conversation:, stage:, actor: nil, automacao: nil)
    @conversation = conversation
    @account = conversation.account
    @stage = stage
    @actor = actor
    @automacao = automacao
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

    Crm::Cards::Mover.new(card: card, actor: @actor, target_stage: @stage, automacao: @automacao).perform
    Crm::Cards::Broadcaster.broadcast(card, CRM_CARD_MOVED)
    card
  end

  # A criação é a mesma do passo "criar card" (CardNovo); aqui, qualquer card da conversa já conta.
  def criar
    return if Crm::Relacao.fora_do_funil?(@conversation.contact)

    Autonomia::Automacao::CardNovo.new(stage: @stage, conversation: @conversation, actor: @actor, automacao: @automacao)
                                  .criar { finder.all(@conversation).exists? }
  end
end
