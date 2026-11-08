# O corpo de um passo "ação" com valor calculado (G16 do fechamento do #2414). Três formas fechadas, numa folha do
# corpo (também dentro de custom_attributes); nada de fórmula nem eval:
# - `{"$valor": "card.responsavel_id"}`: copia um valor da lista fechada do Valores;
# - `{"$texto": ["indicado por ", {"$valor": "contato.nome"}]}`: os pedaços do texto da mensagem (Texto);
# - `{"$data": {"de": "hoje", "mais": {"valor": 6, "unidade": "meses"}}}`, ou `"de": {"$valor": "<atributo de data>"}`.
#   Sai "AAAA-MM-DD", o que a tela grava num atributo do tipo data (attributeDate) e no campo de data do card. "Hoje" é
#   o dia da execução no fuso da conta, nunca o do salvar. Mês e ano pelo calendário: 31/01 + 1 mês = 28/02.
#
# Valor lido vazio: o corpo inteiro não sai, e o passo pula com o motivo. Nunca grava "indicado por " pela metade.
class Autonomia::Automacao::Corpo
  FORMAS = %w[$valor $texto $data].freeze
  HOJE = 'hoje'.freeze
  UNIDADES = { 'dias' => :days, 'semanas' => :weeks, 'meses' => :months, 'anos' => :years }.freeze
  # O corpo pronto, ou o motivo de não sair (faltou_valor, data_invalida).
  Montado = Struct.new(:corpo, :motivo, keyword_init: true)
  Pula = Class.new(StandardError)

  class << self
    def calculado?(valor) = valor.is_a?(Hash) && FORMAS.any? { |forma| valor.key?(forma) }

    def calculado_em?(corpo) = folhas(corpo).any?

    # Cada valor calculado do corpo.
    def folhas(corpo) = lugares(corpo).map(&:last)

    # [[onde, folha]]: onde são as chaves (e os índices) do corpo até a folha, para o `dig`.
    def lugares(corpo, onde = [])
      return [[onde, corpo]] if calculado?(corpo)

      filhos(corpo).flat_map { |chave, filho| lugares(filho, onde + [chave]) }
    end

    # Os caminhos que o corpo lê, para o salvar conferir como confere os do caminho e os da condição.
    def caminhos(corpo)
      folhas(corpo).flat_map do |folha|
        next [folha['$valor']] if folha.key?('$valor')
        next ::Autonomia::Automacao::Texto.caminhos(folha['$texto']) if folha.key?('$texto')

        Array(de_valor(folha))
      end
    end

    # Chave com "$" que não é uma das formas: quem montou esperava um cálculo que não existe ("$soma"), e gravar o texto
    # literal seria falhar em silêncio.
    def formas_desconhecidas(corpo)
      proprias = corpo.is_a?(Hash) ? corpo.keys.select { |chave| chave.to_s.start_with?('$') && FORMAS.exclude?(chave.to_s) } : []
      proprias + filhos(corpo).flat_map { |_chave, filho| formas_desconhecidas(filho) }
    end

    # O "de" de cada data que lê um valor (e não "hoje"): o salvar confere que é um atributo de data.
    def datas(corpo) = folhas(corpo).filter_map { |folha| de_valor(folha) }

    # O corpo com cada valor calculado trocado pelo que o bloco devolve (onde: as chaves até a folha).
    def trocar(corpo, onde = [], &)
      return yield(onde, corpo) if calculado?(corpo)

      case corpo
      when Hash then corpo.to_h { |chave, valor| [chave, trocar(valor, onde + [chave], &)] }
      when Array then corpo.each_with_index.map { |valor, indice| trocar(valor, onde + [indice], &) }
      else corpo
      end
    end

    # O corpo para a Conferência do formato no salvar: cada valor calculado vira um exemplo que o campo de destino
    # aceita (CampoDaAcao). O valor de verdade só existe ao executar, e o motor confere o formato de novo com ele.
    def exemplo(acao, corpo)
      campos = ::Autonomia::Automacao::CampoDaAcao.new(acao)
      trocar(corpo) { |onde, folha| campos.exemplo(onde, folha) }
    end

    private

    def filhos(corpo)
      case corpo
      when Hash then corpo.to_a
      when Array then corpo.each_with_index.map { |valor, indice| [indice, valor] }
      else []
      end
    end

    def de_valor(folha)
      de = folha['$data'].is_a?(Hash) ? folha['$data']['de'] : nil
      de['$valor'] if de.is_a?(Hash)
    end
  end

  def initialize(corpo, valores:, conta:)
    @corpo = corpo.to_h
    @valores = valores
    @conta = conta
  end

  def montar
    Montado.new(corpo: self.class.trocar(@corpo) { |_onde, folha| resolver(folha) })
  rescue Pula => e
    Montado.new(motivo: e.message)
  end

  private

  def resolver(folha)
    valor = lido(folha)
    raise Pula, 'faltou_valor' if vazio?(valor)

    valor
  end

  def lido(folha)
    return @valores.ler(folha['$valor']) if folha.key?('$valor')
    return ::Autonomia::Automacao::Texto.new(folha['$texto'], @valores).montar if folha.key?('$texto')

    data(folha['$data'])
  end

  # false é valor (um atributo "sim/não" desmarcado); vazio é nada, texto só de espaços ou lista vazia. Dentro de um
  # `$texto`, o pedaço segue a regra do texto da mensagem (Texto): false conta como vazio, e a ação pula.
  def vazio?(valor) = valor.nil? || (valor.is_a?(String) && valor.strip.empty?) || (valor.respond_to?(:empty?) && valor.empty?)

  def data(forma)
    base = forma['de'] == HOJE ? hoje : lida(forma['de']['$valor'])
    mais = forma['mais']
    (mais ? base.advance(UNIDADES.fetch(mais['unidade']) => mais['valor']) : base).iso8601
  end

  # O dia de hoje no fuso que a tela grava na conta (#954), o mesmo do extrair e do Guia.
  def hoje
    fuso = ::Crm::Timezone::Resolver.new(explicit: @conta.custom_attributes.to_h['timezone'], account: @conta).zone_or_default
    Time.current.in_time_zone(fuso).to_date
  end

  # O atributo de data guarda "AAAA-MM-DD" (a tela corta a hora, como aqui; o que vem depois de "T" ou de espaço). Fora
  # disso, não é data: pula com o motivo.
  def lida(caminho)
    texto = @valores.ler(caminho).to_s
    raise Pula, 'faltou_valor' if texto.strip.empty?

    Date.iso8601(texto.split('T').first.split.first)
  rescue Date::Error
    raise Pula, 'data_invalida'
  end
end
