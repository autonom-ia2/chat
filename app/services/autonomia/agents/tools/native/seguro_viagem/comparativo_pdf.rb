# O COMPARATIVO EM PDF do Seguro Viagem (#3211): o material que o cliente guarda e mostra em casa, com a marca da
# Universal Assistance e a corretora como quem envia. Sai da cotação guardada (`planos` no formato de `Planos.de`) e
# não lê banco nem chama a seguradora. A4 em pé:
# 1. capa: faixa da marca, o plano mais recomendado em destaque, os dados da viagem e o resumo com os rótulos;
# 2. "Compare as opções": um cartão por plano (`Comparacao`), sem cartão partido entre páginas;
# 3. "Antes de contratar": os pontos importantes e o próximo passo.
# Os rótulos (mais econômica, mais recomendada, maior cobertura) seguem a regra fixa de `Rotulos`.
#
# O QUE NUNCA ENTRA (R2): comissão, markup, ranking, `id_produto`, o código interno do plano (`P1`) e dado pessoal.
# `Planos.de` já não traz comissão nem ranking; aqui só se leem as chaves que os blocos citam. Do cliente só as idades.
class Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf
  include Desenho
  include Capa
  include Resumo
  include Comparacao
  include CartaoDoPlano
  include AntesDeContratar

  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  TITULO = 'Seguro Viagem: comparativo de planos'.freeze

  def initialize(cotacao:, nome_corretora:)
    @cotacao = cotacao
    @nome_corretora = nome_corretora.to_s.strip
  end

  # -> os bytes do PDF (`%PDF-`).
  def render
    @doc = Prawn::Document.new(page_size: 'A4', page_layout: :portrait, margin: 0, info: { Title: TITULO })
    registrar_fontes
    capa
    comparacao
    antes_de_contratar
    rodapes
    @doc.render
  end

  private

  def planos
    @planos ||= @cotacao.planos.to_a
  end

  def rotulos
    @rotulos ||= Rotulos.de(planos)
  end

  def pedido
    @pedido ||= @cotacao.pedido.to_h
  end

  def idades
    @cotacao.idades
  end

  # O nome por extenso (`destinos_nomes`); cotação antiga, sem ele, mostra as siglas.
  def destinos
    nomes = pedido['destinos_nomes'].to_a.compact_blank
    nomes.presence || pedido['destinos'].to_a
  end

  def destinos_texto
    destinos.to_sentence(words_connector: ', ', two_words_connector: ' e ', last_word_connector: ' e ')
  end

  def viajantes_texto
    idades.size == 1 ? '1 viajante' : "#{idades.size} viajantes"
  end

  def idades_texto
    lista = idades.map(&:to_s).to_sentence(words_connector: ', ', two_words_connector: ' e ', last_word_connector: ' e ')
    "#{lista} #{idades.size == 1 && idades.first == 1 ? 'ano' : 'anos'}"
  end

  def saida
    data(pedido['data_saida'])
  end

  def retorno
    data(pedido['data_retorno'])
  end

  def periodo_texto
    return SEM_VALOR if saida.nil? || retorno.nil?

    dias = (retorno - saida).to_i + 1
    "#{saida.strftime('%d/%m')} a #{retorno.strftime('%d/%m/%Y')} · #{dias} #{dias == 1 ? 'dia' : 'dias'}"
  end

  def parcelas_texto(parcelas)
    parcelas.to_i.positive? ? "até #{parcelas.to_i}x" : SEM_VALOR
  end

  def parcelas_maximas
    parcelas_texto(planos.map { |plano| plano['max_parcelas'].to_i }.max)
  end

  def preco(plano)
    plano['preco_total'].blank? ? SEM_VALOR : SeguroViagem::Dinheiro.brl(plano['preco_total'])
  end

  # -> ["47 anos: R$ 120,00", ...] na ordem das idades.
  def precos_por_idade(plano)
    SeguroViagem::Faixas.precos_por_pessoa(plano, idades).each_with_index.map do |valor, indice|
      idade = idades[indice]
      "#{idade} #{idade == 1 ? 'ano' : 'anos'}: #{valor.nil? ? SEM_VALOR : SeguroViagem::Dinheiro.brl(valor)}"
    end
  end

  # A cotação vale para o dia em que foi feita, no fuso da conta (o do servidor é UTC e viraria o dia perto da
  # meia-noite); é a mesma regra de `CotacaoDeViagem#do_dia?`.
  def momento_da_cotacao
    fuso = Crm::Timezone::Resolver.new(account: @cotacao.account).zone_or_default
    @cotacao.created_at.in_time_zone(fuso)
  end

  def dia_da_cotacao
    momento_da_cotacao.strftime('%d/%m/%Y')
  end

  def valida_ate
    "#{dia_da_cotacao}, 23h59"
  end

  def preparada_por
    @nome_corretora.empty? ? nil : "Cotação preparada por #{@nome_corretora}"
  end

  def data(texto)
    Date.iso8601(texto.to_s)
  rescue Date::Error
    nil
  end

  def rodapes
    total = @doc.page_count
    (1..total).each do |pagina|
      @doc.go_to_page(pagina)
      rodape_da_pagina("Página #{pagina} de #{total}")
    end
  end

  def rodape_da_pagina(numero)
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.6
    @doc.stroke_horizontal_line MARGEM, FOLHA[:largura] - MARGEM, at: y_de(FOLHA[:altura] - 34)
    esquerda = [preparada_por, 'Planos Universal Assistance'].compact.join(' · ')
    escrever(esquerda, at: [MARGEM, FOLHA[:altura] - 27], largura: 380, size: 7, cor: :fraca)
    escrever(numero, at: [FOLHA[:largura] - MARGEM - 100, FOLHA[:altura] - 27], largura: 100, size: 7, cor: :fraca, align: :right)
  end
end
