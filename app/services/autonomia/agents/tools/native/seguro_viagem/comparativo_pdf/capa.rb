# A CAPA do comparativo de Seguro Viagem (#3211): a faixa em degradê com o logo da Universal Assistance, a corretora
# que envia, o título e o selo da viagem; e o cartão do plano em destaque sobre a borda da faixa. Os dados da viagem e o
# resumo com os rótulos, logo abaixo, são do `Resumo`.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Capa
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  Rotulos = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  LOGO = Rails.root.join('lib/assets/images/seguro_viagem/universal-assistance.png').freeze
  ALTURA_DA_FAIXA = 300
  TOPO_DO_DESTAQUE = 236
  LARGURA_DO_TEXTO = 300
  LARGURA_DO_PRECO = 170

  private

  def capa
    faixa_da_capa
    textos_da_capa
    topo = destaque(TOPO_DO_DESTAQUE)
    topo = dados_da_viagem(topo + 22)
    resumo(topo + 28) if planos.size > 1
  end

  def faixa_da_capa
    @doc.fill_gradient from: [0, FOLHA[:altura]], to: [FOLHA[:largura], y_de(ALTURA_DA_FAIXA)],
                       stops: [cor(:marinho), cor(:azul_marca)]
    @doc.fill_rectangle [0, FOLHA[:altura]], FOLHA[:largura], ALTURA_DA_FAIXA
    @doc.save_graphics_state do
      @doc.rectangle [0, FOLHA[:altura]], FOLHA[:largura], ALTURA_DA_FAIXA
      @doc.add_content('W n')
      @doc.stroke_color cor(:ciano)
      @doc.transparent(0.12) { arcos_da_faixa }
    end
  end

  # Dois aros concÃªntricos recortados pela faixa, eco da curva do "ua" do logo.
  def arcos_da_faixa
    @doc.line_width 34
    @doc.stroke_circle [FOLHA[:largura] - 60, y_de(64)], 150
    @doc.line_width 14
    @doc.stroke_circle [FOLHA[:largura] - 60, y_de(64)], 82
  end

  def textos_da_capa
    @doc.image LOGO.to_s, at: [MARGEM, y_de(38)], width: 136
    corretora_na_capa unless preparada_por.nil?
    escrever('Seguro Viagem', at: [MARGEM, 100], largura: 360, size: 34, style: :bold, cor: :branco)
    escrever('Separamos os planos da Universal Assistance para esta viagem. Compare o preço e a proteção e escolha com calma.',
             at: [MARGEM, 146], largura: 330, size: 11, leading: 3, cor: :heroi_texto)
    selo_da_viagem
  end

  def corretora_na_capa
    direita = FOLHA[:largura] - MARGEM - 240
    rotulo('Cotação preparada por', at: [direita, 40], largura: 240, cor: :ciano, size: 6.5, align: :right)
    escrever(@nome_corretora, at: [direita, 52], largura: 240, size: 11.5, style: :semibold, cor: :branco, align: :right,
                              height: 30, overflow: :shrink_to_fit)
  end

  def selo_da_viagem
    texto = "#{destinos_texto} · #{viajantes_texto}"
    largura = [@doc.width_of(texto, size: 9.5, style: :semibold) + 30, largura_util].min
    @doc.fill_color cor(:branco)
    @doc.transparent(0.14) { @doc.fill_rounded_rectangle [MARGEM, y_de(196)], largura, 24, 12 }
    escrever(texto, at: [MARGEM + 15, 203], largura: largura - 30, size: 9.5, style: :semibold, cor: :branco,
                    height: 12, overflow: :shrink_to_fit)
  end

  def indice_do_destaque
    rotulos.index(:recomendada) || rotulos.index(:disponivel) || 0
  end

  # O cartão do plano em destaque, sobre a borda da faixa. Devolve o topo logo abaixo dele.
  def destaque(topo)
    plano = planos[indice_do_destaque]
    return topo if plano.nil?

    rotulo_do_plano = rotulos[indice_do_destaque] || :disponivel
    frase = Rotulos.frase(rotulo_do_plano, plano)
    altura = altura_do_destaque(plano, frase)
    caixa = [MARGEM, topo, largura_util, altura]
    cartao(caixa)
    faixa_do_cartao(caixa, TONS.dig(rotulo_do_plano, :faixa))
    lado_esquerdo_do_destaque(plano, frase, topo, rotulo_do_plano)
    lado_direito_do_destaque(plano, topo)
    topo + altura
  end

  def altura_do_destaque(plano, frase)
    esquerda = 50 + altura_de(plano['nome'], largura: LARGURA_DO_TEXTO, size: 18, style: :bold) +
               altura_de(frase, largura: LARGURA_DO_TEXTO, size: 9.5, leading: 2) + 24
    [esquerda, 124].max
  end

  def lado_esquerdo_do_destaque(plano, frase, topo, rotulo_do_plano)
    x = MARGEM + 22
    chamada = rotulo_do_plano == :recomendada ? 'Opção mais recomendada para esta viagem' : 'Opção disponível para esta viagem'
    rotulo(chamada, at: [x, topo + 22], largura: LARGURA_DO_TEXTO, cor: :teal_texto)
    escrever(plano['nome'], at: [x, topo + 38], largura: LARGURA_DO_TEXTO, size: 18, style: :bold, cor: :marinho)
    altura_do_nome = altura_de(plano['nome'], largura: LARGURA_DO_TEXTO, size: 18, style: :bold)
    escrever(frase, at: [x, topo + 46 + altura_do_nome], largura: LARGURA_DO_TEXTO, size: 9.5, leading: 2, cor: :suave)
  end

  def lado_direito_do_destaque(plano, topo)
    x = FOLHA[:largura] - MARGEM - 22 - LARGURA_DO_PRECO
    a_direita = { largura: LARGURA_DO_PRECO, align: :right }
    rotulo("Total para #{viajantes_texto}", at: [x, topo + 22], **a_direita)
    escrever(preco(plano), at: [x, topo + 36], size: 26, style: :bold, cor: :marinho, **a_direita)
    parcelas = plano['max_parcelas'].to_i
    escrever("em até #{parcelas}x", at: [x, topo + 70], size: 9, cor: :suave, **a_direita) if parcelas.positive?
    dmh = Rotulos.despesas_medicas_texto(plano) || SEM_VALOR
    escrever("#{dmh} em despesas médicas", at: [x, topo + 88], size: 9, style: :semibold, cor: :teal_texto, **a_direita)
  end
end
