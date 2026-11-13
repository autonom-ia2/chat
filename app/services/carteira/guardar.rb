# O gravador único da apólice (E4, #2897). Toda fonte que traz um seguro para a carteira (a planilha, a leitura de PDF, o
# conector, a apólice nova da renovação) entrega os dados de UMA apólice já na forma do banco e chama aqui. A regra de
# "é a mesma, é o termo novo ou é nova" mora só neste lugar.
#
#   Carteira::Guardar.new(account, origem: 'planilha', user: user, importacao: importacao, valores: { arquivo: 'carteira.xlsx' })
#                    .call(dados, contato: contato, empresa: nil)   # => Resultado(apolice:, situacao:)
#
# dados: { seguradora:, seguradora_chave:, numero:, numero_chave:, tipo:, ramo_original:, inicio_vigencia:, fim_vigencia:,
#          valor_centavos:, bem: } — as chaves de Carteira::Chave, o valor em centavos, as datas como Date ou AAAA-MM-DD.
# O que não veio é nil (nunca texto vazio). Qualquer outra chave é ignorada.
#
# - A apólice é achada na conta pela seguradora e pelo número; entre as achadas, a do mesmo termo de vigência
#   (Carteira::Termo) e, havendo mais de uma, a que termina mais perto. Sem número não há como achar: nasce outra.
# - Não achou, ou é o termo novo da mesma apólice (a renovação que mantém o número): nasce uma linha, com a origem de
#   quem chamou e o primeiro passo da história (`chegada`). Situação `nova`.
# - Achou e nada muda: nada é gravado na história. Situação `igual`.
# - Achou e muda o tipo, o começo, o fim, o valor ou o bem (Carteira::Guardar::Mudancas): a apólice é atualizada e a
#   história ganha `chegou_de_novo` com o antes e o depois de cada campo, na forma do banco (Carteira::Campos): é o que
#   o desfazer repõe. Situação `atualizada`.
# - O campo corrigido à mão (`corrigido_a_mao`) nunca muda. O dado que não veio não apaga o que estava guardado.
# - Precedência das fontes: conector > PDF > planilha. A fonte mais fraca que a `origem` da apólice só preenche campo
#   vazio. A mais forte atualiza, e a `origem` da apólice passa a ser a dela: é sempre a fonte mais forte que já
#   escreveu ali. A apólice feita à mão não é mexida por fonte nenhuma, só completada.
# - Seguradora e número são a identidade (foi por eles que a apólice foi achada): ficam como estavam. A pessoa e a
#   empresa também: nenhuma fonte muda um seguro de dono. O seguro cancelado continua cancelado.
#
# A apólice achada fica travada enquanto é comparada e gravada: a correção na gaveta ao mesmo tempo não se perde. A
# transação é própria (savepoint): a apólice e o passo da história entram juntos ou não entram.
#
# Recusas (quem chama decide o que fazer com elas):
# - ArgumentError, ao criar o gravador: `origem` fora de Carteira::Apolice::ORIGENS, ou fonte sem primeiro passo da
#   história (`chegada`) conhecido;
# - Date::Error: data em texto que não é AAAA-MM-DD;
# - ActiveRecord::RecordInvalid: o que o model da apólice recusa (sem seguradora, sem fim, tipo fora da lista, fim antes
#   do começo, pessoa ou empresa de outra conta);
# - ActiveRecord::RecordNotUnique: outra gravação da mesma seguradora, número e fim chegou ao mesmo tempo.
#
# Nada daqui vai para o log.
class Carteira::Guardar
  Resultado = Struct.new(:apolice, :situacao, keyword_init: true)
  NOVA = 'nova'.freeze
  ATUALIZADA = 'atualizada'.freeze
  IGUAL = 'igual'.freeze
  # Da mais fraca para a mais forte.
  FORCA = %w[planilha pdf conector manual].freeze
  # O primeiro passo da história de cada fonte. A fonte que não está aqui diz o dela em `chegada:`.
  CHEGOU = { 'planilha' => 'chegou_planilha' }.freeze
  DE_NOVO = 'chegou_de_novo'.freeze
  DADOS = %i[seguradora seguradora_chave numero numero_chave tipo ramo_original inicio_vigencia fim_vigencia valor_centavos bem].freeze
  DATAS = %i[inicio_vigencia fim_vigencia].freeze

  # origem: uma de Carteira::Apolice::ORIGENS. user: quem trouxe (nil: o sistema). importacao: o lote que trouxe.
  # valores: o que a história mostra da chegada ({ arquivo: 'carteira.xlsx' }). chegada: o tipo do primeiro passo da
  # história da apólice que nasce (um de Carteira::ApoliceEvento::TIPOS).
  # rubocop:disable Metrics/ParameterLists -- o que cada fonte diz de si, cada um com o seu padrão
  def initialize(account, origem:, user: nil, importacao: nil, valores: {}, chegada: CHEGOU[origem])
    # rubocop:enable Metrics/ParameterLists
    raise ArgumentError, 'origem' unless FORCA.include?(origem)
    raise ArgumentError, 'chegada' unless Carteira::ApoliceEvento::TIPOS.include?(chegada)

    @account = account
    @origem = origem
    @user = user
    @importacao = importacao
    @valores = valores
    @chegada = chegada
  end

  def call(dados, contato:, empresa: nil)
    dados = na_forma_do_banco(dados)
    guardada = achar(dados)
    guardada ? atualizar(guardada, dados) : Resultado.new(apolice: criar(dados, contato, empresa), situacao: NOVA)
  end

  private

  def na_forma_do_banco(dados)
    dados = dados.to_h.symbolize_keys.slice(*DADOS)
    dados.merge(dados.slice(*DATAS).transform_values { |data| data.is_a?(String) ? Date.iso8601(data) : data })
  end

  # Sem número ou sem fim não há o que comparar: quem recusa a apólice sem fim é o model, na criação.
  def achar(dados)
    return if dados[:numero_chave].blank? || dados[:fim_vigencia].nil?

    mesmas = Carteira::Apolice.where(account_id: @account.id, **dados.slice(:seguradora_chave, :numero_chave))
                              .select { |apolice| Carteira::Termo.mesmo?(apolice, dados) }
    mesmas.min_by { |apolice| [(apolice.fim_vigencia - dados[:fim_vigencia]).abs, apolice.id] }
  end

  def criar(dados, contato, empresa)
    Carteira::Apolice.transaction(requires_new: true) do
      apolice = Carteira::Apolice.create!(
        dados.merge(account: @account, contact: contato, company: empresa, origem: @origem, campaign_import: @importacao)
      )
      registrar(apolice, @chegada)
      apolice
    end
  end

  def atualizar(apolice, dados)
    apolice.with_lock(requires_new: true) do
      mudancas = Carteira::Guardar::Mudancas.new(apolice, dados, mais_fraca: mais_fraca?(apolice))
      origem = mais_forte?(apolice) ? @origem : apolice.origem
      apolice.update!(mudancas.colunas.merge(origem: origem))
      next Resultado.new(apolice: apolice, situacao: IGUAL) if mudancas.nenhuma?

      registrar(apolice, DE_NOVO, mudancas: mudancas.lista)
      Resultado.new(apolice: apolice, situacao: ATUALIZADA)
    end
  end

  def mais_fraca?(apolice)
    FORCA.index(@origem) < FORCA.index(apolice.origem)
  end

  def mais_forte?(apolice)
    FORCA.index(@origem) > FORCA.index(apolice.origem)
  end

  def registrar(apolice, tipo, mudancas: nil)
    apolice.eventos.create!(tipo: tipo, quando: Time.current, user: @user, campaign_import: @importacao, valores: @valores, mudancas: mudancas)
  end
end
