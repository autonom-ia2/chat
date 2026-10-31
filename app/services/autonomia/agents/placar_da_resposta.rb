# #1431 (F0) — o placar da RESPOSTA do agente, ao lado do placar da busca (PlacarDaBase). Cada pergunta passa pelo
# Answerer como no autoteste do material (`prova: true`: sem ferramentas do agente, sem busca na web, nada sai para
# fora), com a instrução tratada como no atendimento. O juiz do autoteste (outro modelo) dá o veredito pelo sentido:
# - acerto: nas perguntas que a base responde, a resposta traz o fato esperado ("certo");
# - recusa correta: nas de fora da base, o agente disse que não sabe ou passou para a equipe ("recusou"), sem inventar;
# - de onde veio: a resposta diz ter usado um trecho que contém a âncora (os `used_snippet_ids` que o modelo devolve).
# Resposta que falhou (IA fora) não vai ao juiz nem entra nas taxas: é contada em `erros`. Juiz indisponível: a rodada sai
# como não julgada (nil), nunca como tudo errado. É IA paga: o MedidorDeCusto do autoteste para a rodada antes do teto.
class Autonomia::Agents::PlacarDaResposta
  FEATURE = 'agente_placar_resposta'.freeze

  def self.resumo(placar)
    placar.except(:itens)
  end

  def initialize(agent:, perguntas:, juiz: nil, responder: nil, teto_usd: Autonomia::Agents::Material::MedidorDeCusto::TETO_USD)
    @agent = agent
    @perguntas = perguntas
    @juiz = juiz || Autonomia::Agents::Material::JuizDoAutoteste.new(account: agent.account)
    @responder = responder || method(:responder_do_autoteste)
    @medidor = Autonomia::Agents::Material::MedidorDeCusto.new(teto: teto_usd)
  end

  def medir
    respondidas = responder_no_teto
    validas = respondidas.reject { |_, resposta| resposta.error.present? }
    vereditos = julgar(validas)
    itens = respondidas.map { |pergunta, resposta| item(pergunta, resposta, vereditos&.dig(pergunta)) }
    {
      agente: @agent.id, perguntas: @perguntas.size, respondidas: respondidas.size,
      interrompido: respondidas.size < @perguntas.size, erros: respondidas.size - validas.size,
      julgado: !vereditos.nil?, **taxas(itens, julgado: !vereditos.nil?), gasto_usd: @medidor.gasto.round(4), itens: itens
    }
  end

  private

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

  # { pergunta => veredito }, ou nil quando o juiz não julgou (falhou, ou não coube no teto).
  def julgar(validas)
    return {} if validas.empty?
    return unless @medidor.cabe?(:juiz)

    vereditos = @medidor.medir(:juiz) { @juiz.julgar(validas.map { |pergunta, resposta| item_do_juiz(pergunta, resposta) }) }
    vereditos && validas.map(&:first).zip(vereditos).to_h
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
      'resposta' => resposta.reply.to_s, 'equipe' => resposta.handoff.to_h[:should] == true
    }
  end

  def item(pergunta, resposta, veredito)
    usados = Array(resposta.used_knowledge).pluck(:content)
    {
      pergunta: pergunta.texto, fora: pergunta.fora, resposta: resposta.reply.to_s, veredito: veredito,
      erro: resposta.error.presence, equipe: resposta.handoff.to_h[:should] == true,
      usou_a_ancora: usados.any? { |texto| Autonomia::Agents::PlacarDaBase.contem_ancora?(texto, pergunta.ancoras) }
    }
  end

  def taxa(itens, &)
    return nil if itens.empty?

    (itens.count(&).to_f / itens.size).round(4)
  end
end
