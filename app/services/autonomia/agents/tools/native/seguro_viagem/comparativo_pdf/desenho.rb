# O DESENHO do comparativo de Seguro Viagem (#3211): a paleta da Universal Assistance, a letra Inter dos outros PDFs do
# produto e os blocos que as pÃ¡ginas repetem (texto, cartÃ£o com sombra, selo e rÃ³tulo em caixa alta).
#
# COORDENADAS: a folha nÃ£o tem margem do Prawn; todo bloco recebe o `topo` como distÃ¢ncia do alto da folha (o jeito de
# ler uma pÃ¡gina), e `y_de` converte para o Prawn, que mede de baixo para cima.
#
# DE ONDE VÃM AS CORES (site e logo oficiais, 25/11/2026):
# - marinho `002E6D`: a cor mais usada no CSS do tema do site (universal-assistance.com/br, theme.min.css);
# - azul_marca `005191`: o segundo azul do mesmo CSS, fim do degradÃª da capa;
# - teal `008998`: o "ua" do logo colorido (logo-color-1.webp) e o mesmo hex no CSS;
# - ciano `40D3E7` e ciano_fundo `E6FAFF`: o destaque claro do CSS;
# - teal_texto `00707D`: o teal do logo escurecido, sÃ³ para texto pequeno sobre teal passar o contraste de 4,5:1.
# Os neutros sÃ£o os dos relatÃ³rios em PDF (`Relatorios::Pdf::COR`).
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho
  FOLHA = { largura: 595.28, altura: 841.89 }.freeze
  MARGEM = 40
  RAIO = 10
  ESPACO_DAS_LETRAS = 0.8
  SEM_VALOR = '—'.freeze
  MARCA = {
    marinho: '002E6D', azul_marca: '005191', teal: '008998', teal_texto: '00707D', ciano: '40D3E7', ciano_fundo: 'E6FAFF'
  }.freeze
  # A cor da faixa do cartÃ£o e do selo de cada rÃ³tulo (`Rotulos::NOMES`); selo = [fundo, texto].
  TONS = {
    economica: { faixa: :ciano, selo: %i[ciano_fundo marinho] }, recomendada: { faixa: :teal, selo: %i[teal_texto branco] },
    maior_cobertura: { faixa: :marinho, selo: %i[marinho branco] }, disponivel: { faixa: :fraca, selo: %i[fundo suave] }
  }.freeze
  COR = Relatorios::Pdf::COR.slice(:tinta, :suave, :fraca, :linha, :fundo, :branco, :heroi_texto).merge(MARCA).freeze
  FONTES = Relatorios::Pdf::FONTES

  private

  def cor(nome)
    COR.fetch(nome)
  end

  def y_de(topo)
    FOLHA[:altura] - topo
  end

  def largura_util
    FOLHA[:largura] - (2 * MARGEM)
  end

  def registrar_fontes
    @doc.font_families.update(
      'Inter' => { normal: FONTES.join('Inter-Regular.ttf').to_s, medium: FONTES.join('Inter-Medium.ttf').to_s,
                   semibold: FONTES.join('Inter-SemiBold.ttf').to_s, bold: FONTES.join('Inter-Bold.ttf').to_s }
    )
    @doc.font 'Inter'
  end

  # `estilo`: as opÃ§Ãµes do `text_box` do Prawn (size, style, align, leading, height, overflow...) e `cor`.
  def escrever(conteudo, at:, largura:, **estilo)
    @doc.fill_color cor(estilo.fetch(:cor, :tinta))
    opcoes = { size: 10, style: :normal }.merge(estilo.except(:cor))
    @doc.text_box(conteudo.to_s, at: [at[0], y_de(at[1])], width: largura, **opcoes)
  end

  def altura_de(conteudo, largura:, **estilo)
    @doc.height_of(conteudo.to_s, width: largura, size: estilo.fetch(:size, 10), style: estilo.fetch(:style, :normal),
                                  leading: estilo.fetch(:leading, 0))
  end

  # O rÃ³tulo pequeno em caixa alta, com as letras espaÃ§adas.
  def rotulo(conteudo, at:, largura:, **estilo)
    opcoes = { size: 7, style: :semibold, cor: :suave }.merge(estilo)
    @doc.character_spacing(ESPACO_DAS_LETRAS) do
      escrever(conteudo.to_s.upcase, at: at, largura: largura, **opcoes)
    end
  end

  # CartÃ£o de canto arredondado, com uma sombra suave em trÃªs camadas. `caixa` = [x, topo, largura, altura].
  def cartao(caixa, fundo: :branco, borda: :linha)
    x, topo, largura, altura = caixa
    sombra(caixa)
    @doc.fill_color cor(fundo)
    @doc.fill_rounded_rectangle [x, y_de(topo)], largura, altura, RAIO
    return if borda.nil?

    @doc.stroke_color cor(borda)
    @doc.line_width 0.7
    @doc.stroke_rounded_rectangle [x, y_de(topo)], largura, altura, RAIO
  end

  def sombra(caixa)
    x, topo, largura, altura = caixa
    @doc.fill_color cor(:marinho)
    [[4, 2.5], [2.5, 1.5], [1.2, 0.6]].each do |deslocamento, folga|
      @doc.transparent(0.035) do
        @doc.fill_rounded_rectangle [x - folga, y_de(topo + deslocamento) + folga], largura + (2 * folga), altura + folga,
                                    RAIO + folga
      end
    end
  end

  # Uma faixa de cor no alto do cartÃ£o, recortada pelo canto arredondado dele.
  def faixa_do_cartao(caixa, cor_da_faixa, altura: 4)
    x, topo, largura, altura_do_cartao = caixa
    @doc.save_graphics_state do
      @doc.rounded_rectangle [x, y_de(topo)], largura, altura_do_cartao, RAIO
      @doc.add_content('W n')
      @doc.fill_color cor(cor_da_faixa)
      @doc.fill_rectangle [x, y_de(topo)], largura, altura
    end
  end

  # Selo em pÃ­lula; devolve a largura dele. `tons` = [fundo, texto].
  def selo(conteudo, at:, tons:, size: 7)
    texto = conteudo.to_s.upcase
    largura = @doc.width_of(texto, size: size, style: :bold) + (ESPACO_DAS_LETRAS * texto.length) + 16
    @doc.fill_color cor(tons[0])
    @doc.fill_rounded_rectangle [at[0], y_de(at[1])], largura, size + 9, (size + 9) / 2.0
    @doc.character_spacing(ESPACO_DAS_LETRAS) do
      escrever(texto, at: [at[0], at[1] + 4.6], largura: largura, size: size, style: :bold, cor: tons[1], align: :center)
    end
    largura
  end

  # BotÃ£o em pÃ­lula que abre `url` no leitor de PDF (anotaÃ§Ã£o de link sobre a pÃ­lula inteira).
  def botao(conteudo, caixa, url)
    x, topo, largura, altura = caixa
    @doc.fill_color cor(:marinho)
    @doc.fill_rounded_rectangle [x, y_de(topo)], largura, altura, altura / 2.0
    escrever(conteudo, at: [x, topo + ((altura - 8.5) / 2.0)], largura: largura, size: 8.5, style: :semibold, cor: :branco,
                       align: :center)
    @doc.link_annotation([x, y_de(topo + altura), x + largura, y_de(topo)],
                         Border: [0, 0, 0], A: { Type: :Action, S: :URI, URI: PDF::Core::LiteralString.new(url) })
  end
end
