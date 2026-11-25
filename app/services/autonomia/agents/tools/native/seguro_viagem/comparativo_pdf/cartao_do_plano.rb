# O CARTÃO DE UM PLANO em "Compare as opções" (#3211), desenhado de cima para baixo com as alturas que a
# `Comparacao` mediu (todos os cartões com as seções na mesma altura): selo do rótulo, nome, preço total, o valor para
# médico e hospital, o preço por pessoa e as outras coberturas. Cada bloco soma exatamente o que
# `Comparacao#altura_do_cartao` conta.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CartaoDoPlano
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  Rotulos = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  Comparacao = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Comparacao
  FIXAS = Comparacao::FIXAS

  private

  def cartao_do_plano(caixa, plano, rotulo_do_plano)
    fundo_do_cartao(caixa, rotulo_do_plano)
    x = caixa[0] + respiro_do_cartao
    topo = caixa[1] + respiro_do_cartao + FIXAS[:selo]
    escrever(plano['nome'], at: [x, topo], largura: interna, size: tamanho_do_nome, style: :bold, cor: :marinho)
    topo = preco_do_cartao(plano, [x, topo + alturas[:nome] + FIXAS[:folga]])
    topo = por_pessoa_do_cartao(plano, [x, topo])
    detalhes_do_cartao(plano, [x, topo])
  end

  # A recomendada ganha borda mais grossa na cor da marca; todo plano com rótulo ganha a faixa e o selo da cor dele.
  def fundo_do_cartao(caixa, nome_do_rotulo)
    recomendada = nome_do_rotulo == :recomendada
    cartao(caixa, borda: recomendada ? :teal : :linha, espessura: recomendada ? 1.4 : 0.7)
    return if nome_do_rotulo.nil?

    faixa_do_cartao(caixa, TONS.dig(nome_do_rotulo, :faixa))
    selo(Rotulos::NOMES[nome_do_rotulo], at: [caixa[0] + respiro_do_cartao, caixa[1] + respiro_do_cartao + 2],
                                         tons: TONS.dig(nome_do_rotulo, :selo))
  end

  # Preço total e, logo abaixo, o valor para médico e hospital. Devolve o topo logo abaixo.
  def preco_do_cartao(plano, posicao)
    x, topo = posicao
    rotulo('Valor total', at: [x, topo], largura: interna)
    escrever(preco(plano), at: [x, topo + 12], largura: interna, size: 20, style: :bold, cor: :tinta)
    topo += FIXAS[:preco]
    escrever(dmh_do_cartao(plano), at: [x, topo], largura: interna, cor: :teal_texto, **Comparacao::DMH)
    topo + alturas[:dmh] + FIXAS[:folga]
  end

  # O preço por pessoa, idades do mesmo preço juntas (some quando não há o que dividir). Devolve o topo logo abaixo.
  def por_pessoa_do_cartao(plano, posicao)
    x, topo = posicao
    linhas = linhas_por_pessoa(plano)
    return topo + alturas[:por_pessoa] if linhas.empty?

    rotulo('Por pessoa', at: [x, topo], largura: interna)
    linhas.reduce(topo + FIXAS[:por_pessoa]) do |atual, linha|
      escrever(linha, at: [x, atual], largura: interna, cor: :tinta, **Comparacao::POR_PESSOA)
      atual + altura_de(linha, largura: interna, **Comparacao::POR_PESSOA) + FIXAS[:entre_precos]
    end
    topo + alturas[:por_pessoa]
  end

  # As coberturas em linhas "nome ... valor" separadas por fio.
  def detalhes_do_cartao(plano, posicao)
    x, topo = posicao
    detalhes(plano).each_with_index.reduce(topo) do |atual, ((nome, valor), indice)|
      largura_do_nome, largura_do_valor = colunas_do_detalhe(nome)
      fio(x, atual, interna)
      texto = atual + FIXAS[:linha_de_detalhe]
      escrever(nome, at: [x, texto], largura: largura_do_nome, cor: :suave, **Comparacao::NOME_DO_DETALHE)
      escrever(valor, at: [x + interna - largura_do_valor, texto], largura: largura_do_valor, cor: :tinta, align: :right,
                      **Comparacao::VALOR_DO_DETALHE)
      atual + alturas[:detalhes][indice]
    end
  end

  def fio(esquerda, topo, largura)
    @doc.stroke_color cor(:linha)
    @doc.line_width 0.6
    @doc.stroke_horizontal_line esquerda, esquerda + largura, at: y_de(topo)
  end
end
