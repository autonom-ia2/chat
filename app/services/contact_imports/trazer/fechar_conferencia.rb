# "Trazer minha lista" (#2896): fecha a conferência depois que a pessoa mandou trazer. Roda num job
# (ContactImports::Trazer::FecharConferenciaJob), sob a trava da importação e uma vez só: é o único ponto que abre o
# arquivo conferido inteiro.
#
# - O arquivo conferido fica só com as linhas que vão entrar: as aprovadas na leitura e as que a pessoa consertou
#   (ContactImports::Trazer::Consertos), sem as que ela deixou de fora e sem as que ficaram com o problema aberto. Quem
#   entra é o que ContactImports::Trazer::QuemEntra diz, a mesma conta que a tela mostrou.
# - A linha consertada passa a ser linha aprovada no banco, com o que toda linha aprovada tem (nome, hashes e máscaras:
#   nunca o telefone nem o e-mail inteiros). A linha aprovada que perdeu o lugar para uma repetida que a pessoa
#   escolheu manter deixa de ser.
# - A importação passa a contar as linhas que vão entrar de verdade.
#
# Rodar de novo não muda nada: a linha consertada já é aprovada e já está no arquivo. Sem o arquivo conferido (apagado
# pelo prazo) nada é mexido e `call` devolve falso: quem chama encerra a lista como falha.
#
# Em dois tempos, para a trava da importação não esperar o armazenamento:
# - `preparar`, FORA da trava, baixa o arquivo conferido e os consertos;
# - `call`, SOB a trava, só mexe no banco. Antes confere que os dois arquivos ainda são os que foram baixados (pelo
#   blob de cada um: arquivo trocado é blob novo); se não são, baixa de novo ali mesmo. O arquivo conferido regravado
#   só é enviado ao armazenamento depois do commit.
class ContactImports::Trazer::FecharConferencia
  DEIXADA = 'left_out'.freeze

  def initialize(importacao)
    @importacao = importacao
    @conferido = ContactImports::Trazer::ArquivoConferido.new(importacao)
  end

  # Devolve o próprio fechamento, para quem chama guardar e fechar depois.
  def preparar
    @baixados = arquivos
    return self unless @conferido.existe?

    @linhas = @conferido.linhas
    @consertos = ContactImports::Trazer::Consertos.new(@importacao).ler
    self
  end

  # Devolve se fechou.
  def call
    preparar unless @baixados == arquivos
    return false unless @conferido.existe?

    quem = ContactImports::Trazer::QuemEntra.new(@importacao, @consertos)
    entram = regravar_o_conferido(quem.novas, quem.trocadas)
    aprovar(quem.novas)
    tirar(quem.trocadas)
    @importacao.update!(valid_rows: entram, invalid_rows: @importacao.total_rows - entram)
    true
  end

  private

  def arquivos
    [@importacao.normalized_csv.blob&.id, @importacao.consertos.blob&.id]
  end

  # Devolve quantas linhas o arquivo conferido passou a ter.
  def regravar_o_conferido(novas, trocadas)
    protegidas = novas.transform_values { |conferida| ContactImports::Trazer::ArquivoConferido.protegida(conferida) }
    ficam = @linhas.except(*trocadas).merge(protegidas).sort.to_h
    @conferido.regravar(ficam)
    ficam.size
  end

  # novas: { número => a linha conferida } das linhas consertadas que vão entrar.
  def aprovar(novas)
    linhas.where(row_number: novas.keys).find_each do |linha|
      conferida = novas.fetch(linha.row_number)
      linha.update!(aprovada(conferida).merge(mascaras(linha, conferida)))
    end
  end

  def aprovada(conferida)
    { status: :valid, error_messages: [], raw_name: conferida['name'].to_s, normalized_name: conferida['name'].to_s,
      normalized_phone_hash: conferida['phone_hash'].presence, normalized_email_hash: conferida['email_hash'].presence,
      company_name: conferida['company_name'].presence }
  end

  def mascaras(linha, conferida)
    telefone = conferida['phone_number'].presence
    email = conferida['email'].presence
    { raw_phone_masked: telefone ? CampaignImports::PhoneNormalizer.mask(telefone) : linha.raw_phone_masked,
      email_masked: email ? EmailCampaigns::EmailNormalizer.mask(email) : linha.email_masked }
  end

  def tirar(numeros)
    linhas.status_valid.where(row_number: numeros).find_each { |linha| linha.update!(status: :invalid, error_messages: [DEIXADA]) }
  end

  def linhas
    @importacao.campaign_import_rows
  end
end
