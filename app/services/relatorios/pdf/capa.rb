# Capa dos relatórios em PDF (#1960): faixa azul-escura de ponta a ponta no alto da primeira página, com a conta e o
# período em cima, o rótulo e a frase do relatório em letra grande, e dois círculos recortados pela faixa.
module Relatorios::Pdf::Capa
  ALTURA_DA_FAIXA = 206

  # Devolve o `topo` (na área útil) logo abaixo da faixa.
  def capa(conta:, titulo:, periodo:, rotulo:, frase:)
    pagina = { alto: @doc.bounds.absolute_top + Relatorios::Pdf::MARGEM[0],
               largura: @doc.bounds.absolute_left + largura + Relatorios::Pdf::MARGEM[1] }
    @doc.canvas do
      faixa_da_capa(pagina)
      textos_da_capa(pagina, conta: conta, direita: "#{titulo} · #{periodo}", rotulo: rotulo, frase: frase)
    end
    altura - (ALTURA_DA_FAIXA - Relatorios::Pdf::MARGEM[0])
  end

  private

  # A faixa e os dois círculos decorativos, recortados por ela (o retângulo vira a área de recorte, "W n").
  def faixa_da_capa(pagina)
    @doc.fill_color cor(:heroi)
    @doc.fill_rectangle [0, pagina[:alto]], pagina[:largura], ALTURA_DA_FAIXA
    @doc.save_graphics_state do
      @doc.rectangle [0, pagina[:alto]], pagina[:largura], ALTURA_DA_FAIXA
      @doc.add_content('W n')
      @doc.stroke_color cor(:heroi_linha)
      @doc.line_width 34
      @doc.stroke_circle [pagina[:largura] - 110, pagina[:alto] - 40], 96
      @doc.stroke_circle [pagina[:largura] - 290, pagina[:alto] - ALTURA_DA_FAIXA - 10], 62
    end
  end

  def textos_da_capa(pagina, textos)
    esquerda = Relatorios::Pdf::MARGEM[3]
    @doc.fill_color cor(:heroi_texto)
    @doc.text_box textos[:conta], at: [esquerda, pagina[:alto] - 30], width: 380, size: 10, style: :semibold
    @doc.text_box textos[:direita], at: [pagina[:largura] - Relatorios::Pdf::MARGEM[1] - 420, pagina[:alto] - 30], width: 420,
                                    size: 10, align: :right
    @doc.text_box textos[:rotulo], at: [esquerda, pagina[:alto] - 70], width: 600, size: 11, style: :medium
    @doc.fill_color cor(:branco)
    @doc.text_box textos[:frase], at: [esquerda, pagina[:alto] - 90], width: 600, height: 70, size: 25, style: :bold, leading: 3,
                                  overflow: :shrink_to_fit
  end
end
