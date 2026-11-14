# O gravador único da apólice (E4, #2897). Toda fonte que traz um seguro para a carteira (a planilha, a leitura de PDF, o
# conector, a apólice nova da renovação) entrega os dados de UMA apólice já na forma do banco e chama aqui. A regra de
# "é a mesma, é o termo novo ou é nova" mora só neste lugar.
#
#   Carteira::Guardar.new(account, origem: 'planilha', user: user, importacao: importacao, valores: { arquivo: 'carteira.xlsx' })
#                    .call(dados, contato: contato, empresa: nil)   # => Resultado(apolice:, situacao:)
#
# O lote de PDFs (E6, #2899) chama com `origem: 'pdf'` e `leitura:`: a apólice que nasce aponta para o lote
# (`leitura_id`), e os passos da história levam `valores.leitura`, que é por onde o Desfazer do lote acha o que ele
# completou. A fonte diz os passos dela: `chegou_pdf` na que nasce e `chegou_de_novo_pdf` na que muda.
#
# dados: { seguradora:, seguradora_chave:, numero:, numero_chave:, tipo:, ramo_original:, inicio_vigencia:, fim_vigencia:,
#          valor_centavos:, bem: } — a forma do banco, conferida por Carteira::Guardar::Dados.
#
# - A apólice é procurada na conta pela seguradora e pelo número; entre as achadas, a do mesmo termo de vigência
#   (Carteira::Termo: o mesmo começo ou o mesmo fim). Sem número não há como achar: nasce outra.
# - Não achou, ou é outro termo da mesma apólice (a renovação que mantém o número): nasce uma linha, com a origem de
#   quem chamou e o primeiro passo da história (`chegada`). Situação `nova`.
# - Achou e os dados da apólice não mudam: situação `igual`. Nada é gravado, a não ser quando a fonte é mais forte que
#   a `origem` guardada: aí a origem sobe e fica registrado que chegou de novo (ver a precedência, abaixo).
# - Achou e muda o tipo, o começo, o fim, o valor ou o bem (Carteira::Guardar::Mudancas): a apólice é atualizada e a
#   história ganha `chegou_de_novo` com o antes e o depois de cada campo, na forma do banco (Carteira::Campos): é o que
#   o desfazer repõe. Situação `atualizada`.
# - Achou e a apólice está cancelada: continua cancelada e não é alterada, nem a história, venha de que fonte vier
#   (da mão também). Situação `cancelada`, para quem chamou poder mostrar.
# - O campo corrigido à mão (`corrigido_a_mao`) nunca muda. O dado que não veio não apaga o que estava guardado.
# - Precedência das fontes: conector > PDF > planilha. A fonte mais fraca que a `origem` da apólice só preenche campo
#   vazio. A mais forte atualiza, e a `origem` da apólice passa a ser a dela: é sempre a fonte mais forte que já
#   escreveu ali. Quando a origem sobe, a história ganha o passo (`chegou_de_novo` com `valores.origem_antes` e
#   `valores.origem_depois`), mesmo sem campo mudado: nesse caso a situação continua `igual`, porque os dados da
#   apólice não mudaram. A apólice de origem `manual` só é completada pelas fontes.
# - A origem `manual` só CRIA: quem edita à mão a apólice que já existe é a gaveta (Carteira::Corrigir).
# - Seguradora e número são a identidade (foi por eles que a apólice foi achada): ficam como estavam.
#
# Recusas com código (CustomExceptions::CarteiraRecusa), sem tocar em nada:
# - `termo_ambiguo`: há mais de um termo guardado que pode ser o dos dados, e o gravador não adivinha (Carteira::Termo).
#   Também quando ATUALIZAR a apólice achada bate no índice único: o fim que chegou já é de outro termo guardado. Isso
#   não é corrida, é termo errado, e não há nova tentativa;
# - `apolice_de_outra_pessoa`: a apólice achada é de outro contato. Nada é mesclado nem mudado de dono;
# - `apolice_repetida`: a origem `manual` achou a apólice, ou outra gravação da mesma seguradora, número e fim chegou ao
#   mesmo tempo: CRIAR bateu no índice único, e a nova tentativa (uma só) também.
# A mensagem do banco na batida do índice único traz o número da apólice: nunca é repassada (a recusa sai sem causa).
# Erros de quem chamou (ArgumentError com o nome do que está errado, nunca com o valor): `account`, `origem`, `chegada`,
# `valores`, `user` ou `importacao` de outra conta, ao criar o gravador; `dados`, `contato`, `empresa` ou o campo fora
# da forma do banco, ao chamar.
# O que o model da apólice recusa sobe como ActiveRecord::RecordInvalid (sem seguradora, sem fim, tipo fora da lista,
# fim antes do começo, pessoa ou empresa de outra conta).
#
# Cada chamada é uma transação própria (savepoint): a apólice e o passo da história entram juntos ou não entram. As
# apólices de mesma seguradora e número ficam travadas da escolha do termo até a gravação: a correção na gaveta ao
# mesmo tempo não se perde, e duas chegadas da mesma apólice não escolhem termos diferentes. Nada daqui vai para o log.
class Carteira::Guardar
  Resultado = Struct.new(:apolice, :situacao, keyword_init: true)
  NOVA = 'nova'.freeze
  ATUALIZADA = 'atualizada'.freeze
  IGUAL = 'igual'.freeze
  CANCELADA = 'cancelada'.freeze
  MANUAL = 'manual'.freeze
  # As fontes que disputam os campos, da mais fraca para a mais forte. A apólice feita à mão fica acima de todas.
  FORCA = %w[planilha pdf conector].freeze
  # O primeiro passo da história de cada fonte. A fonte que não está aqui diz o dela em `chegada:`.
  CHEGOU = { 'planilha' => 'chegou_planilha', 'pdf' => 'chegou_pdf' }.freeze
  DE_NOVO = 'chegou_de_novo'.freeze
  # O passo de quando a apólice chega de novo e muda, da fonte que tem o seu. As outras usam DE_NOVO.
  DE_NOVO_DA = { 'pdf' => 'chegou_de_novo_pdf' }.freeze
  TERMO_AMBIGUO = 'termo_ambiguo'.freeze
  DE_OUTRA_PESSOA = 'apolice_de_outra_pessoa'.freeze
  REPETIDA = 'apolice_repetida'.freeze
  TENTATIVAS = 2
  # Criar bateu no índice único: outra gravação da mesma apólice entrou no meio. Só existe para tentar de novo.
  ChegouJunto = Class.new(StandardError)

  # origem: uma de Carteira::Apolice::ORIGENS. user: quem trouxe (nil: o sistema). importacao: a planilha que trouxe.
  # leitura: o lote de PDFs que trouxe (Carteira::Leitura). valores: o que a história mostra da chegada
  # ({ arquivo: 'carteira.xlsx' }). chegada: o tipo do primeiro passo da história da apólice que nasce (um de
  # Carteira::ApoliceEvento::TIPOS).
  # rubocop:disable Metrics/ParameterLists -- o que cada fonte diz de si, cada um com o seu padrão
  def initialize(account, origem:, user: nil, importacao: nil, leitura: nil, valores: {}, chegada: CHEGOU[origem])
    # rubocop:enable Metrics/ParameterLists
    @account = account
    @origem = origem
    @user = user
    @importacao = importacao
    @leitura = leitura
    @valores = leitura && valores.is_a?(Hash) ? valores.merge(leitura: leitura.id) : valores
    @chegada = chegada
    @de_novo = DE_NOVO_DA.fetch(origem, DE_NOVO)
    conferir_a_fonte
  end

  def call(dados, contato:, empresa: nil)
    dados = Carteira::Guardar::Dados.call(dados)
    raise ArgumentError, 'contato' unless contato.is_a?(Contact)
    raise ArgumentError, 'empresa' unless empresa.nil? || empresa.is_a?(Company)

    tentativas = 0
    begin
      Carteira::Apolice.transaction(requires_new: true) { gravar(dados, contato, empresa) }
    rescue ChegouJunto
      retry if (tentativas += 1) < TENTATIVAS
      recusar(REPETIDA)
    end
  end

  private

  def conferir_a_fonte
    raise ArgumentError, 'account' unless @account.is_a?(Account)
    raise ArgumentError, 'origem' unless Carteira::Apolice::ORIGENS.include?(@origem)
    raise ArgumentError, 'chegada' unless Carteira::ApoliceEvento::TIPOS.include?(@chegada)
    raise ArgumentError, 'valores' unless @valores.is_a?(Hash)

    conferir_que_sao_da_conta
  end

  def conferir_que_sao_da_conta
    raise ArgumentError, 'user' unless @user.nil? || @account.account_users.exists?(user_id: @user.id)
    raise ArgumentError, 'importacao' unless @importacao.nil? || @importacao.account_id == @account.id
    raise ArgumentError, 'leitura' unless @leitura.nil? || @leitura.account_id == @account.id
  end

  def gravar(dados, contato, empresa)
    guardada = achar(dados)
    return Resultado.new(apolice: criar(dados, contato, empresa), situacao: NOVA) unless guardada

    recusar(DE_OUTRA_PESSOA) unless guardada.contact_id == contato.id
    return Resultado.new(apolice: guardada, situacao: CANCELADA) if guardada.cancelado_em

    recusar(REPETIDA) if @origem == MANUAL
    atualizar(guardada, dados)
  end

  # Trava as apólices de mesma seguradora e número e escolhe, entre elas, a do termo dos dados.
  def achar(dados)
    return if dados[:numero_chave].blank?

    guardadas = Carteira::Apolice.where(account_id: @account.id, **dados.slice(:seguradora_chave, :numero_chave)).lock.order(:id).to_a
    achada = Carteira::Termo.escolher(guardadas, dados)
    achada == Carteira::Termo::AMBIGUO ? recusar(TERMO_AMBIGUO) : achada
  end

  def criar(dados, contato, empresa)
    apolice = Carteira::Apolice.create!(
      dados.merge(account: @account, contact: contato, company: empresa, origem: @origem, campaign_import: @importacao, leitura: @leitura)
    )
    registrar(apolice, @chegada, valores: @valores)
    apolice
  rescue ActiveRecord::RecordNotUnique
    raise ChegouJunto
  end

  def atualizar(apolice, dados)
    mudancas = Carteira::Guardar::Mudancas.new(apolice, dados, mais_fraca: forca(@origem) < forca(apolice.origem))
    origem = forca(@origem) > forca(apolice.origem) ? @origem : apolice.origem
    return Resultado.new(apolice: apolice, situacao: IGUAL) if mudancas.nenhuma? && origem == apolice.origem

    subiu = origem == apolice.origem ? {} : { origem_antes: apolice.origem, origem_depois: origem }
    apolice.update!(mudancas.colunas.merge(origem: origem))
    registrar(apolice, @de_novo, valores: @valores.merge(subiu), mudancas: mudancas.lista.presence)
    Resultado.new(apolice: apolice, situacao: mudancas.nenhuma? ? IGUAL : ATUALIZADA)
  rescue ActiveRecord::RecordNotUnique
    recusar(TERMO_AMBIGUO)
  end

  def forca(origem)
    FORCA.index(origem) || FORCA.size
  end

  def registrar(apolice, tipo, valores:, mudancas: nil)
    apolice.eventos.create!(tipo: tipo, quando: Time.current, user: @user, campaign_import: @importacao, valores: valores, mudancas: mudancas)
  end

  # Só o código: sem a causa, que pode ser a mensagem do banco com o número da apólice.
  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
  end
end
