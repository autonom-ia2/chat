# #2428 (F6.7 do #2414): a IA do funil respeita o card que uma automação moveu, como respeita o da pessoa. Sem isso, a
# avaliação seguinte devolvia o card para onde estava e desfazia, sem ninguém ver, a automação que alguém configurou.
#
# Vale quando o último movimento do card foi de uma automação (`by: 'automacao'`, Crm::Cards::Mover): dentro da mesma
# janela da pessoa (RESPEITO_AO_MOVIMENTO) e, depois dela, até chegar mensagem NOVA do cliente. Card parado ou
# reavaliação sem fato novo não desfazem a automação. Movimento da IA ou de uma pessoa depois dele encerra o respeito.
class Crm::Ai::MovimentoDaAutomacao
  def self.respeitar?(card) = new(card).respeitar?

  # O passo da Automação livre move pela porta da frente, com quem ligou como ator: a atividade é da pessoa no nome,
  # mas a escolha foi da automação. Fora das regras da pessoa (Evaluator, FecharCard), que barram também o fechar.
  def self.sem_automacao(atividades)
    atividades.where.not('payload @> ?', { by: 'automacao' }.to_json)
  end

  def initialize(card)
    @card = card
  end

  def respeitar?
    movimento = ultimo_movimento
    return false unless movimento&.payload.to_h['by'] == 'automacao'

    movimento.created_at > Crm::Ai::Evaluator::RESPEITO_AO_MOVIMENTO.ago || !mensagem_nova_depois?(movimento.created_at)
  end

  private

  def ultimo_movimento
    Crm::Activity.where(account_id: @card.account_id, card_id: @card.id, event_type: 'move').order(:created_at, :id).last
  end

  def mensagem_nova_depois?(momento)
    conversas = [@card.conversation_id, *@card.card_conversations.pluck(:conversation_id)].compact.uniq
    Message.where(account_id: @card.account_id, conversation_id: conversas, message_type: :incoming)
           .exists?(['created_at > ?', momento])
  end
end
