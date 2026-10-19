# #1426 — largura e altura de uma imagem lidas só do CABEÇALHO (PNG, JPEG, GIF e WebP), sem decodificar os pixels e sem
# chamar programa externo: é o que deixa recusar a bomba de pixels antes do OCR. Formato que não dá para ler devolve
# [nil, nil], e quem chama recusa.
#
# Animação (GIF com mais de um quadro, WebP com ANIM/ANMF) é recusada à parte (`animada?`): foto de material é uma
# imagem parada, e cada quadro de uma animação pediria memória ao decodificar. No GIF de um quadro só, vale o maior
# entre a tela declarada e o quadro (posição + tamanho), porque o decodificador aloca os dois.
module Autonomia::Agents::Knowledge::DimensoesDaImagem
  # Marcadores JPEG de início de quadro (SOF0..SOF15, menos DHT, JPG e DAC), onde moram altura e largura.
  JPEG_SOF = ([0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]).freeze
  GIF_FIM = 0x3B
  GIF_EXTENSAO = 0x21
  GIF_QUADRO = 0x2C
  WEBP_ANIMACAO = %w[ANIM ANMF].freeze
  WEBP_FLAG_ANIMACAO = 0x02

  module_function

  def ler(bytes, tipo)
    case tipo
    when 'image/png' then png(bytes)
    when 'image/gif' then gif(bytes)
    when 'image/webp' then webp(bytes)
    when 'image/jpeg' then jpeg(bytes)
    else [nil, nil]
    end
  end

  def animada?(bytes, tipo)
    case tipo
    when 'image/gif' then gif_quadros(bytes).to_a.size > 1
    when 'image/webp' then webp_animada?(bytes)
    else false
    end
  end

  # Assinatura (8) + tamanho e tipo do IHDR (8) + largura e altura (4 + 4, big-endian).
  def png(bytes)
    return [nil, nil] unless bytes.bytesize >= 24 && bytes.byteslice(12, 4) == 'IHDR'

    bytes.byteslice(16, 8).unpack('NN')
  end

  def gif(bytes)
    quadros = gif_quadros(bytes)
    return [nil, nil] if quadros.blank?

    largura, altura = bytes.byteslice(6, 4).unpack('vv')
    esquerda, topo, largura_do_quadro, altura_do_quadro = quadros.first
    [[largura, esquerda + largura_do_quadro].max, [altura, topo + altura_do_quadro].max]
  end

  # Os quadros do GIF ([esquerda, topo, largura, altura]), percorrendo os blocos até o fim (0x3B). nil quando o arquivo
  # não segue o formato (bloco desconhecido, cortado no meio): quem chama recusa.
  def gif_quadros(bytes)
    return if bytes.bytesize < 13

    posicao = 13 + tabela_de_cores(bytes.getbyte(10))
    quadros = []
    loop do
      case bytes.getbyte(posicao)
      when GIF_FIM then return quadros
      when GIF_EXTENSAO then posicao = pular_sub_blocos(bytes, posicao + 2)
      when GIF_QUADRO
        return if posicao + 10 > bytes.bytesize

        quadros << bytes.byteslice(posicao + 1, 8).unpack('vvvv')
        posicao = pular_sub_blocos(bytes, posicao + 11 + tabela_de_cores(bytes.getbyte(posicao + 9)))
      else return
      end
      return if posicao.nil?
    end
  end

  # Tamanho da tabela de cores que segue um cabeçalho do GIF (bit 7 = existe; bits 0-2 = 2^(n+1) cores de 3 bytes).
  def tabela_de_cores(campo)
    return 0 if campo.nil? || campo.nobits?(0x80)

    3 * (2 << (campo & 0x07))
  end

  # Sub-blocos do GIF: um byte de tamanho e os dados, até o de tamanho zero. Devolve a posição depois deles, ou nil.
  def pular_sub_blocos(bytes, posicao)
    loop do
      tamanho = bytes.getbyte(posicao)
      return if tamanho.nil?

      posicao += 1 + tamanho
      return posicao if tamanho.zero?
    end
  end

  def webp(bytes)
    return [nil, nil] unless bytes.bytesize >= 30

    case bytes.byteslice(12, 4)
    when 'VP8 ' then bytes.byteslice(26, 4).unpack('vv').map { |valor| valor & 0x3FFF }
    when 'VP8L' then webp_sem_perda(bytes.byteslice(21, 4).unpack('C4'))
    when 'VP8X' then [vinte_e_quatro_bits(bytes, 24) + 1, vinte_e_quatro_bits(bytes, 27) + 1]
    else [nil, nil]
    end
  end

  # A marca de animação do VP8X, ou qualquer pedaço ANIM/ANMF no arquivo (percorre os pedaços RIFF pelo tamanho).
  def webp_animada?(bytes)
    return true if bytes.byteslice(12, 4) == 'VP8X' && bytes.getbyte(20).to_i.anybits?(WEBP_FLAG_ANIMACAO)

    posicao = 12
    while posicao + 8 <= bytes.bytesize
      return true if WEBP_ANIMACAO.include?(bytes.byteslice(posicao, 4))

      tamanho = bytes.byteslice(posicao + 4, 4).unpack1('V')
      posicao += 8 + tamanho + (tamanho % 2)
    end
    false
  end

  def webp_sem_perda((b0, b1, b2, b3))
    [1 + (((b1 & 0x3F) << 8) | b0), 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6))]
  end

  def vinte_e_quatro_bits(bytes, posicao)
    a, b, c = bytes.byteslice(posicao, 3).unpack('C3')
    a | (b << 8) | (c << 16)
  end

  # Percorre os segmentos (FF xx + tamanho big-endian) até o início de quadro: precisão (1), altura (2), largura (2).
  def jpeg(bytes)
    posicao = 2
    while posicao + 9 <= bytes.bytesize
      return [nil, nil] unless bytes.getbyte(posicao) == 0xFF

      marcador = bytes.getbyte(posicao + 1)
      tamanho = bytes.byteslice(posicao + 2, 2).unpack1('n')
      return bytes.byteslice(posicao + 5, 4).unpack('nn').reverse if JPEG_SOF.include?(marcador)

      posicao += 2 + tamanho
    end
    [nil, nil]
  end
end
