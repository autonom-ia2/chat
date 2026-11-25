# A METADE DE BAIXO DA CAPA do comparativo de Seguro Viagem (#3211): os seis dados da viagem em ladrilhos e o resumo
# com até três planos rotulados (mais econômica, mais recomendada, maior cobertura), na regra de `Rotulos`.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Resumo
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  Rotulos = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  ALTURA_DO_DADO = 56
  ALTURA_DO_CARTAO = 134
  ESPACO = 12
  RESPIRO = 14

  private

  def dados
    [['Destino', destinos_texto], ['Período', periodo_texto], ['Viajantes', "#{idades.size} · #{idades_texto}"],
     ['Parcelamento máximo', parcelas_maximas], ['Data da cotação', dia_da_cotacao], ['Válida até', valida_ate]]
  end

  # Os ladrilhos em 3 colunas. Devolve o topo logo abaixo deles.
  def dados_da_viagem(topo)
    largura = (largura_util - (2 * ESPACO)) / 3
    dados.each_with_index do |(nome, valor), indice|
      x = MARGEM + ((indice % 3) * (largura + ESPACO))
      topo_do_dado = topo + ((indice / 3) * (ALTURA_DO_DADO + ESPACO))
      ladrilho([x, topo_do_dado, largura], nome, valor)
    end
    topo + (2 * ALTURA_DO_DADO) + ESPACO
  end

  def ladrilho(caixa, nome, valor)
    x, topo, largura = caixa
    @doc.fill_color cor(:fundo)
    @doc.fill_rounded_rectangle [x, y_de(topo)], largura, ALTURA_DO_DADO, RAIO
    rotulo(nome, at: [x + RESPIRO, topo + RESPIRO], largura: largura - (2 * RESPIRO), size: 6.5)
    escrever(valor, at: [x + RESPIRO, topo + 27], largura: largura - (2 * RESPIRO), size: 10.5, style: :semibold,
                    cor: :marinho, height: 24, leading: 1, overflow: :shrink_to_fit)
  end

  # Os planos com rótulo, na ordem econômica, recomendada, maior cobertura.
  def destaques_do_resumo
    Rotulos::ORDEM_DO_RESUMO.filter_map do |nome|
      indice = rotulos.index(nome)
      [nome, planos[indice]] unless indice.nil?
    end
  end

  def resumo(topo)
    destaques = destaques_do_resumo
    return if destaques.empty?

    rotulo('Resumo da cotação', at: [MARGEM, topo], largura: largura_util, cor: :teal_texto)
    escrever('Os destaques desta viagem', at: [MARGEM, topo + 13], largura: largura_util, size: 17, style: :bold,
                                          cor: :marinho)
    largura = (largura_util - ((destaques.size - 1) * ESPACO)) / destaques.size
    destaques.each_with_index do |(nome, plano), indice|
      cartao_do_resumo([MARGEM + (indice * (largura + ESPACO)), topo + 44, largura, ALTURA_DO_CARTAO], nome, plano)
    end
    escrever('Nas próximas páginas: todos os planos lado a lado e o que conferir antes de contratar.',
             at: [MARGEM, topo + 44 + ALTURA_DO_CARTAO + 20], largura: largura_util, size: 8.5, cor: :suave)
  end

  def cartao_do_resumo(caixa, nome, plano)
    x, topo, largura = caixa
    interna = largura - (2 * 16)
    cartao(caixa)
    faixa_do_cartao(caixa, TONS.dig(nome, :faixa))
    selo(Rotulos::NOMES[nome], at: [x + 16, topo + 16], tons: TONS.dig(nome, :selo))
    escrever(plano['nome'], at: [x + 16, topo + 40], largura: interna, size: 12, style: :bold, cor: :marinho, height: 30,
                            overflow: :shrink_to_fit)
    escrever(preco(plano), at: [x + 16, topo + 76], largura: interna, size: 17, style: :bold, cor: :tinta)
    dmh = Rotulos.despesas_medicas_texto(plano) || SEM_VALOR
    linha_da_cobertura = { size: 8.5, cor: :suave, height: 22, overflow: :shrink_to_fit }
    escrever("#{dmh} em despesas médicas", at: [x + 16, topo + 102], largura: interna, **linha_da_cobertura)
  end
end
