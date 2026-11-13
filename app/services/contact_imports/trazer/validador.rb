# A leitura da planilha de "Trazer minha lista" (#2896): a importação de contatos com a marca options['trazer'].
# ContactImports::Validator passa a vez para cá quando a importação tem a marca; sem ela nada daqui roda.
#
# O que muda em relação a "Importar contatos":
# - a leitura nunca para para perguntar as colunas: a sugestão do leitor é aceita e schema_resolution guarda as colunas
#   incertas, que a tela mostra como "duvidosa" (Relacionamentos::Trazer::Colunas). Sem coluna de telefone nem de e-mail
#   não há quem trazer, e a leitura falha com `missing_contact_column`;
# - a coluna que a pessoa marcou "não guardar" não deixa valor nas linhas nem entra na prévia das informações;
# - o telefone é lido como está na coluna dele. O DDD que vem em outra coluna não é juntado ao número: decidir pelo
#   título qual coluna é o DDD seria adivinhar o que a pessoa escreveu (#3010). O número sem DDD vira problema de
#   telefone, e a planilha em que nenhuma linha tem contato que dê para usar falha com `no_valid_rows`. A linha que
#   tem e-mail bom entra só com o e-mail (regra de CampaignImports::AudienceRowContacts, que não muda), e a leitura
#   conta quantas são para a tela avisar (`sem_telefone`);
# - a mesma pessoa em várias linhas vira uma linha só, ou problema quando as linhas se contradizem
#   (ContactImports::Trazer::MesmaPessoa); a linha sem nome vira problema de nome;
# - as linhas com problema ganham um arquivo próprio (ContactImports::Trazer::LinhasComProblema), trocado a cada leitura,
#   só com as células dos quatro alvos;
# - a coluna que diz quem é cliente tem os valores dela contados, também num arquivo próprio trocado a cada leitura
#   (ContactImports::Trazer::ValoresDeCliente). A escolha que a pessoa tinha feito só continua valendo se os valores
#   escolhidos ainda existem;
# - o que a pessoa já tinha consertado e deixado de fora continua valendo quando a planilha é lida de novo
#   (ContactImports::Trazer::ConsertosDaLeitura). O arquivo dos consertos não é apagado pela leitura: a que falha não
#   perde nada. O arquivo conferido só recebe os consertos na hora de trazer (ContactImports::Trazer::FecharConferencia);
# - a leitura que falha depois de uma mudança da pessoa (troca de coluna, resposta) desfaz a mudança e lê de novo, uma
#   vez só (ContactImports::Trazer::DesfazerMudanca). Sem mudança para desfazer, falha como sempre.
# validation_summary guarda só contagens: `mesma_pessoa` (linhas juntadas a outra) e `sem_telefone` (pessoas que
# entram sem o telefone que estava escrito na planilha).
#
# A trava da leitura. A leitura de planilhas não aguenta duas execuções da mesma importação, nem juntas nem em
# sequência: a que termina por último apaga as linhas e regrava o estado, até no meio da gravação. Aqui:
# - na entrada, sob a trava da importação, a leitura só começa a partir de um estado de leitura (LEITURA): nunca de uma
#   lista já mandada trazer, gravando, gravada ou que falhou na gravação. Ela deixa a importação `validating` e guarda
#   o número dela (options['trazer']['leitura']);
# - no fim, dentro da transação que grava o resultado (a que dá certo e a que falha) e antes de apagar qualquer coisa,
#   a importação é travada e conferida: se o número não é mais o desta leitura, ou o estado não é mais `validating`,
#   outra leitura (ou a varredura) passou na frente e esta é descartada sem tocar em nada. O número, o instante em que
#   a leitura começou (options['trazer']['leitura_em'], que diz à varredura há quanto tempo ela roda) e a contagem das
#   voltas da varredura saem na mesma transação.
#
# A trava é tomada no primeiro passo da transação que grava o resultado e fica até o commit: toda escrita na importação
# espera por ela. Por isso o que não precisa da trava fica fora dela:
# - o tipo de cada coluna (CampaignImports::ColumnTypes, uma chamada externa) é perguntado antes de a transação abrir;
# - os arquivos do resultado anterior (conferido, erros, relatório) saem pelo ContactImports::Trazer::ApagarAnexo: o
#   anexo sai na transação e o arquivo é apagado do armazenamento depois do commit, em vez de dentro dela.
# Dentro da trava ficam o que precisa dela: apagar e gravar as linhas (até 50 mil) e as contas que leem a conta
# (empresas, atributos, contatos que já existem).
class ContactImports::Trazer::Validador < ContactImports::Validator
  LEITURA = %w[uploaded validating needs_column_choice ready_to_confirm validation_failed].freeze
  DA_LEITURA = %w[leitura leitura_em releituras].freeze
  DO_RESULTADO = %i[normalized_csv error_csv report_csv].freeze
  # A leitura que perdeu a vez: só existe para sair da transação sem gravar nada.
  Superada = Class.new(StandardError)

  def perform
    super if comecar
  end

  private

  def comecar
    campaign_import.with_lock do
      next false unless LEITURA.include?(campaign_import.status)

      @leitura = SecureRandom.uuid
      ContactImports::Trazer::Conferencia.new(campaign_import).gravar('leitura' => @leitura, 'leitura_em' => Time.current.iso8601)
      campaign_import.update!(status: :validating)
      true
    end
  end

  def conferir_que_a_leitura_e_esta!
    campaign_import.lock!
    conferencia = ContactImports::Trazer::Conferencia.new(campaign_import)
    raise Superada unless campaign_import.validating? && conferencia.leitura == @leitura

    conferencia.tirar(*DA_LEITURA)
  end

  def descartar
    Rails.logger.warn("[ContactImports::Trazer::Validador] import_id=#{campaign_import.id} superseded")
    nil
  end

  def validate_parsed_file(parsed_file)
    @consertos = ContactImports::Trazer::ConsertosDaLeitura.new(campaign_import)
    super
  end

  def read(parsed_file)
    reading = super
    return reading unless reading.needs_column_choice? && reading.mapping.values_at(*CONTACT_TARGETS).any?

    CampaignImports::SpreadsheetReader::Result.new(**reading.to_h, resolution: reading.resolution.merge('needs_confirmation' => false))
  end

  def mark_needs_column_choice
    mark_validation_failed(['missing_contact_column'], [])
  end

  # A leitura que falha nunca regrava os arquivos da conferência como se tivesse dado certo: `@pronta` volta a ser
  # falso, mesmo que a falha tenha vindo depois de as linhas serem conferidas. A falha que veio de um erro pode ter
  # desfeito uma transação pela metade: a importação é lida de novo do banco, para os anexos na memória não apontarem
  # para arquivos que a transação desfeita nunca chegou a gravar.
  def mark_validation_failed(global_errors, row_results, exception: nil)
    @pronta = false
    campaign_import.reload if exception
    desfazer = ContactImports::Trazer::DesfazerMudanca.new(campaign_import)
    desfazer.pendente? ? desfazer.call(@leitura) : super
  rescue Superada
    descartar
  end

  # As células que a conferência usa: só as dos quatro alvos, nunca as das outras colunas.
  def audience_row(row, mapping)
    super.merge(celulas: TARGETS.index_with { |alvo| value_at(row, mapping[alvo]) })
  end

  def extra_values(row)
    super.except(*colunas_que_nao_guardam)
  end

  def colunas_que_nao_guardam
    @colunas_que_nao_guardam ||= Relacionamentos::Trazer::Colunas.chaves_que_nao_guardam(campaign_import.options, @reading.extra_columns)
  end

  # Fora da prévia das informações: o que não é guardado e o que vai para a cidade, o telefone da empresa ou o cliente.
  def discarded_columns
    destinos = ContactImports::Trazer::Conferencia.new(campaign_import).destinos
    @reading.extra_columns.filter_map { |extra| extra['key'] if destinos.key?(extra['index'].to_s) }
  end

  # A mesma pessoa em várias linhas vira uma linha só, ou problema quando as linhas se contradizem
  # (ContactImports::Trazer::MesmaPessoa). Depois disso, a linha que vai entrar e não tem nome vira problema de nome:
  # só quando a planilha tem coluna de nome, e só o que sobrou sem nome depois de juntar as linhas da mesma pessoa.
  def add_duplicate_errors(row_results)
    @juntadas = ContactImports::Trazer::MesmaPessoa.new(row_results).call
    return if @reading.mapping['name'].nil?

    row_results.each { |row| row[:errors] << 'blank_name' if row[:errors].empty? && row[:normalized_name].blank? }
  end

  def ready_attributes(row_results, valid_rows, invalid_rows, plan)
    attributes = super
    summary = attributes[:validation_summary].merge(mesma_pessoa: @juntadas.to_i, sem_telefone: sem_telefone(valid_rows))
    opcoes = valores_de_cliente.opcoes_depois_da_leitura(@consertos.opcoes_depois_da_leitura(row_results))
    attributes.merge(validation_summary: summary, options: opcoes)
  end

  # Quantas pessoas entram sem o telefone que estava escrito na planilha: a célula do telefone tem alguma coisa, não deu
  # para ler como celular, e a linha entra pelo e-mail. Só a contagem sai daqui, nunca o que estava na célula.
  def sem_telefone(valid_rows)
    valid_rows.count { |row| row[:normalized_phone].blank? && row.dig(:celulas, 'phone').present? }
  end

  def mark_ready(row_results)
    @pronta = true
    @consertos.reaplicar(row_results, ContactImports::Trazer::Conserto.new(alvos: @reading.mapping, contatos: row_contacts))
    @tipos_das_colunas = CampaignImports::ColumnTypes.new(@reading).perform
    super
  rescue Superada
    descartar
  end

  # O tipo de cada coluna já foi perguntado antes de a transação abrir (mark_ready): aqui só entra no resultado.
  def with_column_types(resolution)
    @tipos_das_colunas ? resolution.merge(CampaignImports::ColumnTypes::RESOLUTION_KEY => @tipos_das_colunas) : resolution
  end

  # O primeiro passo das duas transações que gravam o resultado: antes dele nada foi apagado. Os arquivos do resultado
  # anterior saem aqui, sem chamada ao armazenamento dentro da trava; o `super` não acha mais o que apagar.
  def reset_validation_rows!
    conferir_que_a_leitura_e_esta!
    DO_RESULTADO.each { |nome| ContactImports::Trazer::ApagarAnexo.call(campaign_import.public_send(nome)) }
    super
    linhas_com_problema.apagar
    valores_de_cliente.apagar
  end

  def persist_rows(row_results)
    super
    return unless @pronta

    linhas_com_problema.gravar(row_results.select { |row| row[:errors].present? })
    @consertos.gravar
    valores_de_cliente.gravar_da_leitura(@reading.extra_columns, row_results)
  end

  def linhas_com_problema
    @linhas_com_problema ||= ContactImports::Trazer::LinhasComProblema.new(campaign_import)
  end

  def valores_de_cliente
    @valores_de_cliente ||= ContactImports::Trazer::ValoresDeCliente.new(campaign_import)
  end
end
