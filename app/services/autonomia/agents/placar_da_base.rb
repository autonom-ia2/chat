# #1431 (F0) — o placar da busca na base de um agente. Roda cada pergunta pelo Retriever de verdade e mede:
# - hit@k: a pergunta respondível acertou quando um dos k primeiros trechos contém uma das âncoras do gabarito.
#   A âncora é texto do material, não o id do pedaço: o placar vale entre dois cortes diferentes da mesma base.
# - MRR: média de 1/posição do primeiro acerto (0 quando nenhum trecho tem a âncora).
# - fora da base: a pergunta que a base não responde deveria voltar sem trecho.
# - distância: a menor distância VETORIAL de cada pergunta, por classe. O trecho que entra pelo reforço por palavra
#   tem uma distância fixa no Retriever, não medida: fica fora da distância e é contado à parte (`lexicais`).
# Só a busca, sem IA paga: o custo é o embedding das perguntas. Pergunta que não vira embedding PARA a rodada
# (BuscaFalhou): o Retriever devolveria [], e o placar leria a falha como "não achou". `resumo` tira o texto das
# perguntas, para o placar de uma base de cliente poder ir para docs/audit sem o material.
class Autonomia::Agents::PlacarDaBase
  KS = [1, 5, 12].freeze

  class BuscaFalhou < StandardError; end

  # `esperado`: o que o material responde, em palavras de gente, para o juiz da resposta (PlacarDaResposta). Opcional.
  # Gabarito com defeito é recusado na leitura: âncora em branco casaria com qualquer trecho, e pergunta respondível sem
  # âncora nunca acertaria.
  Pergunta = Data.define(:texto, :ancoras, :fora, :esperado) do
    def initialize(texto:, ancoras:, fora:, esperado: nil)
      raise ArgumentError, 'pergunta sem texto' if texto.to_s.strip.empty?
      raise ArgumentError, "fora precisa ser true ou false: #{texto}" unless [true, false].include?(fora)
      raise ArgumentError, "âncora em branco: #{texto}" if ancoras.any? { |ancora| ancora.to_s.strip.empty? }
      raise ArgumentError, "pergunta respondível sem âncora: #{texto}" if !fora && ancoras.empty?

      super
    end
  end

  def self.perguntas_do_arquivo(caminho)
    YAML.safe_load_file(caminho).fetch('perguntas').map do |item|
      Pergunta.new(texto: item.fetch('pergunta'), ancoras: Array(item['ancoras']), fora: item.fetch('fora', false),
                   esperado: item['esperado'])
    end
  end

  # A pasta do detalhe por pergunta, que carrega o material da base: nunca dentro de um checkout git (o repo é público).
  # Confere pelo caminho real da pasta existente mais próxima (resolve symlink, caminho relativo e maiúscula) e pelo
  # próprio git, que acha o repositório de qualquer checkout ou worktree.
  def self.pasta_de_saida(caminho)
    pasta = Pathname(caminho).expand_path
    existente = pasta.ascend.find(&:exist?)
    real = existente.realpath
    dentro_de_git = system('git', '-C', real.to_s, 'rev-parse', '--is-inside-work-tree', out: File::NULL, err: File::NULL)
    raise ArgumentError, 'SAIDA precisa ficar fora de qualquer repositório git' if dentro_de_git

    real.join(pasta.relative_path_from(existente))
  end

  # O texto contém uma das âncoras, sem contar maiúscula, acento nem espaço.
  def self.contem_ancora?(texto, ancoras)
    procurado = normalizar(texto)
    ancoras.any? { |ancora| procurado.include?(normalizar(ancora)) }
  end

  def self.normalizar(texto)
    I18n.transliterate(texto.to_s.downcase).squish
  end

  def self.resumo(placar)
    placar.except(:itens)
  end

  def initialize(agent:, perguntas:)
    @agent = agent
    @perguntas = perguntas
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
    conferir_embedding!(pergunta.texto)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    trechos = Autonomia::Agents::Retriever.new(agent: @agent).retrieve(pergunta.texto, top_k: KS.max)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    vetoriais = trechos.select { |trecho| trecho.has_attribute?(:neighbor_distance) }
    {
      pergunta: pergunta.texto, fora: pergunta.fora, posicao: posicao(trechos, pergunta.ancoras),
      trechos: trechos.size, lexicais: trechos.size - vetoriais.size, ms: ms,
      menor_distancia: vetoriais.filter_map { |trecho| trecho.neighbor_distance&.to_f }.min
    }
  end

  def conferir_embedding!(texto)
    @embedding ||= Autonomia::Agents::EmbeddingService.new(account: @agent.account)
    raise BuscaFalhou, 'embedding_vazio' if @embedding.embed(texto).blank?
  rescue Autonomia::Agents::EmbeddingService::EmbeddingError => e
    raise BuscaFalhou, e.message
  end

  def posicao(trechos, ancoras)
    indice = trechos.index { |trecho| self.class.contem_ancora?(trecho.content, ancoras) }
    indice && (indice + 1)
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
