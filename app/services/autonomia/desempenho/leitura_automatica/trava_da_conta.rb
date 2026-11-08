# A trava de UMA rodada da leitura automática por conta (#2301), no Redis: os agentes da mesma conta leem em fila,
# porque o teto diário de gasto é da conta. Vence sozinha em POR; quem segura renova a cada conversa.
class Autonomia::Desempenho::LeituraAutomatica::TravaDaConta
  POR = 6.hours

  def initialize(account)
    @chave = "autonomia:desempenho:leitura:#{account.id}:trava"
    @account_id = account.id
    @token = SecureRandom.hex(8)
  end

  # true quando pegou; false com outra rodada da conta em andamento.
  def pegar = Redis::Alfred.set(@chave, @token, nx: true, ex: POR.to_i).present?

  def renovar = Redis::Alfred.expire(@chave, POR.to_i)

  # Só solta a trava que é dela. Erro ao soltar (Redis fora do ar) só fica no log: a trava vence sozinha em POR, e a
  # rodada, já paga, não pode cair por isso.
  def soltar
    Redis::Alfred.delete_if_equals(@chave, @token)
  rescue StandardError => e
    Rails.logger.error("[desempenho][leitura] conta=#{@account_id} soltar_trava=#{e.class.name}")
  end
end
