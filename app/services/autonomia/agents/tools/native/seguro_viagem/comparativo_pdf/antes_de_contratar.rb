# A ÚLTIMA PARTE do comparativo de Seguro Viagem (#3211): "Antes de contratar". Um cartão com os pontos importantes
# (só o que a base do agente sustenta: o preço do dia, as regras completas, contratar antes do embarque, não é plano de
# saúde), a seguradora, o registro na SUSEP e o link das regras completas.
#
# ONDE ENTRA, nesta ordem:
# 1. ao lado dos últimos planos, quando a última fileira tem 2 vagas ou mais livres e o cartão cabe ali até o rodapé:
#    alinhado em cima com a fileira, com o título dentro, como mais um cartão dela;
# 2. embaixo da última fileira, na largura toda, quando cabe até o rodapé;
# 3. numa folha nova.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::AntesDeContratar
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  CondicoesGerais = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CondicoesGerais
  Comparacao = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Comparacao
  TITULO_DA_PARTE = 'Antes de contratar'.freeze
  RESPIRO = 22
  ENTRE_PONTOS = 8
  TITULO = 32
  TITULO_DENTRO = 30
  VAGAS_AO_LADO = 2
  ALTURA_DO_BOTAO = 26
  LARGURA_DO_BOTAO = 250
  PONTO = { size: 10, leading: 2 }.freeze
  SOBRE = { size: 9.5, leading: 2 }.freeze
  LINK = 'Ler as regras completas do seguro  ↗'.freeze

  private

  # `ultima`: onde ficou a última fileira de cartões (`Comparacao#comparacao`).
  def antes_de_contratar(ultima)
    lado = ao_lado(ultima)
    return cartao_de_pontos(lado, titulo_dentro: true) unless lado.nil?

    topo = ultima[:fim] + Comparacao::ENTRE_FILEIRAS + 4
    if topo + TITULO + altura_do_cartao_de_pontos(largura_util, titulo_dentro: false) > Comparacao::FIM_DA_AREA
      @doc.start_new_page
      topo = 44
    end
    escrever(TITULO_DA_PARTE, at: [MARGEM, topo], largura: largura_util, size: 20, style: :bold, cor: :marinho)
    cartao_de_pontos([MARGEM, topo + TITULO, largura_util], titulo_dentro: false)
  end

  # [x, topo, largura] do cartão ao lado dos últimos planos, ou nil quando não há vagas ou não cabe até o rodapé.
  def ao_lado(ultima)
    return nil if colunas - ultima[:ocupadas] < VAGAS_AO_LADO

    x = MARGEM + (ultima[:ocupadas] * (largura_do_cartao + Comparacao::ESPACO))
    largura = largura_util - (x - MARGEM)
    cabe = ultima[:topo] + altura_do_cartao_de_pontos(largura, titulo_dentro: true) <= Comparacao::FIM_DA_AREA
    cabe ? [x, ultima[:topo], largura] : nil
  end

  def pontos
    ["O preço vale para hoje, #{dia_da_cotacao}. Se contratar depois, ele pode mudar.",
     'O que o seguro cobre e o que não cobre está nas regras completas (condições gerais).',
     'O seguro precisa ser contratado antes do embarque.',
     'Seguro viagem não substitui plano de saúde.']
  end

  def sobre
    [CondicoesGerais.seguradora, CondicoesGerais.registro_susep].join("\n")
  end

  def alturas_dos_pontos(interna)
    pontos.map { |ponto| altura_de(ponto, **PONTO, largura: interna - 18) }
  end

  # O título (se for dentro), os pontos, o fio, a seguradora e a SUSEP, e o botão das regras completas (se a base
  # trouxer o link).
  def altura_do_cartao_de_pontos(largura, titulo_dentro:)
    interna = largura - (2 * RESPIRO)
    botao = CondicoesGerais.url.nil? ? 0 : 12 + ALTURA_DO_BOTAO
    RESPIRO + (titulo_dentro ? TITULO_DENTRO : 0) + alturas_dos_pontos(interna).sum + (ENTRE_PONTOS * (pontos.size - 1)) +
      28 + altura_de(sobre, largura: interna, **SOBRE) + botao + RESPIRO
  end

  def cartao_de_pontos(posicao, titulo_dentro:)
    x, topo, largura = posicao
    cartao([x, topo, largura, altura_do_cartao_de_pontos(largura, titulo_dentro: titulo_dentro)])
    esquerda = x + RESPIRO
    interna = largura - (2 * RESPIRO)
    escrever(TITULO_DA_PARTE, at: [esquerda, topo + RESPIRO], largura: interna, size: 16, style: :bold, cor: :marinho) if titulo_dentro
    atual = lista_de_pontos([esquerda, topo + RESPIRO + (titulo_dentro ? TITULO_DENTRO : 0), interna])
    sobre_o_seguro([esquerda, atual - ENTRE_PONTOS + 14, interna])
  end

  # Devolve o topo logo abaixo do último ponto (com a folga entre pontos).
  def lista_de_pontos(posicao)
    x, topo, interna = posicao
    pontos.zip(alturas_dos_pontos(interna)).reduce(topo) do |atual, (ponto, altura)|
      marcador(x, atual)
      escrever(ponto, at: [x + 18, atual], largura: interna - 18, **PONTO)
      atual + altura + ENTRE_PONTOS
    end
  end

  def marcador(esquerda, topo)
    @doc.fill_color cor(:teal)
    @doc.fill_circle [esquerda + 4, y_de(topo + 6)], 3
  end

  def sobre_o_seguro(posicao)
    x, topo, interna = posicao
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.6
    @doc.stroke_horizontal_line x, x + interna, at: y_de(topo)
    escrever(sobre, at: [x, topo + 14], largura: interna, cor: :suave, **SOBRE)
    url = CondicoesGerais.url
    return if url.nil?

    topo_do_botao = topo + 14 + altura_de(sobre, largura: interna, **SOBRE) + 12
    botao(LINK, [x, topo_do_botao, [LARGURA_DO_BOTAO, interna].min, ALTURA_DO_BOTAO], url)
  end
end
