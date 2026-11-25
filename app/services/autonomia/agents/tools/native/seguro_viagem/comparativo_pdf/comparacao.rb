# "COMPARE AS OPÇÕES" no comparativo de Seguro Viagem (#3211): um cartão por plano, 3 por linha (2 quando a cotação
# tem até 2 planos), com o selo do rótulo, o preço total, o preço de cada viajante pela idade, as coberturas principais,
# o link para as condições gerais e a seguradora.
#
# CARTÃO INTEIRO: a altura de cada linha de cartões é medida antes de desenhar; se não cabe no resto da folha, a linha
# vai inteira para a folha seguinte. Na mesma linha os cartões têm a mesma altura e as seções alinhadas.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Comparacao
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Rotulos = SeguroViagem::ComparativoPdf::Rotulos
  CondicoesGerais = SeguroViagem::ComparativoPdf::CondicoesGerais
  ESPACO = 14
  FIM_DA_AREA = 790
  ALTURA_DO_BOTAO = 26
  # As alturas fixas do cartÃ£o: atÃ© o nome (faixa e selo), o bloco do preÃ§o, o rÃ³tulo "por pessoa", cada idade, o botÃ£o
  # com os respiros e a folga entre blocos.
  FIXAS = { selo: 26, preco: 50, por_pessoa: 13, idade: 13.5, botao: ALTURA_DO_BOTAO + 26, folga: 10 }.freeze

  private

  def comparacao
    @doc.start_new_page
    inicio = cabecalho_da_comparacao(false)
    planos.each_with_index.each_slice(colunas).reduce(inicio) { |topo, linha| linha_de_cartoes(linha, topo) }
  end

  def largura_do_cartao
    (largura_util - ((colunas - 1) * ESPACO)) / colunas
  end

  # Uma linha de cartões, inteira nesta folha ou inteira na seguinte. Devolve o topo da próxima linha.
  def linha_de_cartoes(linha, topo)
    alturas = alturas_da_linha(linha.map(&:first), largura_do_cartao)
    altura = altura_do_cartao(alturas)
    if topo + altura > FIM_DA_AREA
      @doc.start_new_page
      topo = cabecalho_da_comparacao(true)
    end
    linha.each_with_index do |(plano, indice), coluna|
      caixa = [MARGEM + (coluna * (largura_do_cartao + ESPACO)), topo, largura_do_cartao, altura]
      cartao_do_plano(caixa, plano, indice, alturas)
    end
    topo + altura + ESPACO + 4
  end

  def colunas
    planos.size >= 3 ? 3 : 2
  end

  def respiro_do_cartao
    colunas == 3 ? 14 : 18
  end

  # Devolve o topo onde os cartões começam.
  def cabecalho_da_comparacao(continuacao)
    rotulo(continuacao ? 'Continuação' : 'Os planos desta cotação', at: [MARGEM, 44], largura: largura_util, cor: :teal_texto)
    escrever('Compare as opções', at: [MARGEM, 57], largura: largura_util, size: 24, style: :bold, cor: :marinho)
    escrever("Valores para #{viajantes_texto} (#{idades_texto}) · #{periodo_texto}",
             at: [MARGEM, 90], largura: largura_util, size: 9.5, cor: :suave)
    122
  end

  def detalhes(plano)
    [['Despesas médicas e hospitalares', Rotulos.despesas_medicas_texto(plano) || SEM_VALOR],
     ['Perda de bagagem', cobertura_texto(plano, SeguroViagem::Planos::IDS_BAGAGEM, 'bagagem')],
     ['Cancelamento de viagem', cobertura_texto(plano, SeguroViagem::Planos::IDS_CANCELAMENTO, 'cancelamento')],
     ['Parcelamento', parcelas_texto(plano['max_parcelas'])],
     ['Idades aceitas', idades_aceitas(plano)]]
  end

  def cobertura_texto(plano, ids, principal)
    cobertura = plano['coberturas'].to_a.find { |item| ids.include?(item['id_beneficio']) }
    cobertura.to_h['valor'].to_s.strip.presence || plano.dig('principais', principal).presence || SEM_VALOR
  end

  def idades_aceitas(plano)
    minima = plano['idade_minima']
    maxima = plano['idade_maxima']
    return SEM_VALOR if maxima.nil?

    minima.nil? ? "até #{maxima} anos" : "#{minima} a #{maxima} anos"
  end

  # As alturas que variam (nome, cada linha de detalhe, rodapé), a maior de cada uma entre os cartões da linha.
  def alturas_da_linha(planos_da_linha, largura)
    medidas = planos_da_linha.map { |plano| medidas_do_cartao(plano, largura - (2 * respiro_do_cartao)) }
    { nome: medidas.pluck(:nome).max, detalhes: medidas.pluck(:detalhes).transpose.map(&:max),
      rodape: medidas.pluck(:rodape).max }
  end

  # A linha de detalhe: o nome ocupa 58% da largura e o valor, alinhado à direita, o resto.
  def colunas_do_detalhe(interna)
    [(interna * 0.58) - 4, interna * 0.42]
  end

  def medidas_do_cartao(plano, interna)
    nome_largura, valor_largura = colunas_do_detalhe(interna)
    { nome: altura_de(plano['nome'], largura: interna, size: 13, style: :bold),
      detalhes: detalhes(plano).map do |nome, valor|
        [altura_de(nome, largura: nome_largura, size: 8),
         altura_de(valor, largura: valor_largura, size: 8.5, style: :semibold)].max + 12
      end,
      rodape: altura_de(CondicoesGerais.rodape, largura: interna, size: 6.5, leading: 1) }
  end

  def altura_do_cartao(alturas)
    (2 * respiro_do_cartao) + FIXAS[:selo] + alturas[:nome] + FIXAS[:folga] + FIXAS[:preco] + FIXAS[:por_pessoa] +
      (idades.size * FIXAS[:idade]) + FIXAS[:folga] + alturas[:detalhes].sum + FIXAS[:botao] + alturas[:rodape]
  end
end
