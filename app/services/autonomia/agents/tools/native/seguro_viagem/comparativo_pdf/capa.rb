# A CAPA do comparativo de Seguro Viagem (#3211): a faixa em degradê com o logo da Universal Assistance, a corretora
# que envia, o título e o selo da viagem; e o cartão do plano em destaque sobre a borda da faixa, com o porquê. Os dados
# da viagem, o resumo com os rótulos e a chamada para contratar, logo abaixo, são do `Resumo`.
#
# A faixa não encosta na borda da folha (`RECUO`): impressora não imprime até a borda, e o fundo cortado parece erro.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Capa
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  Rotulos = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  LOGO = Rails.root.join('lib/assets/images/seguro_viagem/universal-assistance.png').freeze
  RECUO = 18
  RAIO_DA_FAIXA = 18
  ALTURA_DA_FAIXA = 300
  TOPO_DO_DESTAQUE = 236
  RESPIRO = 22
  LARGURA_DO_PRECO = 170
  PORQUE = { size: 10, leading: 2 }.freeze
  DMH_DO_DESTAQUE = { size: 12, style: :semibold }.freeze

  private

  def capa
    faixa_da_capa
    textos_da_capa
    topo = destaque(TOPO_DO_DESTAQUE)
    topo = dados_da_viagem(topo + 20)
    topo = resumo(topo + 26) if planos.size > 1
    chamada_da_capa(topo + 18)
  end

  def caixa_da_faixa
    [RECUO, RECUO, FOLHA[:largura] - (2 * RECUO), ALTURA_DA_FAIXA - RECUO]
  end

  def faixa_da_capa
    x, topo, largura, altura = caixa_da_faixa
    @doc.save_graphics_state do
      @doc.rounded_rectangle [x, y_de(topo)], largura, altura, RAIO_DA_FAIXA
      @doc.add_content('W n')
      @doc.fill_gradient from: [x, y_de(topo)], to: [x + largura, y_de(topo + altura)], stops: [cor(:marinho), cor(:azul_marca)]
      @doc.fill_rectangle [x, y_de(topo)], largura, altura
      @doc.stroke_color cor(:ciano)
      @doc.transparent(0.12) { arcos_da_faixa }
    end
  end

  # Dois aros concêntricos recortados pela faixa, eco da curva do "ua" do logo.
  def arcos_da_faixa
    @doc.line_width 34
    @doc.stroke_circle [FOLHA[:largura] - 60, y_de(64)], 150
    @doc.line_width 14
    @doc.stroke_circle [FOLHA[:largura] - 60, y_de(64)], 82
  end

  def textos_da_capa
    @doc.image LOGO.to_s, at: [MARGEM, y_de(42)], width: 136
    corretora_na_capa unless preparada_por.nil?
    escrever('Seguro Viagem', at: [MARGEM, 102], largura: 360, size: 34, style: :bold, cor: :branco)
    escrever('Separamos os planos da Universal Assistance para esta viagem. Compare o preço e a proteção e escolha com calma.',
             at: [MARGEM, 148], largura: 330, size: 11, leading: 3, cor: :heroi_texto)
    selo_da_viagem
  end

  def corretora_na_capa
    direita = FOLHA[:largura] - MARGEM - 240
    rotulo('Cotação preparada por', at: [direita, 42], largura: 240, cor: :ciano, align: :right)
    escrever(@nome_corretora, at: [direita, 55], largura: 240, size: 11.5, style: :semibold, cor: :branco, align: :right,
                              height: 30, overflow: :shrink_to_fit)
  end

  def selo_da_viagem
    texto = "#{destinos_texto} · #{viajantes_texto}"
    largura = [@doc.width_of(texto, size: 10, style: :semibold) + 30, largura_util].min
    @doc.fill_color cor(:branco)
    @doc.transparent(0.14) { @doc.fill_rounded_rectangle [MARGEM, y_de(196)], largura, 24, 12 }
    escrever(texto, at: [MARGEM + 15, 203], largura: largura - 30, size: 10, style: :semibold, cor: :branco,
                    height: 12, overflow: :shrink_to_fit)
  end

  # O cartão do plano em destaque, sobre a borda da faixa: à esquerda o rótulo, o nome e o valor para médico e
  # hospital; à direita o preço; embaixo, na largura toda, o porquê. Devolve o topo logo abaixo dele.
  def destaque(topo)
    plano = planos[indice_do_destaque]
    return topo if plano.nil?

    rotulo_do_plano = rotulos[indice_do_destaque] || :disponivel
    caixa = [MARGEM, topo, largura_util, altura_do_destaque(plano)]
    cartao(caixa)
    faixa_do_cartao(caixa, TONS.dig(rotulo_do_plano, :faixa))
    fim_da_esquerda = lado_esquerdo_do_destaque(plano, topo, rotulo_do_plano)
    lado_direito_do_destaque(plano, topo)
    escrever(porque, at: [MARGEM + RESPIRO, [fim_da_esquerda, topo + 84].max + 12], largura: largura_do_porque,
                     cor: :suave, **PORQUE)
    topo + caixa[3]
  end

  def porque
    @porque ||= Rotulos.porque(planos, rotulos)
  end

  def largura_do_porque
    largura_util - (2 * RESPIRO)
  end

  def largura_da_esquerda
    largura_util - (2 * RESPIRO) - LARGURA_DO_PRECO - 16
  end

  def dmh_do_destaque(plano)
    para_medico_e_hospital(plano, largura_da_esquerda, **DMH_DO_DESTAQUE)
  end

  def altura_da_esquerda(plano)
    38 + altura_de(plano['nome'], largura: largura_da_esquerda, size: 18, style: :bold) + 6 +
      altura_de(dmh_do_destaque(plano), largura: largura_da_esquerda, **DMH_DO_DESTAQUE)
  end

  def altura_do_destaque(plano)
    [altura_da_esquerda(plano), 84].max + 12 + altura_de(porque, largura: largura_do_porque, **PORQUE) + RESPIRO
  end

  # Devolve a distância do alto do cartão até o fim do lado esquerdo (somada ao `topo`).
  def lado_esquerdo_do_destaque(plano, topo, rotulo_do_plano)
    x = MARGEM + RESPIRO
    chamada = rotulo_do_plano == :recomendada ? 'Opção mais recomendada para esta viagem' : 'Opção disponível para esta viagem'
    rotulo(chamada, at: [x, topo + 22], largura: largura_da_esquerda, cor: :teal_texto)
    escrever(plano['nome'], at: [x, topo + 38], largura: largura_da_esquerda, size: 18, style: :bold, cor: :marinho)
    altura_do_nome = altura_de(plano['nome'], largura: largura_da_esquerda, size: 18, style: :bold)
    escrever(dmh_do_destaque(plano), at: [x, topo + 44 + altura_do_nome], largura: largura_da_esquerda, cor: :teal_texto,
                                     **DMH_DO_DESTAQUE)
    topo + altura_da_esquerda(plano)
  end

  def lado_direito_do_destaque(plano, topo)
    x = FOLHA[:largura] - MARGEM - RESPIRO - LARGURA_DO_PRECO
    a_direita = { largura: LARGURA_DO_PRECO, align: :right }
    rotulo("Total para #{viajantes_texto}", at: [x, topo + 22], **a_direita)
    escrever(preco(plano), at: [x, topo + 36], size: 26, style: :bold, cor: :marinho, **a_direita)
    parcelas = plano['max_parcelas'].to_i
    escrever("em até #{parcelas}x", at: [x, topo + 70], size: 9.5, cor: :suave, **a_direita) if parcelas.positive?
  end
end
