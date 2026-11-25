# A ÚLTIMA FOLHA do comparativo de Seguro Viagem (#3211): "Antes de contratar". Os pontos importantes (só o que a base
# do agente sustenta: cotação do dia, condições gerais, contratar antes do embarque, não é plano de saúde), o próximo
# passo na conversa e a seguradora com o link das condições gerais.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::AntesDeContratar
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  CondicoesGerais = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CondicoesGerais
  RESPIRO = 24
  ESPACO = 16
  ENTRE_PONTOS = 10
  PONTO = { size: 10, leading: 2 }.freeze
  CHAMADA = { size: 15, style: :semibold, leading: 3 }.freeze
  PROXIMO_PASSO = 'Escolha o plano e responda na conversa: a gente prepara a proposta e manda o link de pagamento.'.freeze

  private

  def antes_de_contratar
    @doc.start_new_page
    rotulo('Para decidir com segurança', at: [MARGEM, 44], largura: largura_util, cor: :teal_texto)
    escrever('Antes de contratar', at: [MARGEM, 57], largura: largura_util, size: 24, style: :bold, cor: :marinho)
    escrever('O que vale saber antes de escolher o plano.', at: [MARGEM, 90], largura: largura_util, size: 9.5, cor: :suave)
    topo = pontos_importantes(122)
    topo = proximo_passo(topo + ESPACO)
    sobre_o_seguro(topo + ESPACO)
  end

  def pontos
    ["Os valores valem para a data desta cotação (#{dia_da_cotacao}) e podem mudar até a emissão do seguro.",
     'Coberturas, limites e exclusões estão nas condições gerais do seguro.',
     'O seguro precisa ser contratado antes do embarque.',
     'Seguro viagem não substitui plano de saúde.']
  end

  def largura_do_ponto
    largura_util - (2 * RESPIRO) - 18
  end

  # Devolve o topo logo abaixo do cartão.
  def pontos_importantes(topo)
    alturas = pontos.map { |ponto| altura_de(ponto, **PONTO, largura: largura_do_ponto) }
    altura = RESPIRO + 30 + alturas.sum + (ENTRE_PONTOS * (pontos.size - 1)) + RESPIRO
    cartao([MARGEM, topo, largura_util, altura])
    escrever('Pontos importantes', at: [MARGEM + RESPIRO, topo + RESPIRO], largura: largura_util, size: 13, style: :bold,
                                   cor: :marinho)
    lista_de_pontos(topo + RESPIRO + 30, alturas)
    topo + altura
  end

  def lista_de_pontos(topo, alturas)
    pontos.each_with_index.reduce(topo) do |atual, (ponto, indice)|
      marcador(MARGEM + RESPIRO, atual)
      escrever(ponto, at: [MARGEM + RESPIRO + 18, atual], largura: largura_do_ponto, **PONTO)
      atual + alturas[indice] + ENTRE_PONTOS
    end
  end

  def marcador(esquerda, topo)
    @doc.fill_color cor(:teal)
    @doc.fill_circle [esquerda + 4, y_de(topo + 6)], 3
  end

  # O cartão em degradê da marca com o próximo passo e a validade. Devolve o topo logo abaixo dele.
  def proximo_passo(topo)
    largura = largura_util - (2 * RESPIRO)
    altura_do_texto = altura_de(PROXIMO_PASSO, **CHAMADA, largura: largura)
    altura = RESPIRO + 20 + altura_do_texto + 14 + altura_de(validade, largura: largura, size: 9) + RESPIRO
    cartao_da_marca(topo, altura)
    textos_do_proximo_passo([MARGEM + RESPIRO, topo + RESPIRO, largura], altura_do_texto)
    topo + altura
  end

  def cartao_da_marca(topo, altura)
    @doc.fill_gradient from: [MARGEM, y_de(topo)], to: [MARGEM + largura_util, y_de(topo + altura)],
                       stops: [cor(:marinho), cor(:azul_marca)]
    @doc.fill_rounded_rectangle [MARGEM, y_de(topo)], largura_util, altura, RAIO
  end

  def validade
    ["Cotação válida até #{valida_ate}", preparada_por].compact.join(' · ')
  end

  def textos_do_proximo_passo(posicao, altura_do_texto)
    x, topo, largura = posicao
    rotulo('Próximo passo', at: [x, topo], largura: largura, cor: :ciano)
    escrever(PROXIMO_PASSO, at: [x, topo + 20], largura: largura, cor: :branco, **CHAMADA)
    escrever(validade, at: [x, topo + 20 + altura_do_texto + 14], largura: largura, size: 9, cor: :heroi_texto)
  end

  def sobre_o_seguro(topo)
    url = CondicoesGerais.url
    altura = url.nil? ? 58 : 92
    @doc.fill_color cor(:fundo)
    @doc.fill_rounded_rectangle [MARGEM, y_de(topo)], largura_util, altura, RAIO
    rotulo('Sobre o seguro', at: [MARGEM + RESPIRO, topo + 20], largura: largura_util)
    escrever(CondicoesGerais.rodape, at: [MARGEM + RESPIRO, topo + 34], largura: largura_util - (2 * RESPIRO), size: 9,
                                     cor: :tinta)
    botao('Ver as condições gerais  ↗', [MARGEM + RESPIRO, topo + 54, 170, 24], url) unless url.nil?
  end
end
