# O QUE SAI DO DADO DA BIGDATACORP PARA O AGENTE (#2858, F7). Cada card escolhe os campos pelo nome (lista fechada): o
# que não está na lista não sai, e por isso nunca saem nome de parente, sócio pessoa física, nome do dono do carro,
# doação eleitoral, pessoa exposta politicamente, link de arquivo nem o PDF da certidão. Os textos ganham teto na
# `Resposta`.
module Autonomia::FerramentasProntas::Premium::Extrair
  MAX_ITENS = 5

  module_function

  # `mapa`: nosso nome -> o campo da BigDataCorp. Vazio e "0001-01-01" (data vazia dela) ficam de fora.
  def campos(dado, mapa)
    return {} unless dado.is_a?(Hash)

    mapa.to_h { |nosso, deles| [nosso.to_s, valor(dado[deles])] }.compact
  end

  def valor(bruto)
    case bruto
    when String
      texto = bruto.strip
      texto.empty? || texto.start_with?('0001-01-01') ? nil : texto
    when Integer, Float, TrueClass, FalseClass then bruto
    end
  end

  # Até `maximo` itens da lista, cada um com os campos do mapa (em hash ou como palavras-chave); os vazios saem.
  def itens(lista, mapa = {}, maximo: MAX_ITENS, **campos_do_mapa)
    mapa = mapa.merge(campos_do_mapa)
    Array(lista).select { |item| item.is_a?(Hash) }.map { |item| campos(item, mapa) }.reject(&:empty?).first(maximo)
  end

  # A certidão sob demanda (`OnlineCertificates`): a situação que a fonte oficial deu e as datas que vierem.
  CERTIDAO = { emitida_em: 'EmissionDate', emitida: 'CertificateIssueDate', validade: 'ValidityDate', periodo: 'Validity',
               vence_em: 'Expiration', situacao_do_fgts: 'Status', em_debito: 'IsInDebt' }.freeze

  def certidao(lista)
    certidao = Array(lista).find { |item| item.is_a?(Hash) }
    return nil if certidao.nil?

    situacao = valor(certidao['BaseStatus'])
    return nil if situacao.nil?

    { 'situacao' => situacao }.merge(campos(certidao['AdditionalOutputData'], CERTIDAO))
  end

  def sem_vazio(hash)
    hash.reject { |_chave, item| item.nil? || (item.respond_to?(:empty?) && item.empty?) }.presence
  end
end
