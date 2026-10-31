# #1431 (F0) — o placar da busca na base de um agente. Roda cada pergunta pelo Retriever de verdade e mede:
# - hit@k: a pergunta respondível acertou quando um dos k primeiros trechos contém uma das âncoras do gabarito.
#   A âncora é texto do material, não o id do pedaço: o placar vale entre dois cortes diferentes da mesma base.
# - MRR: média de 1/posição do primeiro acerto (0 quando nenhum trecho tem a âncora).
# - fora da base: a pergunta que a base não responde deveria voltar sem trecho.
# - distância: a menor distância de cada pergunta, por classe, para calibrar os limites a partir de dados.
# Só a busca, sem IA paga: o custo é o embedding das perguntas. `resumo` tira o texto das perguntas, para o placar
# de uma base de cliente poder ir para docs/audit sem o material.
class Autonomia::Agents::PlacarDaBase
  KS = [1, 5, 12].freeze

  Pergunta = Data.define(:texto, :ancoras, :fora)

  def self.perguntas_do_arquivo(caminho)
    YAML.safe_load_file(caminho).fetch('perguntas').map do |item|
      Pergunta.new(texto: item.fetch('pergunta'), ancoras: Array(item['ancoras']), fora: item['fora'] == true)
    end
  end

  def self.resumo(placar)
    placar.except(:itens)
  end

  def initialize(agent:, perguntas:, top_k: KS.max)
    @agent = agent
    @perguntas = perguntas
    @top_k = top_k
  end

  def medir
    itens = @perguntas.map { |pergunta| medir_pergunta(pergunta) }
    fora, respondiveis = itens.partition { |item| item[:fora] }
    {
      agente: @agent.id, perguntas: itens.size, respondiveis: respondiveis.size, fora: fora.size,
      **acertos(respondiveis),
      fora_sem_trecho: taxa(fora) { |item| item[:trechos].zero? },
      distancia: { respondiveis: distribuicao(respondiveis), fora: distribuicao(fora) },
      ms: media(itens.pluck(:ms)),
      itens: itens
    }
  end

  private

  def acertos(respondiveis)
    {
      hit: KS.index_with { |k| taxa(respondiveis) { |item| item[:posicao]&.<=(k) } },
      mrr: media(respondiveis.map { |item| item[:posicao] ? 1.0 / item[:posicao] : 0.0 })
    }
  end

  def medir_pergunta(pergunta)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    trechos = Autonomia::Agents::Retriever.new(agent: @agent).retrieve(pergunta.texto, top_k: @top_k)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    {
      pergunta: pergunta.texto, fora: pergunta.fora, posicao: posicao(trechos, pergunta.ancoras),
      trechos: trechos.size, menor_distancia: trechos.map { |trecho| trecho.neighbor_distance.to_f }.min, ms: ms
    }
  end

  def posicao(trechos, ancoras)
    procuradas = ancoras.map { |ancora| normalizar(ancora) }
    indice = trechos.index { |trecho| procuradas.any? { |ancora| normalizar(trecho.content).include?(ancora) } }
    indice && (indice + 1)
  end

  def normalizar(texto)
    I18n.transliterate(texto.to_s.downcase).squish
  end

  def taxa(itens, &)
    return nil if itens.empty?

    (itens.count(&).to_f / itens.size).round(4)
  end

  def media(valores)
    return nil if valores.empty?

    (valores.sum.to_f / valores.size).round(4)
  end

  def distribuicao(itens)
    valores = itens.filter_map { |item| item[:menor_distancia] }.sort
    return { mediana: nil, p90: nil, minimo: nil } if valores.empty?

    { mediana: percentil(valores, 0.5), p90: percentil(valores, 0.9), minimo: valores.first.round(4) }
  end

  def percentil(ordenados, fracao)
    ordenados[((ordenados.size - 1) * fracao).round].round(4)
  end
end
