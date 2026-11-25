# A ÚLTIMA PARTE do comparativo de Seguro Viagem (#3211): "Antes de contratar". Logo abaixo da última fileira de
# cartões quando cabe até o rodapé; senão, numa folha nova. Um cartão com os pontos importantes (só o que a base do
# agente sustenta: o preço do dia, as regras completas, contratar antes do embarque, não é plano de saúde), a
# seguradora, o registro na SUSEP e o link das regras completas; e o cartão da marca com como contratar.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::AntesDeContratar
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  CondicoesGerais = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CondicoesGerais
  Comparacao = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Comparacao
  RESPIRO = 22
  ESPACO = 14
  ENTRE_PONTOS = 8
  TITULO = 32
  ALTURA_DO_BOTAO = 26
  PONTO = { size: 10, leading: 2 }.freeze
  SOBRE = { size: 9.5, leading: 2 }.freeze
  CHAMADA = { size: 14, style: :semibold, leading: 3 }.freeze
  LINK = 'Ler as regras completas do seguro  ↗'.freeze

  private

  def antes_de_contratar(topo)
    topo += 4
    if topo + altura_do_antes > Comparacao::FIM_DA_AREA
      @doc.start_new_page
      topo = 44
    end
    escrever('Antes de contratar', at: [MARGEM, topo], largura: largura_util, size: 20, style: :bold, cor: :marinho)
    topo = pontos_importantes(topo + TITULO)
    proximo_passo(topo + ESPACO)
  end

  def altura_do_antes
    TITULO + altura_dos_pontos + ESPACO + altura_do_proximo_passo
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

  def largura_interna
    largura_util - (2 * RESPIRO)
  end

  def largura_do_ponto
    largura_interna - 18
  end

  def alturas_dos_pontos
    pontos.map { |ponto| altura_de(ponto, **PONTO, largura: largura_do_ponto) }
  end

  # Os pontos, o fio, a seguradora e a SUSEP, e o botão das regras completas (se a base trouxer o link).
  def altura_dos_pontos
    botao = CondicoesGerais.url.nil? ? 0 : 12 + ALTURA_DO_BOTAO
    RESPIRO + alturas_dos_pontos.sum + (ENTRE_PONTOS * (pontos.size - 1)) + 28 +
      altura_de(sobre, largura: largura_interna, **SOBRE) + botao + RESPIRO
  end

  # Devolve o topo logo abaixo do cartão.
  def pontos_importantes(topo)
    altura = altura_dos_pontos
    cartao([MARGEM, topo, largura_util, altura])
    atual = lista_de_pontos(topo + RESPIRO)
    sobre_o_seguro(atual - ENTRE_PONTOS + 14)
    topo + altura
  end

  # Devolve o topo logo abaixo do último ponto (com a folga entre pontos).
  def lista_de_pontos(topo)
    pontos.zip(alturas_dos_pontos).reduce(topo) do |atual, (ponto, altura)|
      marcador(MARGEM + RESPIRO, atual)
      escrever(ponto, at: [MARGEM + RESPIRO + 18, atual], largura: largura_do_ponto, **PONTO)
      atual + altura + ENTRE_PONTOS
    end
  end

  def marcador(esquerda, topo)
    @doc.fill_color cor(:teal)
    @doc.fill_circle [esquerda + 4, y_de(topo + 6)], 3
  end

  def sobre_o_seguro(topo)
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.6
    @doc.stroke_horizontal_line MARGEM + RESPIRO, MARGEM + RESPIRO + largura_interna, at: y_de(topo)
    escrever(sobre, at: [MARGEM + RESPIRO, topo + 14], largura: largura_interna, cor: :suave, **SOBRE)
    url = CondicoesGerais.url
    return if url.nil?

    topo_do_botao = topo + 14 + altura_de(sobre, largura: largura_interna, **SOBRE) + 12
    botao(LINK, [MARGEM + RESPIRO, topo_do_botao, 250, ALTURA_DO_BOTAO], url)
  end

  def altura_do_proximo_passo
    RESPIRO + 18 + altura_de(chamada, largura: largura_interna, **CHAMADA) + RESPIRO
  end

  # O cartão em degradê da marca com como contratar.
  def proximo_passo(topo)
    altura = altura_do_proximo_passo
    @doc.fill_gradient from: [MARGEM, y_de(topo)], to: [MARGEM + largura_util, y_de(topo + altura)],
                       stops: [cor(:marinho), cor(:azul_marca)]
    @doc.fill_rounded_rectangle [MARGEM, y_de(topo)], largura_util, altura, RAIO
    rotulo('Próximo passo', at: [MARGEM + RESPIRO, topo + RESPIRO], largura: largura_interna, cor: :ciano)
    escrever(chamada, at: [MARGEM + RESPIRO, topo + RESPIRO + 18], largura: largura_interna, cor: :branco, **CHAMADA)
  end
end
