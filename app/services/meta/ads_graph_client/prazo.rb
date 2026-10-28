# Prazo de quem chama (Seus posts, #2304), parte do Meta::AdsGraphClient: `prazo:` é o relógio monotônico até o qual
# quem chama espera. Cada requisição usa só o que falta dele (inclusive cada página de uma lista); passado o prazo, a
# requisição nem sai e volta com o erro TEMPO. O timeout do HTTParty vale para cada etapa da requisição (conectar, cada
# leitura), não para ela inteira: uma resposta que chega aos poucos pode passar do prazo uma vez, e a próxima já não sai.
module Meta::AdsGraphClient::Prazo
  # Código próprio (não é da Meta) do pedido que não saiu ou não voltou dentro do prazo de quem chamou.
  TEMPO = 'tempo'.freeze

  private

  # Segundos até o prazo de quem chama; sem prazo, nil.
  def restante
    @prazo && (@prazo - Process.clock_gettime(Process::CLOCK_MONOTONIC))
  end

  def passou_do_prazo?
    @prazo.present? && restante <= 0
  end

  def sem_tempo
    Meta::AdsGraphClient::Result.new(ok: false, http_code: nil, data: nil, error_code: TEMPO,
                                     error_message: 'passou do prazo de quem chamou')
  end
end
