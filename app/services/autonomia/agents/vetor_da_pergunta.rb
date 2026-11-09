# #2850 (Refs #1431) — o vetor da pergunta, com prazo. O embedding da pergunta trava o turno do cliente enquanto espera:
# cada tentativa tem o prazo curto do EmbeddingService (sem as repetições do RubyLLM) e, numa falha passageira (prazo,
# conexão, provedor fora, limite de taxa), há no máximo uma nova tentativa, e só se ela couber inteira no orçamento.
#
# Sem vetor, toda falha deixa uma linha de log com o motivo, as tentativas, o tempo e o caminho que a busca segue. Com
# `so_palavra_sem_vetor`, devolve nil e a busca segue só pela palavra; sem ele, a falha sobe (o `retrieve` degrada para
# [] como sempre; o placar a vê). A falha que não passa (chave errada, por exemplo) sobe direto, sem nova tentativa.
#
# Telemetria: um contador por dia, conta, motivo e caminho no Redis (o log de produção some), guardado GUARDA.
class Autonomia::Agents::VetorDaPergunta
  MAX_TENTATIVAS = 2
  GUARDA = 30.days

  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.chave(account_id, motivo, segue, dia = Date.current)
    "autonomia:retriever:sem_vetor:#{dia.iso8601}:#{account_id}:#{motivo}:#{segue}"
  end

  def initialize(servico, agent:)
    @servico = servico
    @agent = agent
  end

  # -> Array<Float> ([] para pergunta vazia), ou nil quando a busca segue só pela palavra.
  def calcular(query, so_palavra_sem_vetor:)
    inicio = self.class.agora
    tentativas = 0
    begin
      tentativas += 1
      @servico.embed(query)
    rescue Autonomia::Agents::EmbeddingService::Passageira => e
      retry if cabe_outra_tentativa?(tentativas, inicio)

      sem_vetor(e, tentativas, inicio, so_palavra_sem_vetor)
    end
  end

  private

  def cabe_outra_tentativa?(tentativas, inicio)
    tentativas < MAX_TENTATIVAS &&
      self.class.agora - inicio + Autonomia::Agents::Config::PRAZO_DO_EMBEDDING_S <= Autonomia::Agents::Config::ORCAMENTO_DO_EMBEDDING_S
  end

  def sem_vetor(erro, tentativas, inicio, so_palavra_sem_vetor)
    segue = so_palavra_sem_vetor ? 'so_palavra' : 'sem_busca'
    Rails.logger.warn("[autonomia][retriever] embedding_falhou agent=#{@agent.id} motivo=#{erro.motivo} " \
                      "tentativas=#{tentativas} ms=#{((self.class.agora - inicio) * 1000).round} segue=#{segue}")
    contar(erro.motivo, segue)
    raise erro unless so_palavra_sem_vetor

    nil
  end

  def contar(motivo, segue)
    chave = self.class.chave(@agent.account_id, motivo, segue)
    Redis::Alfred.incr(chave)
    Redis::Alfred.expire(chave, GUARDA.to_i)
  rescue Redis::BaseError => e
    Rails.logger.warn("[autonomia][retriever] telemetria_falhou agent=#{@agent.id} #{e.class}")
  end
end
