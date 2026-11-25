# O CARTÃO DE UM PLANO em "Compare as opções" (#3211), desenhado de cima para baixo com as alturas que a
# `Comparacao` mediu para a linha inteira (os cartões lado a lado ficam com as seções na mesma altura): selo do rótulo,
# nome, preço total, preço por idade, coberturas principais, botão "Ver coberturas" (link para as condições gerais) e
# a seguradora com o processo SUSEP. Cada bloco soma exatamente o que `Comparacao#altura_do_cartao` conta.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CartaoDoPlano
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  Rotulos = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  CondicoesGerais = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CondicoesGerais
  Comparacao = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Comparacao
  FIXAS = Comparacao::FIXAS

  private

  def cartao_do_plano(caixa, plano, indice, alturas)
    fundo_do_cartao(caixa, rotulos[indice])
    x = caixa[0] + respiro_do_cartao
    interna = caixa[2] - (2 * respiro_do_cartao)
    topo = caixa[1] + respiro_do_cartao + FIXAS[:selo]
    escrever(plano['nome'], at: [x, topo], largura: interna, size: 13, style: :bold, cor: :marinho)
    topo = preco_do_cartao(plano, [x, topo + alturas[:nome] + FIXAS[:folga], interna])
    topo = detalhes_do_cartao(plano, [x, topo, interna], alturas[:detalhes])
    fim_do_cartao([x, topo, interna])
  end

  # O recomendado ganha borda na cor da marca; todo plano com rótulo ganha a faixa e o selo da cor dele.
  def fundo_do_cartao(caixa, nome_do_rotulo)
    cartao(caixa, borda: nome_do_rotulo == :recomendada ? :teal : :linha)
    return if nome_do_rotulo.nil?

    faixa_do_cartao(caixa, TONS.dig(nome_do_rotulo, :faixa))
    selo(Rotulos::NOMES[nome_do_rotulo], at: [caixa[0] + respiro_do_cartao, caixa[1] + respiro_do_cartao + 2],
                                         tons: TONS.dig(nome_do_rotulo, :selo))
  end

  # Preço total e o preço de cada viajante pela idade. Devolve o topo logo abaixo.
  def preco_do_cartao(plano, posicao)
    x, topo, interna = posicao
    rotulo('Valor total', at: [x, topo], largura: interna, size: 6.5)
    escrever(preco(plano), at: [x, topo + 12], largura: interna, size: 20, style: :bold, cor: :tinta)
    topo += FIXAS[:preco]
    rotulo('Por pessoa', at: [x, topo], largura: interna, size: 6.5)
    topo += FIXAS[:por_pessoa]
    precos_por_idade(plano).each do |linha|
      escrever(linha, at: [x, topo], largura: interna, size: 8.5, cor: :suave)
      topo += FIXAS[:idade]
    end
    topo + FIXAS[:folga]
  end

  # As coberturas principais em linhas "rótulo ... valor" separadas por fio. Devolve o topo logo abaixo.
  def detalhes_do_cartao(plano, posicao, alturas)
    x, topo, interna = posicao
    nome_largura, valor_largura = colunas_do_detalhe(interna)
    detalhes(plano).each_with_index do |(nome, valor), indice|
      fio(x, topo, interna)
      escrever(nome, at: [x, topo + 6], largura: nome_largura, size: 8, cor: :suave)
      escrever(valor, at: [x + interna - valor_largura, topo + 6], largura: valor_largura, size: 8.5, style: :semibold,
                      cor: :tinta, align: :right)
      topo += alturas[indice]
    end
    fio(x, topo, interna)
    topo
  end

  def fio(esquerda, topo, largura)
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.6
    @doc.stroke_horizontal_line esquerda, esquerda + largura, at: y_de(topo)
  end

  # Botão "Ver coberturas" (12 de respiro em cima, 14 embaixo) e a seguradora.
  def fim_do_cartao(posicao)
    x, topo, interna = posicao
    url = CondicoesGerais.url
    botao('Ver coberturas  ↗', [x, topo + 12, interna, Comparacao::ALTURA_DO_BOTAO], url) unless url.nil?
    escrever(CondicoesGerais.rodape, at: [x, topo + FIXAS[:botao]], largura: interna, size: 6.5, leading: 1, cor: :fraca)
  end
end
