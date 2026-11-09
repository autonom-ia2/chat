# #2850 (Refs #1431) — o vetor da pergunta, com prazo. O embedding da pergunta trava o turno do cliente enquanto espera:
# cada tentativa tem o prazo curto do EmbeddingService (sem as repetições do RubyLLM) e, numa falha passageira (prazo,
# conexão, provedor fora, limite de taxa), há no máximo uma nova tentativa, e só se ela couber inteira no orçamento.
#
# Sem vetor, toda falha deixa uma linha de log com o motivo, as tentativas, o tempo e o caminho que a busca segue. Com
# `so_palavra_sem_vetor`, devolve nil e a busca segue só pela palavra; sem ele, a falha sobe (o `retrieve` degrada para
# [] como sempre; o placar a vê). A falha que não passa (chave errada, por exemplo) sobe direto, sem nova tentativa.
class Autonomia::Agents::VetorDaPergunta
  MAX_TENTATIVAS = 2

  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def initialize(servico, agent_id:)
    @servico = servico
    @agent_id = agent_id
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
    Rails.logger.warn("[autonomia][retriever] embedding_falhou agent=#{@agent_id} motivo=#{erro.motivo} " \
                      "tentativas=#{tentativas} ms=#{((self.class.agora - inicio) * 1000).round} " \
                      "segue=#{so_palavra_sem_vetor ? 'so_palavra' : 'sem_busca'}")
    raise erro unless so_palavra_sem_vetor

    nil
  end
end
