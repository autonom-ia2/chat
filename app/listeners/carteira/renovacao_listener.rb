# O desfecho do card de renovação chega ao seguro (E5, #2898): card ganho, perdido, resolvido, cancelado, reaberto ou
# arquivado. Quem escreve é Carteira::Renovacao::Desfecho, pelo estado do card; aqui só se ouve.
#
# No despacho SÍNCRONO (SyncDispatcher), depois do commit de quem mexeu no card: a gaveta do seguro fecha o card e já
# devolve o seguro como ficou, e o quadro e a gaveta passam pelo mesmo caminho. Custa uma leitura pelo índice único de
# `crm_card_id` em cada evento desses; card que não é de seguro nenhum para aí.
#
# Uma falha aqui não desfaz o fechamento do card, que já está gravado: vai para o rastreador de erros e para o log, só
# com ids. O seguro se acerta no próximo evento do card.
class Carteira::RenovacaoListener < BaseListener
  def crm_card_won(event)
    acertar(event.data)
  end

  alias crm_card_lost crm_card_won
  alias crm_card_resolved crm_card_won
  alias crm_card_cancelled crm_card_won
  alias crm_card_reopened crm_card_won
  alias crm_card_archived crm_card_won

  private

  def acertar(dados)
    Carteira::Renovacao::Desfecho.do_card(dados[:card_id], user: quem_fez(dados[:activity_id]))
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[carteira][renovacao] desfecho não chegou ao seguro card=#{dados[:card_id]} #{e.class}")
  end

  # A pessoa que fechou o card; nulo quando foi a IA, uma automação ou o sistema.
  def quem_fez(activity_id)
    atividade = Crm::Activity.find_by(id: activity_id)
    User.find_by(id: atividade.actor_id) if atividade&.actor_type == 'user'
  end
end
