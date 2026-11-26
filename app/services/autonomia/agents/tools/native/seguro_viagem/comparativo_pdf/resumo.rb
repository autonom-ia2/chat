# A METADE DE BAIXO DA CAPA do comparativo de Seguro Viagem (#3211): os três dados da viagem em ladrilhos (o destino
# já está no selo da faixa) e o resumo com até três planos rotulados, do mais barato ao mais caro.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Resumo
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  Rotulos = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  ALTURA_DO_DADO = 62
  ALTURA_DO_CARTAO = 172
  ESPACO = 12
  RESPIRO = 14
  RESPIRO_DO_CARTAO = 16
  DMH_DO_RESUMO = { size: 9.5, style: :semibold }.freeze

  private

  def dados
    [['Período', periodo_texto], ['Viajantes', "#{idades.size} · #{idades_texto}"], ['Preço vale até', valida_ate]]
  end

  # Os ladrilhos numa fileira. Devolve o topo logo abaixo deles.
  def dados_da_viagem(topo)
    largura = (largura_util - (2 * ESPACO)) / 3
    dados.each_with_index do |(nome, valor), indice|
      ladrilho([MARGEM + (indice * (largura + ESPACO)), topo, largura], nome, valor)
    end
    topo + ALTURA_DO_DADO
  end

  def ladrilho(caixa, nome, valor)
    x, topo, largura = caixa
    @doc.fill_color cor(:fundo)
    @doc.fill_rounded_rectangle [x, y_de(topo)], largura, ALTURA_DO_DADO, RAIO
    rotulo(nome, at: [x + RESPIRO, topo + RESPIRO], largura: largura - (2 * RESPIRO))
    escrever(valor, at: [x + RESPIRO, topo + 29], largura: largura - (2 * RESPIRO), size: 10.5, style: :semibold,
                    cor: :marinho, height: 26, leading: 1, overflow: :shrink_to_fit, min_font_size: 9)
  end

  # Os planos com rótulo, do mais barato ao mais caro (a ordem de `planos`).
  def destaques_do_resumo
    planos.each_with_index.filter_map do |plano, indice|
      nome = rotulos[indice]
      [nome, plano] if Rotulos::NOMES.key?(nome) && nome != :disponivel
    end
  end

  # Devolve o topo logo abaixo do resumo.
  def resumo(topo)
    destaques = destaques_do_resumo
    return topo if destaques.empty?

    rotulo('Resumo da cotação', at: [MARGEM, topo], largura: largura_util, cor: :teal_texto)
    escrever('Os destaques desta viagem', at: [MARGEM, topo + 14], largura: largura_util, size: 17, style: :bold,
                                          cor: :marinho)
    largura = (largura_util - ((destaques.size - 1) * ESPACO)) / destaques.size
    destaques.each_with_index do |(nome, plano), indice|
      cartao_do_resumo([MARGEM + (indice * (largura + ESPACO)), topo + 50, largura, ALTURA_DO_CARTAO], nome, plano)
    end
    topo + 50 + ALTURA_DO_CARTAO
  end

  # O nome cabe em até 3 linhas; nome mais longo encolhe até 10 pt.
  def cartao_do_resumo(caixa, nome, plano)
    recomendada = nome == :recomendada
    cartao(caixa, borda: recomendada ? :teal : :linha, espessura: recomendada ? 1.4 : 0.7)
    faixa_do_cartao(caixa, TONS.dig(nome, :faixa))
    x = caixa[0] + RESPIRO_DO_CARTAO
    topo = caixa[1]
    largura = caixa[2] - (2 * RESPIRO_DO_CARTAO)
    selo(Rotulos::NOMES[nome], at: [x, topo + 20], tons: TONS.dig(nome, :selo))
    escrever(plano['nome'], at: [x, topo + 48], largura: largura, size: 12, style: :bold, cor: :marinho, height: 46,
                            overflow: :shrink_to_fit, min_font_size: 10)
    escrever(preco(plano), at: [x, topo + 104], largura: largura, size: 17, style: :bold, cor: :tinta)
    escrever(para_medico_e_hospital(plano, largura, **DMH_DO_RESUMO), at: [x, topo + 130], largura: largura, cor: :teal_texto,
                                                                      height: 26, overflow: :shrink_to_fit, min_font_size: 9,
                                                                      **DMH_DO_RESUMO)
  end
end
