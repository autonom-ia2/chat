# Prende, no save que troca a pessoa da conversa, o que o registro de passagens precisa saber depois do commit (#1606):
# quem estava (a pessoa anterior ou, sem ela, o robô), o motivo e o card do Crm::Passagens.com_motivo em curso, e quem
# pediu (o robô do contexto ou a pessoa logada). O Crm::PassagensListener, no despacho síncrono depois do commit,
# recebe este mesmo objeto e lê o que ficou preso aqui, mesmo que o bloco do com_motivo já tenha terminado.
#
# Vários saves de pessoa na mesma transação (robô → Ana → Bia) viram uma troca só, do primeiro "antes" (o robô) para a
# pessoa do fim (a Bia): é o que o commit mostra. A transação desfeita solta a troca.
module ConversationPassagem
  extend ActiveSupport::Concern

  Troca = Struct.new(:pessoa_antes_id, :robo_antes_type, :robo_antes_id, :motivo, :card, :pedida_por, keyword_init: true)

  included do
    before_save :prender_troca_da_passagem, if: :will_save_change_to_assignee_id?
    after_rollback :soltar_troca_da_passagem
  end

  # A troca presa desde o último commit, e solta: cada troca é lida uma vez.
  def soltar_troca_da_passagem
    troca = @troca_da_passagem
    @troca_da_passagem = nil
    troca
  end

  private

  def prender_troca_da_passagem
    contexto = Crm::Passagens::Contexto
    antes = @troca_da_passagem || antes_desta_troca
    @troca_da_passagem = antes.dup.tap do |troca|
      troca.motivo = contexto.motivo.presence
      troca.card = contexto.card
      troca.pedida_por = contexto.pedida_por || Current.user
    end
  end

  def antes_desta_troca
    Troca.new(pessoa_antes_id: attribute_in_database('assignee_id'), robo_antes_type: attribute_in_database('ai_assignee_type'),
              robo_antes_id: attribute_in_database('assignee_agent_bot_id'))
  end
end
