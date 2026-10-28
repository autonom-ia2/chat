# A rodada da leitura automática de UM agente (#2301), enfileirada pelo LeituraAutomaticaJob da conta.
#
# - Cada tentativa paga chamadas de IA de novo: se a rodada cair, ela fica `erro`, o orquestrador levanta
#   RodadaComErro e o job é descartado, sem nova tentativa; a próxima é a do dia seguinte.
# - Erro antes de abrir a rodada (Redis fora do ar, a ficha que não carrega): nada foi pago nem registrado. O job loga a
#   classe do erro e a conta (sem a mensagem, que pode ter dado da conta) e tenta de novo até TENTATIVAS_DO_ERRO vezes;
#   esgotadas, loga de novo e desiste até o dia seguinte. Nada some sem rastro.
# - Os agentes da mesma conta rodam em fila (o teto diário é da conta): com outra rodada da conta em andamento, o
#   orquestrador levanta ContaOcupada e este job se reagenda para dali a ESPERA_DA_CONTA, até TENTATIVAS_DA_CONTA
#   vezes, que somam mais que a trava de 6 horas do orquestrador. Esgotadas, fica registrado no log e o agente lê no
#   dia seguinte.
# - Uma rodada por agente por dia, no fuso da conta: a marca `rodou` no Redis, gravada com a rodada fechada em
#   qualquer status (ok, teto, sem_ia, chave_recusada ou erro), barra o job duplicado do mesmo dia (uma nova tentativa
#   do job da conta) e não deixa pagar duas vezes.
# - Confere de novo, na hora de rodar, que a leitura segue ligada, a conta e o agente seguem elegíveis (o mesmo critério
#   do job da conta) e a ficha ainda é a vigente com chave de leitura.
class Autonomia::Desempenho::LeituraDaFichaJob < ApplicationJob
  queue_as :low

  ESPERA_DA_CONTA = 10.minutes
  TENTATIVAS_DA_CONTA = 37
  ESPERA_DO_ERRO = 30.minutes
  TENTATIVAS_DO_ERRO = 3
  RODOU_POR = 2.days

  # O ActiveJob procura o tratamento do último declarado para o primeiro: o genérico vem antes dos específicos.
  retry_on StandardError, wait: ESPERA_DO_ERRO, attempts: TENTATIVAS_DO_ERRO do |job, erro|
    Rails.logger.error("[desempenho][leitura] conta=#{job.arguments.first} ficha=#{job.arguments.second} desistiu=#{erro.class.name}")
  end
  discard_on ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador::RodadaComErro
  retry_on ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador::ContaOcupada, wait: ESPERA_DA_CONTA,
                                                                                   attempts: TENTATIVAS_DA_CONTA do |job, _erro|
    Rails.logger.warn("[desempenho][leitura] conta=#{job.arguments.first} ficha=#{job.arguments.second} conta_ocupada_esgotou")
  end

  def perform(account_id, ficha_id)
    return unless ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador.ligada?

    ficha = ::Autonomia::Desempenho::Ficha.find_by(id: ficha_id, account_id: account_id)
    return unless rodar?(ficha)

    rodou = rodou_hoje(ficha)
    return if Redis::Alfred.get(rodou).present?

    rodar(ficha, rodou)
  end

  private

  def rodar(ficha, rodou)
    rodada = ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador.new(ficha).call
    Redis::Alfred.set(rodou, rodada.id, ex: RODOU_POR.to_i)
  rescue ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador::ContaOcupada
    raise
  rescue ::Autonomia::Desempenho::LeituraAutomatica::Orquestrador::RodadaComErro
    Redis::Alfred.set(rodou, 'erro', ex: RODOU_POR.to_i)
    raise
  rescue StandardError => e
    Rails.logger.error("[desempenho][leitura] conta=#{ficha.account_id} ficha=#{ficha.id} antes_da_rodada=#{e.class.name}")
    raise
  end

  def rodar?(ficha)
    return false unless ficha&.chave_de_leitura.present? && vigente?(ficha)

    elegivel = ::Autonomia::Desempenho::LeituraAutomatica::Elegivel
    elegivel.conta?(ficha.account) && elegivel.sujeito?(ficha.account, ficha.sujeito_type, ficha.sujeito_id)
  end

  def vigente?(ficha) = ::Autonomia::Desempenho::Ficha.vigente(ficha.account, ficha.sujeito_type, ficha.sujeito_id)&.id == ficha.id

  # A data de hoje no fuso da conta: o dia da conta, igual ao do teto diário.
  def rodou_hoje(ficha)
    data = Time.current.in_time_zone(::Autonomia::Desempenho::Painel.fuso_de(ficha.account, ficha)).to_date.iso8601
    "autonomia:desempenho:leitura:rodou:#{ficha.account_id}:#{ficha.sujeito_type}:#{ficha.sujeito_id}:#{data}"
  end
end
