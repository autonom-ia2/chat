# O desfecho do card de renovação chega ao seguro (E5, #2898): card ganho, perdido, resolvido, cancelado, reaberto ou
# arquivado. Quem escreve é Carteira::Renovacao::Desfecho, pelo estado do card; aqui só se ouve.
#
# No despacho SÍNCRONO (SyncDispatcher), depois do commit de quem mexeu no card: o quadro, a IA e as automações passam
# por aqui. A gaveta do seguro, o cancelamento e a apólice nova já escrevem o desfecho na transação deles
# (Carteira::Renovacao::Fechar.pelo_card); para eles este ouvinte chega depois e não muda nada, porque o Desfecho só
# escreve o que falta.
#
# Estes eventos saem para todo card de toda conta que tenha qualquer assinante (webhook, anúncio, automação). Por isso
# a ordem: primeiro a conta tem a carteira (Carteira::Acesso, sem consulta: a conta do pedido já está carregada);
# depois o card é de um seguro (uma leitura pelo índice único de `crm_card_id`); só então se procura quem fechou. A
# conta sem carteira não custa nada, e o card que não é de seguro custa essa leitura só.
#
# Uma falha aqui não desfaz o fechamento do card, que já está gravado: vai para o rastreador de erros e para o log, só
# com ids. O seguro se acerta no próximo evento do card, ou quando alguém mexer na renovação pela gaveta.
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
    conta = conta_de(dados[:account_id])
    return unless conta && Carteira::Acesso.liberada?(conta)

    apolice = Carteira::Apolice.find_by(account_id: conta.id, crm_card_id: dados[:card_id])
    Carteira::Renovacao::Desfecho.new(apolice, user: quem_fez(dados[:activity_id])).acertar if apolice
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[carteira][renovacao] desfecho não chegou ao seguro card=#{dados[:card_id]} #{e.class}")
  end

  # A conta do pedido, quando é ela: nenhuma consulta. Na troca em lote, a que o emissor já leu
  # (Autonomia::Automacao::EmLote). Fora de pedido (a IA, uma automação), uma leitura pela chave primária.
  def conta_de(id)
    return Current.account if Current.account&.id == id

    Autonomia::Automacao::EmLote.lembrar([:conta, id]) { Account.find_by(id: id) }
  end

  # A pessoa que fechou o card; nulo quando foi a IA, uma automação ou o sistema.
  def quem_fez(activity_id)
    atividade = Crm::Activity.find_by(id: activity_id)
    User.find_by(id: atividade.actor_id) if atividade&.actor_type == 'user'
  end
end
