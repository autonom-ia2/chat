# Foto dos relatórios em PDF (#1960): a imagem preenche o quadrado (como object-fit: cover) com cantos arredondados.
# Sem imagem (ou num formato que o Prawn não lê), um bloco de cor escolhido pelo nome, com o nome escrito; na
# miniatura, só a cor.
module Relatorios::Pdf::Foto
  # Sempre a mesma cor para o mesmo nome.
  BLOCOS = %w[0F766E 2563EB 4F46E5 0E7490 B45309 BE185D].freeze
  RAIO_DA_MINIATURA = 8

  # `item`: { foto: (PNG/JPEG em bytes ou nil), nome: }.
  def foto(item, esquerda:, topo:, lado:, miniatura: false)
    raio = miniatura ? RAIO_DA_MINIATURA : Relatorios::Pdf::RAIO
    return bloco_sem_foto(item[:nome], [esquerda, topo], lado, miniatura) if item[:foto].nil?

    @doc.save_graphics_state do
      @doc.fill_color cor(:fundo)
      @doc.fill_rounded_rectangle([esquerda, topo], lado, lado, raio)
      @doc.rounded_rectangle([esquerda, topo], lado, lado, raio)
      @doc.add_content('W n')
      cobrir(item[:foto], [esquerda, topo], lado)
    end
  rescue Prawn::Errors::UnsupportedImageType
    bloco_sem_foto(item[:nome], [esquerda, topo], lado, miniatura)
  end

  private

  # Escala pelo lado menor e centraliza; o recorte arredondado corta a sobra.
  def cobrir(imagem, ponto, lado)
    objeto, info = @doc.build_image_object(StringIO.new(imagem))
    escala = lado.to_f / [info.width, info.height].min
    largura_da_imagem = info.width * escala
    altura_da_imagem = info.height * escala
    @doc.embed_image(objeto, info, at: [ponto[0] - ((largura_da_imagem - lado) / 2), ponto[1] + ((altura_da_imagem - lado) / 2)],
                                   width: largura_da_imagem, height: altura_da_imagem)
  end

  def bloco_sem_foto(nome, ponto, lado, miniatura)
    esquerda, topo = ponto
    @doc.fill_color BLOCOS[nome.to_s.sum % BLOCOS.size]
    @doc.fill_rounded_rectangle(ponto, lado, lado, miniatura ? RAIO_DA_MINIATURA : Relatorios::Pdf::RAIO)
    return if miniatura

    @doc.fill_color cor(:branco)
    @doc.text_box nome.to_s, at: [esquerda + 14, topo - 14], width: lado - 28, height: lado - 28, size: 17, style: :bold,
                             align: :center, valign: :center, overflow: :shrink_to_fit
  end
end
