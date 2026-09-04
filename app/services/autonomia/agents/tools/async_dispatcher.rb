# DESPACHANTE das execuções assíncronas aceitas num turno (#313).
#
# Roda no fim do `Operate::Responder`, depois de a entrega do turno começar. É aqui que a execução
# sai de `pending` e vira trabalho de verdade.
#
# Por que não no `Bound`, no momento em que o modelo chama a ferramenta: naquele ponto o turno ainda
# pode morrer. A segunda chamada ao modelo (a que transforma a saída da ferramenta em resposta) não
# tem retry — um timeout ali devolve silêncio. Se o disparo já tivesse acontecido, o cliente
# receberia uma cotação 60 segundos depois sem nunca ter ouvido "vou cotar". Promovendo aqui, o
# turno que morre descarta a execução e o portal nunca é chamado.
#
# `notify_customer` responde à outra metade do mesmo problema: quando o turno entrega texto, quem
# avisa é o modelo; quando fica em silêncio, quem avisa é o job. O aviso não pode depender de o
# modelo lembrar de dar.
class Autonomia::Agents::Tools::AsyncDispatcher
  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig

  def initialize(delivery:, agent:)
    @delivery = delivery
    @agent = agent
  end

  # `replied` = o turno vai entregar texto ao cliente (então o modelo já avisou).
  # `expected_chunks` = quantos pedaços a entrega humanizada vai postar (0 ou 1 = mensagem única).
  # NUNCA levanta: falhar ao despachar não pode derrubar a resposta já entregue.
  def dispatch!(replied:, expected_chunks: 0)
    runs = @delivery&.runs.to_a
    return 0 if runs.empty?

    deadline = AsyncConfig.deadline_seconds_for(@agent).from_now
    runs.count do |run|
      promoted = run.promote!(expected_chunks: expected_chunks, notify_customer: !replied,
                              expires_at: deadline)
      ::Autonomia::Agents::Tools::AsyncRunJob.perform_later(run.id, 0) if promoted
      promoted
    end
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] dispatch failed agent=#{@agent&.id} #{e.class}")
    0
  end

  # O turno morreu antes de entregar qualquer coisa: descarta o que foi aceito, sem chamar o portal.
  def discard!
    @delivery&.runs.to_a.each(&:discard!)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] discard failed agent=#{@agent&.id} #{e.class}")
    nil
  end
end
