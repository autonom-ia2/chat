# #1426 — largura e altura de uma imagem lidas só do CABEÇALHO (PNG, JPEG, GIF e WebP), sem decodificar os pixels e sem
# chamar programa externo: é o que deixa recusar a bomba de pixels antes do OCR. Formato que não dá para ler devolve
# [nil, nil], e quem chama recusa.
module Autonomia::Agents::Knowledge::DimensoesDaImagem
  # Marcadores JPEG de início de quadro (SOF0..SOF15, menos DHT, JPG e DAC), onde moram altura e largura.
  JPEG_SOF = ([0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]).freeze

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

  # Assinatura (8) + tamanho e tipo do IHDR (8) + largura e altura (4 + 4, big-endian).
  def png(bytes)
    return [nil, nil] unless bytes.bytesize >= 24 && bytes.byteslice(12, 4) == 'IHDR'

    bytes.byteslice(16, 8).unpack('NN')
  end

  def gif(bytes)
    return [nil, nil] unless bytes.bytesize >= 10

    bytes.byteslice(6, 4).unpack('vv')
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
