# #1431 (F0) — o placar da RESPOSTA do agente, ao lado do placar da busca (PlacarDaBase). Cada pergunta passa pelo
# Answerer como no atendimento real, e o juiz do autoteste (outro modelo) dá o veredito pelo sentido:
# - acerto: nas perguntas que a base responde, a resposta traz o fato esperado ("certo");
# - recusa correta: nas de fora da base, o agente disse que não sabe ou passou para a equipe ("recusou"), sem inventar;
# - de onde veio: a resposta diz ter usado um trecho que contém a âncora (os `used_snippet_ids` que o modelo devolve).
# Juiz indisponível: a rodada sai como não julgada (nil), nunca como tudo errado. É IA paga: quem roda põe o teto.
class Autonomia::Agents::PlacarDaResposta
  def initialize(agent:, perguntas:, juiz: nil, responder: nil)
    @agent = agent
    @perguntas = perguntas
    @juiz = juiz || Autonomia::Agents::Material::JuizDoAutoteste.new(account: agent.account)
    @responder = responder || ->(texto) { Autonomia::Agents::Answerer.new(agent: agent, query: texto, trust_instruction: true).answer }
  end

  def medir
    respostas = @perguntas.map { |pergunta| [pergunta, @responder.call(pergunta.texto)] }
    vereditos = @juiz.julgar(respostas.map { |pergunta, resposta| item_do_juiz(pergunta, resposta) })
    itens = respostas.each_with_index.map { |(pergunta, resposta), indice| item(pergunta, resposta, vereditos&.at(indice)) }
    { agente: @agent.id, perguntas: itens.size, julgado: !vereditos.nil?, **taxas(itens, julgado: !vereditos.nil?), itens: itens }
  end

  private

  def taxas(itens, julgado:)
    fora, respondiveis = itens.partition { |item| item[:fora] }
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
      equipe: resposta.handoff.to_h[:should] == true,
      usou_a_ancora: usados.any? { |texto| Autonomia::Agents::PlacarDaBase.contem_ancora?(texto, pergunta.ancoras) }
    }
  end

  def taxa(itens, &)
    return nil if itens.empty?

    (itens.count(&).to_f / itens.size).round(4)
  end
end
