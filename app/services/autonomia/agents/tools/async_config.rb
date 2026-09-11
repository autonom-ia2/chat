# Parâmetros da ESPERA de uma ferramenta assíncrona (#313).
#
# Ficam num arquivo próprio, e não no `Agents::Config` já enorme, porque são todos do mesmo assunto:
# quanto tempo esperar, de quanto em quanto tempo perguntar de novo, e quando desistir.
#
# A progressão (3, 3, 5, 5, 8, 8…) é decisão do PO: o fluxo de referência esperava 15 segundos fixos
# antes da primeira checagem e só entregava quando TODAS as seguradoras respondiam — uma cotação que
# terminava em 5s era entregue aos 15, e uma seguradora travada segurava as outras 21. Perguntar cedo
# e espaçar depois detecta rápido o que é rápido sem gerar dezenas de chamadas no que é lento.
#
# TODO parâmetro passa por clamp. O `config` do agente é gravável por API pelo admin da conta
# (`agents_controller#agent_params` permite `config: {}`), e um job que se re-agenda sozinho NÃO é
# coberto pelo `max_retries: 3` do Sidekiq — re-enfileiramento voluntário não é retry. Sem clamp,
# `{"async_poll_intervals": [0]}` viraria laço sem freio.
module Autonomia::Agents::Tools::AsyncConfig
  BOOLEAN = ActiveModel::Type::Boolean.new

  # Progressão default, em segundos. O último valor se repete até o teto de tempo.
  DEFAULT_INTERVALS = [3, 3, 5, 5, 8, 8, 13, 13, 21].freeze
  MIN_INTERVAL_SECONDS = 2
  MAX_INTERVAL_SECONDS = 60
  MAX_INTERVALS = 16

  # Teto de tempo de PAREDE. É ele que encerra a execução, não a contagem de tentativas: contagem
  # não sobrevive a um re-enfileiramento perdido, relógio sobrevive.
  #
  # 420s vem de MEDIÇÃO, não de palpite: numa cotação real de auto em 04/09/2026, 3 de 6 seguradoras
  # devolveram preço em ~35s, mas o portal só assentou a cotação aos 392s e ainda não tinha
  # terminado aos 435s. O valor anterior (180s) teria encerrado a execução com as retardatárias
  # ainda vivas. O cliente não espera por isso: a entrega parcial já mandou os preços aos ~35s — o
  # prazo só decide quando desistimos de quem ficou para trás.
  DEFAULT_DEADLINE_SECONDS = 420
  MIN_DEADLINE_SECONDS = 30
  MAX_DEADLINE_SECONDS = 600

  # Cinto sobre o relógio: mesmo com deadline generoso, uma ferramenta que devolve `running` para
  # sempre não pode gerar tentativas infinitas.
  MAX_ATTEMPTS = 60

  # Quando há uma cadeia de entrega humanizada em curso, a publicação assíncrona ESPERA em vez de se
  # intercalar entre dois pedaços da mesma frase. Cada espera é curta e limitada.
  PUBLISH_DEFER_SECONDS = 3
  MAX_PUBLISH_DEFERRALS = 30

  # NÃO EXISTE TETO DE COTAÇÃO POR CONVERSA, E ISSO É DECISÃO DE PRODUTO.
  #
  # Havia um: 8 execuções por hora. Entrou sem aprovação e contava a unidade errada — uma execução
  # aciona todas as seguradoras habilitadas (17 na conta de teste), então "8 por hora" eram até 136
  # consultas, e o número 8 não dizia nada sobre dinheiro.
  #
  # Rodrigo removeu o teto em 10/09/2026, e o motivo não é técnico: **quem paga a cotação é a
  # corretora**. Uma corretora grande cota mais, fecha mais negócio e tem retorno maior. Estrangular
  # o cliente que paga mais é o oposto do produto. Medir para cobrar e mostrar retorno é a entrega 7
  # (`Insurance::Medida`, entregue em 11/09/2026); frear é outra coisa, e frear não é o que se quer
  # aqui — `medida_nao_e_freio_spec` reprova quem chamar a medida de dentro do caminho da cotação.
  #
  # O que continua impedindo desperdício NÃO é teto:
  #   - `turn_already_opened?` (bound.rb) — o retry do mesmo turno não abre execução nova;
  #   - a dedup por (conversa, ferramenta) — duas ao mesmo tempo não acontecem;
  #   - e a entrega 10, que compara os DADOS do pedido: "e aí, saiu?" tem os mesmos dados e não
  #     abre; qualquer campo diferente abre. Enquanto ela não existir, a impaciência do cliente
  #     gera cotação duplicada no portal do corretor — que é sujeira, não prejuízo nosso.
  #
  # TRÊS guardas seguram esta decisão, e quem reintroduzir teto derruba pelo menos uma — obrigado a
  # encarar a decisão em vez de repetir o acidente. `async_config_sem_teto_de_execucoes_spec` pega o
  # NOME (a constante copiada de volta de um diff antigo: MAX_RUNS, PER_HOUR, TETO/LIMITE por HORA…),
  # e só o nome. O COMPORTAMENTO tem um exemplo por porta em que a contagem poderia entrar:
  # `bound_async_spec` no aceite (vinte execuções na última hora, 340 seguradoras, e a vigésima
  # primeira é aceita) e `async_run_job_spec` no job, onde a chamada paga acontece (com as mesmas
  # vinte, a consulta e a submissão seguem). Até 11/09/2026 este comentário apontava para um arquivo
  # que não existia; até a rodada 3 da entrega 7 ele prometia cobertura do job que só o aceite tinha.

  module_function

  # Kill-switch global (ENV, default ON) + override por agente. OFF em qualquer camada -> a
  # ferramenta assíncrona recusa o disparo e devolve erro nomeado ao modelo (que decide o que dizer),
  # em vez de sumir do catálogo — o operador precisa ver no Testar que a ferramenta existe.
  def enabled?(agent = nil)
    return false unless BOOLEAN.cast(ENV.fetch('AI_AGENT_ASYNC_TOOLS', true))
    return true if agent.nil?

    cfg = agent.config.is_a?(Hash) ? agent.config['async_tools'] : nil
    cfg.nil? || BOOLEAN.cast(cfg)
  end

  # Progressão efetiva do agente, sempre saneada: valores fora de [MIN, MAX] são clampados, valores
  # não numéricos somem, lista vazia cai no default.
  def intervals_for(agent = nil)
    raw = agent&.config.is_a?(Hash) ? agent.config['async_poll_intervals'] : nil
    parsed = Array(raw).filter_map do |value|
      seconds = numeric(value)
      seconds.positive? ? seconds.clamp(MIN_INTERVAL_SECONDS, MAX_INTERVAL_SECONDS) : nil
    end
    parsed.first(MAX_INTERVALS).presence || DEFAULT_INTERVALS
  end

  # Intervalo até a PRÓXIMA consulta, dada a tentativa já feita (base zero). Depois do fim da
  # progressão, repete o último valor.
  def interval_for(agent, attempt)
    list = intervals_for(agent)
    index = attempt.to_i.clamp(0, list.length - 1)
    list[index].seconds
  end

  def deadline_seconds_for(agent = nil)
    seconds = numeric(agent&.config.is_a?(Hash) ? agent.config['async_deadline_seconds'] : nil)
    return DEFAULT_DEADLINE_SECONDS.seconds unless seconds.positive?

    seconds.clamp(MIN_DEADLINE_SECONDS, MAX_DEADLINE_SECONDS).seconds
  end

  # `config` é jsonb livre, gravável por API pelo admin da conta: pode chegar Hash ou Array onde se
  # esperava número, e `Hash#to_f` nem existe. Um NoMethodError aqui mataria a re-agenda do polling
  # e deixaria a execução pendurada — então tipo inesperado vale zero e cai no default.
  def numeric(value)
    value.respond_to?(:to_f) ? value.to_f : 0.0
  end
end
