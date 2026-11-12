require 'digest'

# As linhas da planilha que precisam da pessoa (#2896), uma página por vez, no formato da tela: a linha, o tipo do
# problema em palavras da tela, o nome e o valor que está errado.
#
# O tipo sai dos motivos que a leitura gravou na linha. O valor inteiro sai da planilha original, na hora, e só as
# linhas desta página (e a outra linha de cada repetida) são lidas dela; depois que ela é apagada vai a máscara que a
# linha guarda. O nome é a exceção: a leitura já o guarda inteiro na linha, e ele sai inteiro com ou sem a planilha.
# Nesta fatia a linha repetida é a que a leitura de hoje recusa (o segundo telefone ou e-mail igual): a outra linha é
# achada pelo mesmo hash que a leitura gravou na linha que ficou.
class Relacionamentos::Trazer::Problemas
  REPETIDA = { 'duplicate_phone_in_file' => 'phone', 'duplicate_email_in_file' => 'email' }.freeze
  # O tipo de cada motivo, na ordem em que valem: o primeiro que a linha tiver decide.
  TIPO_DOS_MOTIVOS = {
    'duplicada' => REPETIDA.keys, 'sem_contato' => %w[missing_contact],
    'telefone' => %w[blank_phone_number formula_phone_number invalid_brazilian_mobile_number], 'email' => %w[blank_email invalid_email]
  }.freeze
  ALVO_DO_TIPO = { 'telefone' => 'phone', 'email' => 'email', 'nome' => 'name' }.freeze
  # A linha tem contato que vale e ficou de fora por uma célula que parece fórmula: o tipo é o da célula.
  TIPO_DA_FORMULA = { 'phone' => 'telefone', 'email' => 'email' }.freeze
  NOME = 'nome'.freeze
  MASCARAS = { 'phone' => :raw_phone_masked, 'email' => :email_masked, 'name' => :raw_name }.freeze

  def initialize(importacao, planilha, pagina:, por_pagina:)
    @importacao = importacao
    @planilha = planilha
    @pagina = pagina
    @por_pagina = por_pagina
  end

  def call
    abrir_planilha
    linhas.map { |linha| problema(linha) }
  end

  private

  def linhas
    @linhas ||= @importacao.campaign_import_rows.status_invalid.order(:row_number)
                           .offset((@pagina - 1) * @por_pagina).limit(@por_pagina).to_a
  end

  # As células das linhas da página e, numa leitura só da planilha, as da outra linha de cada repetida.
  def abrir_planilha
    @celulas = {}
    @celulas = @planilha.ler(linhas.map(&:row_number)) do |da_pagina|
      @celulas = da_pagina
      primeiras.values
    end
  end

  def problema(linha)
    tipo = tipo_de(linha)
    item = { linha: linha.row_number, tipo: tipo, nome: linha.raw_name.to_s, valor: valor(linha, alvo_do_valor(linha, tipo)), estado: 'aberto' }
    tipo == 'duplicada' ? item.merge(repetida(linha)) : item
  end

  def tipo_de(linha)
    motivos = Array(linha.error_messages)
    tipo, = TIPO_DOS_MOTIVOS.find { |_tipo, codigos| motivos.intersect?(codigos) }
    tipo || TIPO_DA_FORMULA.find { |alvo, _tipo| formula?(linha, alvo) }&.last || NOME
  end

  def formula?(linha, alvo)
    CampaignImports::CsvSanitizer.formula_like?(celula(linha.row_number, alvo), allow_phone_plus: alvo == 'phone')
  end

  def alvo_do_valor(linha, tipo)
    tipo == 'duplicada' ? alvo_repetido(linha) : ALVO_DO_TIPO[tipo]
  end

  def alvo_repetido(linha)
    REPETIDA.values_at(*linha.error_messages).compact.first
  end

  def valor(linha, alvo)
    return '' unless alvo
    return celula(linha.row_number, alvo) if @planilha.inteira?

    linha.public_send(MASCARAS.fetch(alvo)).to_s
  end

  def celula(numero_da_linha, alvo)
    indice = colunas.alvos[alvo]
    indice ? @celulas[numero_da_linha]&.at(indice).to_s.strip : ''
  end

  def repetida(linha)
    outra = primeiras[hash_repetido(linha)]
    { outraLinha: outra, duplicadas: outra ? [outra, linha.row_number].map { |numero| contatos_da_linha(numero) } : [] }
  end

  def contatos_da_linha(numero)
    { linha: numero, telefone: celula(numero, 'phone'), email: celula(numero, 'email') }
  end

  # { hash do telefone ou do e-mail => a linha aprovada que o tem }, das repetidas desta página, numa consulta só.
  def primeiras
    @primeiras ||= begin
      hashes = linhas.filter_map { |linha| hash_repetido(linha) }
      hashes.empty? ? {} : linhas_aprovadas_com(hashes)
    end
  end

  def linhas_aprovadas_com(hashes)
    aprovadas = @importacao.campaign_import_rows.status_valid
    achadas = aprovadas.where(normalized_phone_hash: hashes).or(aprovadas.where(normalized_email_hash: hashes))
                       .order(:row_number).pluck(:normalized_phone_hash, :normalized_email_hash, :row_number)
    achadas.each_with_object({}) do |(telefone, email, numero), por_hash|
      [telefone, email].compact.each { |hash| por_hash[hash] ||= numero }
    end
  end

  # O hash que a leitura gravou na linha que ficou, refeito do valor da planilha. Sem a planilha não há como refazer.
  def hash_repetido(linha)
    alvo = alvo_repetido(linha)
    texto = alvo && celula(linha.row_number, alvo)
    return if texto.blank?

    alvo == 'phone' ? leitura_de_contato.phone(texto).hash : Digest::SHA256.hexdigest(leitura_de_contato.email(texto).email)
  rescue CampaignImports::PhoneNormalizer::Error, EmailCampaigns::EmailNormalizer::Error
    nil
  end

  def leitura_de_contato
    @leitura_de_contato ||= CampaignImports::ContactReading.for(@importacao.account).with_legacy_mobiles(true)
  end

  def colunas
    @colunas ||= Relacionamentos::Trazer::Colunas.new(@importacao)
  end
end
