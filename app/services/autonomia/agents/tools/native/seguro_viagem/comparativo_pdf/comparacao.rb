# "COMPARE AS OPÇÕES" no comparativo de Seguro Viagem (#3211): um cartão por plano, 3 por fileira (2 quando a cotação
# tem até 2 planos), do mais barato ao mais caro, com o selo do rótulo, o preço total, o valor para médico e hospital,
# o preço por pessoa e as outras coberturas principais. O link das condições gerais e a SUSEP ficam na última parte.
#
# CARTÃO INTEIRO: todos os cartões têm a mesma altura (a do maior), medida antes de desenhar, e as seções alinhadas;
# uma fileira que não cabe no resto da folha vai inteira para a seguinte. Com a altura fixa, a 1ª folha tem um número
# certo de vagas, e a recomendada sempre cai numa delas (`Ordem.com_recomendada_ate`).
#
# FALTA DE COBERTURA: a Universal manda, em cada plano, a lista inteira dos benefícios dele (o catálogo da resposta é
# a soma dessas listas; conferido na cotação real gravada). Com a lista, cobertura ausente é "Não inclui"; sem lista
# nenhuma, não dá para afirmar: "Não informado".
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Comparacao
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  Rotulos = SeguroViagem::ComparativoPdf::Rotulos
  Ordem = SeguroViagem::ComparativoPdf::Ordem
  Textos = SeguroViagem::ComparativoPdf::Textos
  ESPACO = 12
  ENTRE_FILEIRAS = 16
  INICIO = 122
  FIM_DA_AREA = 790
  NAO_INCLUI = 'Não inclui'.freeze
  NAO_INFORMADO = 'Não informado'.freeze
  # As alturas fixas do cartão: até o nome (faixa e selo), o rótulo e o preço total, o rótulo "Por pessoa", a folga
  # entre blocos, o respiro em cima e embaixo do texto de cada linha de cobertura e o espaço entre linhas de preço.
  FIXAS = { selo: 25, preco: 37, por_pessoa: 12, folga: 7, linha_de_detalhe: 5, entre_precos: 0.5 }.freeze
  NOME_DO_DETALHE = { size: 9.5 }.freeze
  VALOR_DO_DETALHE = { size: 10, style: :semibold }.freeze
  DMH = { size: 11, style: :semibold }.freeze
  POR_PESSOA = { size: 9.5 }.freeze

  private

  # Devolve onde ficou a última fileira: `topo` dela, quantos cartões `ocupadas` tem e o `fim` (a borda de baixo).
  def comparacao
    @doc.start_new_page
    inicio = cabecalho_da_comparacao(false)
    ultima = cartoes.each_slice(colunas).reduce(nil) do |anterior, fileira|
      topo = anterior.nil? ? inicio : anterior[:fim] + ENTRE_FILEIRAS
      topo = fileira_de_cartoes(fileira, topo)
      { topo: topo, ocupadas: fileira.size, fim: topo + altura_do_cartao }
    end
    ultima || { topo: inicio, ocupadas: colunas, fim: inicio - ENTRE_FILEIRAS }
  end

  # [[plano, rótulo], ...] na ordem dos cartões.
  def cartoes
    Ordem.com_recomendada_ate(planos.zip(rotulos), rotulos.index(:recomendada), vagas_da_primeira_folha)
  end

  def vagas_da_primeira_folha
    fileiras = ((FIM_DA_AREA - INICIO + ENTRE_FILEIRAS) / (altura_do_cartao + ENTRE_FILEIRAS)).floor
    [fileiras, 1].max * colunas
  end

  def largura_do_cartao
    (largura_util - ((colunas - 1) * ESPACO)) / colunas
  end

  def interna
    largura_do_cartao - (2 * respiro_do_cartao)
  end

  # Uma fileira de cartões, inteira nesta folha ou inteira na seguinte. Devolve o topo onde ela ficou.
  def fileira_de_cartoes(fileira, topo)
    if topo + altura_do_cartao > FIM_DA_AREA
      @doc.start_new_page
      topo = cabecalho_da_comparacao(true)
    end
    fileira.each_with_index do |(plano, rotulo_do_plano), coluna|
      caixa = [MARGEM + (coluna * (largura_do_cartao + ESPACO)), topo, largura_do_cartao, altura_do_cartao]
      cartao_do_plano(caixa, plano, rotulo_do_plano)
    end
    topo
  end

  def colunas
    planos.size >= 3 ? 3 : 2
  end

  def respiro_do_cartao
    colunas == 3 ? 12 : 18
  end

  def tamanho_do_nome
    colunas == 3 ? 12 : 14
  end

  # Devolve o topo onde os cartões começam.
  def cabecalho_da_comparacao(continuacao)
    rotulo(continuacao ? 'Continuação' : 'Os planos desta cotação', at: [MARGEM, 44], largura: largura_util, cor: :teal_texto)
    escrever('Compare as opções', at: [MARGEM, 57], largura: largura_util, size: 24, style: :bold, cor: :marinho)
    escrever("Valores para #{viajantes_texto} (#{idades_texto}) · #{periodo_texto}",
             at: [MARGEM, 90], largura: largura_util, size: 10, cor: :suave)
    INICIO
  end

  def detalhes(plano)
    [['Bagagem perdida', cobertura_texto(plano, SeguroViagem::Planos::IDS_BAGAGEM, 'bagagem')],
     ['Cancelamento', cobertura_texto(plano, SeguroViagem::Planos::IDS_CANCELAMENTO, 'cancelamento')],
     ['Parcelamento', parcelas_texto(plano['max_parcelas'])],
     ['Idades aceitas', idades_aceitas(plano)]]
  end

  def cobertura_texto(plano, ids, principal)
    lista = plano['coberturas'].to_a
    cobertura = lista.find { |item| ids.include?(item['id_beneficio']) }
    texto = cobertura.to_h['valor'].to_s.strip.presence || plano.dig('principais', principal).presence
    return texto unless texto.nil?

    lista.empty? ? NAO_INFORMADO : NAO_INCLUI
  end

  def idades_aceitas(plano)
    minima = plano['idade_minima']
    maxima = plano['idade_maxima']
    return NAO_INFORMADO if maxima.nil?

    minima.nil? ? "até #{maxima} anos" : "#{minima} a #{maxima} anos"
  end

  def dmh_do_cartao(plano)
    para_medico_e_hospital(plano, interna, **DMH)
  end

  # "47, 19 e 12 anos: R$ 120,00 cada"; sem caber numa linha, quebra depois das idades.
  def linhas_por_pessoa(plano)
    Textos.precos_por_pessoa(plano, idades).map do |quem, valor|
      texto = "#{quem}: #{valor}"
      @doc.width_of(texto, **POR_PESSOA) <= interna ? texto : "#{quem}:\n#{valor}"
    end
  end

  # A linha de detalhe: o nome à esquerda na largura dele; o valor, à direita, no resto (quebra se precisar).
  def colunas_do_detalhe(nome)
    largura_do_nome = @doc.width_of(nome, **NOME_DO_DETALHE) + 1
    [largura_do_nome, interna - largura_do_nome - 6]
  end

  # As alturas que variam, a maior de cada uma entre todos os cartões (todos ficam com a mesma altura).
  def alturas
    @alturas ||= begin
      medidas = planos.map { |plano| medidas_do_cartao(plano) }
      { nome: medidas.pluck(:nome).max, dmh: medidas.pluck(:dmh).max, por_pessoa: medidas.pluck(:por_pessoa).max,
        detalhes: medidas.pluck(:detalhes).transpose.map(&:max) }
    end
  end

  def medidas_do_cartao(plano)
    { nome: altura_de(plano['nome'], largura: interna, size: tamanho_do_nome, style: :bold),
      dmh: altura_de(dmh_do_cartao(plano), largura: interna, **DMH),
      por_pessoa: altura_por_pessoa(plano),
      detalhes: detalhes(plano).map do |nome, valor|
        largura_do_nome, largura_do_valor = colunas_do_detalhe(nome)
        [altura_de(nome, largura: largura_do_nome, **NOME_DO_DETALHE),
         altura_de(valor, largura: largura_do_valor, **VALOR_DO_DETALHE)].max + (2 * FIXAS[:linha_de_detalhe])
      end }
  end

  def altura_por_pessoa(plano)
    linhas = linhas_por_pessoa(plano)
    return 0 if linhas.empty?

    FIXAS[:por_pessoa] + linhas.sum { |linha| altura_de(linha, largura: interna, **POR_PESSOA) + FIXAS[:entre_precos] } +
      FIXAS[:folga]
  end

  def altura_do_cartao
    @altura_do_cartao ||= (2 * respiro_do_cartao) + FIXAS[:selo] + alturas[:nome] + FIXAS[:folga] + FIXAS[:preco] +
                          alturas[:dmh] + FIXAS[:folga] + alturas[:por_pessoa] + alturas[:detalhes].sum
  end
end
