# Prende, no save que troca a pessoa da conversa, o que o registro de passagens precisa saber depois do commit (#1606):
# quem estava (a pessoa anterior ou, sem ela, o robô), o motivo e o card do Crm::Passagens.com_motivo em curso, e quem
# pediu (o robô do contexto ou a pessoa logada). O Crm::PassagensListener, no despacho síncrono depois do commit,
# recebe este mesmo objeto e lê o que ficou preso aqui, mesmo que o bloco do com_motivo já tenha terminado.
#
# Vários saves de pessoa na mesma transação (robô → Ana → Bia) viram uma troca só, do primeiro "antes" (o robô) para a
# pessoa do fim (a Bia), com o primeiro motivo, card e quem pediu que apareceram: é o que o commit mostra. A troca
# presa numa transação que já terminou (desfeita, ou cujo último save não trocou a pessoa e não disparou o evento) não
# passa para a próxima: cada transação começa a sua.
module ConversationPassagem
  extend ActiveSupport::Concern

  Troca = Struct.new(:pessoa_antes_id, :robo_antes_type, :robo_antes_id, :motivo, :card, :pedida_por, keyword_init: true)

  included do
    before_save :prender_troca_da_passagem, if: :will_save_change_to_assignee_id?
  end

  # A troca presa desde o último commit, e solta: cada troca é lida uma vez.
  def soltar_troca_da_passagem
    troca = @troca_da_passagem
    @troca_da_passagem = nil
    troca
  end

  private

  def prender_troca_da_passagem
    transacao = self.class.connection.current_transaction
    anterior = @troca_da_passagem if @transacao_da_troca.equal?(transacao)
    @transacao_da_troca = transacao
    @troca_da_passagem = (anterior || antes_desta_troca).dup.tap do |troca|
      # A marca do rodízio (#1657) é só do save do próprio rodízio: outra troca de pessoa depois dele na mesma transação
      # não sai como rodízio (a R13 soltaria quem não foi o rodízio que pôs).
      troca.motivo = nil if anterior && troca.motivo == Crm::Passagens::Rodizio::MOTIVO
      completar(troca, Crm::Passagens::Contexto)
    end
  end

  def completar(troca, contexto)
    troca.motivo ||= contexto.motivo.presence
    troca.card ||= contexto.card
    troca.pedida_por ||= contexto.pedida_por || Current.user
  end

  def antes_desta_troca
    Troca.new(pessoa_antes_id: attribute_in_database('assignee_id'), robo_antes_type: attribute_in_database('ai_assignee_type'),
              robo_antes_id: attribute_in_database('assignee_agent_bot_id'))
  end
end
