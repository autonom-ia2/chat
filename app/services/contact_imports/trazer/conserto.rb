# "Trazer minha lista" (#2896): confere o conserto que a pessoa fez numa linha com problema, com os MESMOS leitores de
# telefone e e-mail da leitura da planilha (CampaignImports::AudienceRowContacts). Não grava nada.
#
# Recebe as células da linha como vieram (por alvo), o que a pessoa já tinha consertado nela (`valores`, por alvo) e o
# conserto de agora:
# - `telefone`, `email` ou `nome`: o valor novo daquele campo;
# - `contato`: a linha não tinha telefone nem e-mail; o valor com "@" é e-mail, o resto é telefone, e ele toma o lugar
#   do contato que a pessoa tinha digitado antes;
# - `ficar_com`: a linha repetida que a pessoa escolheu manter, com os valores que ela já tinha.
#
# Devolve:
# - `motivo`, quando o valor digitado não vale, em código (os da leitura da planilha: invalid_brazilian_mobile_number,
#   blank_phone_number, formula_phone_number, invalid_email, blank_email, blank_name, missing_contact, formula_detected).
#   Nunca o valor. Nada é para guardar;
# - senão `valores` (o que guardar) e a linha `conferida`, pronta para o arquivo conferido, quando a linha inteira
#   ficou boa; ou `sobrou`, o motivo que ainda falta resolver nela (a linha sem nome que teve o telefone consertado).
#   Com a linha `conferida`, `sem_telefone` diz se ela entra sem o telefone que está escrito nela: o número não deu
#   para ler e a linha vale pelo e-mail (a linha sem nome que teve só o nome consertado, a repetida que a pessoa
#   escolheu manter). É só a marca, nunca o que estava escrito.
# A fórmula numa célula que a tela não conserta (a empresa) sobra antes de tudo (`formula_detected`): nenhum conserto
# resolve a linha, e ela só pode ficar de fora (Relacionamentos::Trazer::Pendencia diz isso à tela). Depois vem o que
# a tela conserta.
class ContactImports::Trazer::Conserto
  Resultado = Struct.new(:motivo, :valores, :conferida, :sobrou, :sem_telefone, keyword_init: true)
  ALVOS = CampaignImports::SpreadsheetReader::TARGETS
  ALVO_DO_CAMPO = { 'telefone' => 'phone', 'email' => 'email', 'nome' => 'name' }.freeze
  CONTATO = 'contato'.freeze
  CONTATOS = %w[phone email].freeze
  SEM_CONSERTO = (ALVOS - ALVO_DO_CAMPO.values).freeze
  FICAR_COM = 'ficar_com'.freeze
  # O valor que veio vazio, com os códigos que a leitura da planilha já usa.
  VAZIO = { 'phone' => 'blank_phone_number', 'email' => 'blank_email', 'name' => 'blank_name' }.freeze
  SEM_CONTATO = 'missing_contact'.freeze
  FORMULA = 'formula_detected'.freeze
  SEM_NOME = 'blank_name'.freeze
  ARROBA = '@'.freeze

  # A conferência de uma importação já lida: as colunas e a leitura de contato que a leitura da planilha usou.
  def self.da_importacao(importacao)
    resolucao = importacao.schema_resolution.to_h
    alvos = Relacionamentos::Trazer::Colunas.new(importacao).alvos
    leitura = CampaignImports::ContactReading.for(importacao.account)
    do_brasil = leitura.customer_base? && CampaignImports::PhoneCountry.from(resolucao, resolucao, alvos['phone']).brazil?
    new(alvos: alvos, contatos: CampaignImports::AudienceRowContacts.new(leitura.with_legacy_mobiles(do_brasil)))
  end

  # A coluna (índice) de cada alvo nesta leitura.
  attr_reader :alvos

  # alvos: { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => 3 }; contatos: CampaignImports::AudienceRowContacts.
  def initialize(alvos:, contatos:)
    @alvos = alvos
    @contatos = contatos
  end

  # celulas: { 'name' => 'Ana', 'phone' => '123', 'email' => '', 'company' => '' }; valores: o que já estava guardado.
  def call(numero, celulas, campo:, valor: nil, valores: {})
    return Resultado.new(motivo: SEM_CONTATO) if campo == CONTATO && valor.to_s.strip.empty?

    alvo = alvo_do(campo, valor)
    novos = alvo ? valores_com(valores, campo, alvo, valor) : valores
    motivo = alvo && motivo_do_valor(alvo, novos[alvo])
    motivo ? Resultado.new(motivo: motivo) : conferir(numero, celulas, novos)
  end

  # Os consertos guardados, conferidos de novo contra a linha como a leitura nova a viu.
  def reconferir(numero, celulas, valores)
    motivo = valores.filter_map { |alvo, valor| motivo_do_valor(alvo, valor) }.first
    motivo ? Resultado.new(motivo: motivo) : conferir(numero, celulas, valores)
  end

  private

  def alvo_do(campo, valor)
    return if campo == FICAR_COM
    return valor.to_s.include?(ARROBA) ? 'email' : 'phone' if campo == CONTATO

    ALVO_DO_CAMPO.fetch(campo)
  end

  def valores_com(valores, campo, alvo, valor)
    anteriores = campo == CONTATO ? valores.except(*CONTATOS) : valores
    anteriores.merge(alvo => valor.to_s.strip)
  end

  # O valor que a pessoa escreveu tem de valer sozinho: não basta a linha ter outro contato que vale.
  def motivo_do_valor(alvo, valor)
    return VAZIO.fetch(alvo) if valor.empty?

    sozinho = { 'phone' => [valor, nil], 'email' => [nil, valor] }[alvo]
    (sozinho && @contatos.fields(*sozinho)[:errors].first) || (FORMULA if formula?(alvo, valor))
  end

  def conferir(numero, celulas, valores)
    linha = ALVOS.index_with { |alvo| (valores[alvo] || celulas[alvo]).to_s.strip }
    contato = @contatos.fields(linha['phone'], linha['email'])
    sobrou = motivo_da_linha(linha, contato)
    return Resultado.new(valores: valores, sobrou: sobrou) if sobrou

    Resultado.new(valores: valores, conferida: conferida(numero, linha, contato), sem_telefone: sem_telefone?(contato))
  end

  # O telefone da linha tem número e não deu para ler: a máscara é a mesma que a leitura grava na linha aprovada.
  def sem_telefone?(contato)
    contato[:normalized_phone].nil? && contato[:raw_phone_masked].present?
  end

  # O primeiro motivo que falta resolver. O que a tela não conserta vem antes: com ele, consertar o resto não adianta.
  def motivo_da_linha(linha, contato)
    return FORMULA if formula_em?(linha, SEM_CONSERTO)
    return contato[:errors].first if contato[:errors].any?
    return FORMULA if formula_em?(linha, ALVO_DO_CAMPO.values)

    SEM_NOME if @alvos['name'] && linha['name'].empty?
  end

  def formula_em?(linha, alvos)
    alvos.any? { |alvo| formula?(alvo, linha[alvo]) }
  end

  def formula?(alvo, valor)
    CampaignImports::CsvSanitizer.formula_like?(valor, allow_phone_plus: alvo == 'phone')
  end

  # A linha como vai para o arquivo conferido, com as colunas dele.
  def conferida(numero, linha, contato)
    {
      'row_number' => numero, 'name' => linha['name'].squish, 'phone_number' => contato[:normalized_phone],
      'phone_hash' => contato[:normalized_phone_hash], 'email' => contato[:email], 'email_hash' => contato[:email_hash],
      'company_name' => linha['company'].squish.presence, 'batch_index' => 0
    }
  end
end
