# #1431 (F0) — o placar da RESPOSTA do agente, ao lado do placar da busca (PlacarDaBase). Cada pergunta passa pelo
# Answerer como no autoteste do material (`prova: true`: sem ferramentas do agente, sem busca na web, nada sai para
# fora), com a instrução tratada como no atendimento. O juiz do placar (JuizDoPlacar, outro modelo, que recebe os trechos
# usados) dá o veredito pelo sentido:
# - acerto: nas perguntas que a base responde, a resposta traz o fato esperado ("certo");
# - recusa correta: nas de fora da base, o agente disse que não sabe ou passou para a equipe ("recusou"), sem inventar;
# - de onde veio: a resposta diz ter usado um trecho que contém a âncora (os `used_snippet_ids` que o modelo devolve).
# Resposta que falhou (IA fora) não vai ao juiz nem entra nas taxas: é contada em `erros`. Juiz indisponível, ou nenhuma
# resposta válida: a rodada sai como não julgada (nil), nunca como tudo errado. Falha da BUSCA no meio da resposta não
# chega aqui (no atendimento o Answerer a degrada para "sem trecho") e sai como resposta: por isso os "errados" do juiz
# são revistos à mão. É IA paga: um MedidorDeCusto por execução, dividido entre os agentes, para antes do teto.
class Autonomia::Agents::PlacarDaResposta
  FEATURE = 'agente_placar_resposta'.freeze

  def self.resumo(placar)
    placar.except(:itens)
  end

  def initialize(agent:, perguntas:, medidor:, juiz: nil, responder: nil)
    @agent = agent
    @perguntas = perguntas
    @medidor = medidor
    @juiz = juiz || Autonomia::Agents::JuizDoPlacar.new(account: agent.account)
    @responder = responder || method(:responder_do_autoteste)
  end

  def medir
    gasto_antes = @medidor.gasto
    respondidas = responder_no_teto
    validas = respondidas.each_index.reject { |indice| respondidas[indice].last.error.present? }
    vereditos = julgar(respondidas, validas)
    itens = respondidas.each_with_index.map { |(pergunta, resposta), indice| item(pergunta, resposta, vereditos&.dig(indice)) }
    contagem(respondidas.size, validas.size, itens, julgado: !vereditos.nil?)
      .merge(gasto_usd: (@medidor.gasto - gasto_antes).round(4), itens: itens)
  end

  private

  def contagem(respondidas, validas, itens, julgado:)
    {
      agente: @agent.id, perguntas: @perguntas.size, respondidas: respondidas, interrompido: respondidas < @perguntas.size,
      erros: respondidas - validas, julgado: julgado, **taxas(itens, julgado: julgado)
    }
  end

  def responder_do_autoteste(texto)
    Autonomia::Agents::Answerer.new(agent: @agent, query: texto, feature: FEATURE, prova: true,
                                    trust_instruction: Autonomia::Agents::Playground.como_no_atendimento?(@agent)).answer
  end

  def responder_no_teto
    @perguntas.each_with_object([]) do |pergunta, feitas|
      break feitas unless @medidor.cabe?(:resposta)

      feitas << [pergunta, @medidor.medir(:resposta) { @responder.call(pergunta.texto) }]
    end
  end

  # { índice da resposta => veredito } (pelo índice: a mesma pergunta pode vir duas vezes no gabarito), ou nil quando o
  # juiz não julgou (nenhuma resposta válida, juiz falhou, ou não coube no teto).
  def julgar(respondidas, validas)
    return if validas.empty? || !@medidor.cabe?(:juiz)

    vereditos = @medidor.medir(:juiz) { @juiz.julgar(validas.map { |indice| item_do_juiz(*respondidas[indice]) }) }
    vereditos && validas.zip(vereditos).to_h
  end

  def taxas(itens, julgado:)
    fora, respondiveis = itens.reject { |item| item[:erro] }.partition { |item| item[:fora] }
    {
      respondiveis: respondiveis.size, fora: fora.size,
      acerto: julgado ? taxa(respondiveis) { |item| item[:veredito] == 'certo' } : nil,
      recusa_correta: julgado ? taxa(fora) { |item| item[:veredito] == 'recusou' } : nil,
      de_onde_veio: taxa(respondiveis) { |item| item[:usou_a_ancora] }
    }
  end

  def item_do_juiz(pergunta, resposta)
    {
      'origem' => pergunta.fora ? 'fora' : 'material', 'pergunta' => pergunta.texto,
      'esperado' => pergunta.fora ? nil : (pergunta.esperado.presence || pergunta.ancoras.join(' / ')),
      'resposta' => resposta.reply.to_s, 'equipe' => resposta.handoff.to_h[:should] == true, 'trechos' => trechos_usados(resposta)
    }
  end

  def item(pergunta, resposta, veredito)
    usados = trechos_usados(resposta)
    {
      pergunta: pergunta.texto, fora: pergunta.fora, resposta: resposta.reply.to_s, veredito: veredito,
      erro: resposta.error.presence, equipe: resposta.handoff.to_h[:should] == true, trechos_usados: usados,
      usou_a_ancora: usados.any? { |texto| Autonomia::Agents::PlacarDaBase.contem_ancora?(texto, pergunta.ancoras) }
    }
  end

  def trechos_usados(resposta)
    Array(resposta.used_knowledge).pluck(:content)
  end

  def taxa(itens, &)
    return nil if itens.empty?

    (itens.count(&).to_f / itens.size).round(4)
  end
end
