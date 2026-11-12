# O QUE SAI DO DADO DA BIGDATACORP PARA O AGENTE (#2858, F7). Cada card escolhe os campos pelo nome (lista fechada): o
# que não está na lista não sai, e por isso nunca saem nome de parente, sócio pessoa física, nome do dono do carro,
# doação eleitoral, pessoa exposta politicamente, link de arquivo nem o PDF da certidão. Os textos ganham teto na
# `Resposta`.
module Autonomia::FerramentasProntas::Premium::Extrair
  MAX_ITENS = 5
  TAMANHO_DA_DATA = 10
  # A BigDataCorp marca "sem data de fim" com o ano 9999.
  SEM_FIM = '9999'.freeze
  FORMATO_AMERICANO = '%m/%d/%Y'.freeze
  SIM = 'true'.freeze
  NAO = 'false'.freeze

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

    extra = ajustar(campos(certidao['AdditionalOutputData'], CERTIDAO), datas: %w[emitida_em validade], sim_ou_nao: %w[em_debito])
    { 'situacao' => situacao }.merge(extra)
  end

  # Os campos de um hash já extraído, no formato que não leva a leitura errada (as fixtures da vitrine, 11/11):
  #   - `datas`: "2026-10-01T09:00:00" -> "2026-10-01"; o fim 9999 (sem fim) sai; outro formato fica como veio;
  #   - `datas_americanas`: "02/20/2025 00:00:00" (mês/dia, as obras) -> "2025-02-20";
  #   - `positivos`: número negativo (o -1 de "desconhecido") sai;
  #   - `sim_ou_nao`: o "True" e o "False" em texto viram verdadeiro e falso.
  def ajustar(hash, datas: [], datas_americanas: [], positivos: [], sim_ou_nao: [])
    ajustes = { method(:data) => datas, method(:data_americana) => datas_americanas, method(:positivo) => positivos,
                method(:sim_ou_nao) => sim_ou_nao }
    hash.to_h do |chave, item|
      ajuste = ajustes.find { |_metodo, chaves| chaves.include?(chave) }&.first
      [chave, ajuste ? ajuste.call(item) : item]
    end.compact
  end

  def data(texto)
    return nil if texto.nil? || texto.start_with?(SEM_FIM)

    Date.iso8601(texto.first(TAMANHO_DA_DATA)).iso8601
  rescue Date::Error
    texto
  end

  def data_americana(texto)
    return nil if texto.nil?

    Date.strptime(texto.first(TAMANHO_DA_DATA), FORMATO_AMERICANO).iso8601
  rescue Date::Error
    texto
  end

  def positivo(numero)
    numero.is_a?(Numeric) && numero.negative? ? nil : numero
  end

  def sim_ou_nao(item)
    return item if [true, false].include?(item)

    { SIM => true, NAO => false }[item.to_s.strip.downcase]
  end

  def sem_vazio(hash)
    hash.reject { |_chave, item| item.nil? || (item.respond_to?(:empty?) && item.empty?) }.presence
  end
end
