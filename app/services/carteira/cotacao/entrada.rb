# A entrada da cotação de renovação montada a partir do seguro da carteira (E8, #2901), no formato dos parâmetros da
# ferramenta de cotação (Autonomia::Agents::Tools::Native::InsuranceQuote): é ela que confere e cota, com o mesmo
# QuoteInput, sem lógica copiada para cá.
#
# A regra da Cotação (contrato da E8): a renovação só cota com TUDO isto, e nunca como seguro novo:
# - o código da seguradora anterior por fonte certa: o nome do seguro bate, pela forma de comparação da carteira
#   (Carteira::Chave.seguradora), com UM nome da lista de seguradoras anteriores que o formulário da conexão traz (o
#   schema do adapter, `valores`). Sem lista, sem nenhum ou com mais de um: falta. Nada de chute;
# - o número e o fim da vigência do seguro que vence;
# - a classe de bônus como está na apólice, sem recalcular (E8.1, #3043: `bonus_classe`, lida do PDF ou escrita à mão).
#   Nos outros ramos ela só vai quando é um dos valores da lista do formulário; fora da lista, ou sem lista, falta;
# - os sinistros da apólice ou em branco (nunca zero): a carteira não guarda, e vão em branco;
# - os obrigatórios do ramo. Auto: nome, CPF/CNPJ, nascimento, sexo, CEP e placa (ou FIPE ou chassi). Demais ramos: os
#   campos obrigatórios que o cliente informa no formulário do ramo.
#
# Os dados do segurado que a carteira guarda (E8.1): em auto, `insured.birthDate` e `insured.gender` (só do segurado
# pessoa: a empresa segurada continua sem os dois, porque o portal pede os do condutor, fora deste escopo),
# `vehicle.plate` e `quotation.bonusClass`; em todo ramo, o CEP pelo atalho `cep` (o QuoteInput o leva a
# `address.zipCode` em auto e a `segurado.cep` nos outros).
#
# A BUSCA PAGA DO SEGURADO NUNCA RODA AQUI. A conferência da ferramenta chama `quote/enrich` quando o documento veio e
# falta o que a busca acha por ele (InsuranceQuote::Veiculo#busca_do_segurado?): em auto, nome, nascimento ou sexo; nos
# outros ramos, o nome. Esses campos estão SEMPRE em `faltam` quando a carteira não os tem, mesmo que o formulário do
# ramo não os peça, e a renovação nunca chega à conferência sem eles: o robô usa só o que a carteira tem, e as novas
# tentativas da conferência (CotarJob) não pagam de novo.
#
# -> `Resultado` com o produto, os parâmetros da ferramenta e `faltam` (só os NOMES dos campos, no formato do adapter;
# vazio quando dá para cotar). O CPF sai do documento guardado da pessoa (ou da empresa segurada), nunca de texto.
class Carteira::Cotacao::Entrada
  Resultado = Data.define(:produto, :params, :faltam)

  PRODUTOS = { 'auto' => 'auto', 'residencial' => 'residencial', 'vida' => 'vida', 'empresarial' => 'empresarial' }.freeze
  AUTO = 'auto'.freeze
  # Onde cada dado da renovação mora no formulário: auto tem o bloco `quotation`; os outros ramos, o grupo `renovacao`.
  RENOVACAO = {
    AUTO => { grupo: 'quotation', seguradora: 'previousInsurerCode', numero: 'previousPolicyNumber',
              fim: 'previousPolicyEndDate', bonus: 'bonusClass', marca: 'isRenewal' },
    nil => { grupo: 'renovacao', seguradora: 'seguradoraAnterior', numero: 'numeroApolice', fim: 'fimVigencia', bonus: 'bonus' }
  }.freeze
  OBRIGATORIOS_DE_AUTO = %w[insured.name insured.document insured.birthDate insured.gender address.zipCode].freeze
  # O que a busca paga do segurado acharia nos outros ramos (em auto, já está em OBRIGATORIOS_DE_AUTO).
  NOME_NOS_RAMOS = 'segurado.nome'.freeze
  # O que a busca paga do segurado acha pelo documento (InsuranceQuote::Veiculo#busca_do_segurado?), em auto e nos
  # outros ramos. `entrada_spec` prende esta lista à da ferramenta: se a busca passar a procurar outro campo, ele falha.
  BUSCADOS_PELO_DOCUMENTO = { AUTO => %w[insured.name insured.birthDate insured.gender], nil => [NOME_NOS_RAMOS] }.freeze
  VEICULO = %w[plate fipeCode chassis].freeze
  PLACA = 'vehicle.plate'.freeze

  # conexao: a conexão pronta da conta com o portal. O formulário do ramo é o que ela guarda, pela mesma busca da
  # ferramenta de cotação (`schema_da_conexao`, que busca de graça quando falta).
  def initialize(apolice, conexao)
    @apolice = apolice
    @conexao = conexao
  end

  def call
    produto = PRODUTOS[@apolice.tipo]
    return Resultado.new(produto: nil, params: {}, faltam: ['produto']) if produto.nil?

    @schema = Autonomia::Agents::Tools::Native::InsuranceQuote.schema_da_conexao(@conexao, produto)
    params = base.merge('produto' => produto, 'item' => item, renovacao(produto)[:grupo] => da_renovacao(produto))
    params = params.merge(de_auto) if produto == AUTO
    Resultado.new(produto: produto, params: params, faltam: faltam(produto, params))
  end

  private

  def renovacao(produto)
    RENOVACAO.fetch(produto == AUTO ? AUTO : nil)
  end

  # O nome do bem desta cotação, distinto do que a Lia dá numa cotação da conversa (Insurance::Faixa).
  def item
    "renovação #{@apolice.bem.presence || @apolice.tipo}"
  end

  def base
    { 'cpf' => documento, 'nome' => segurado_nome, 'cep' => @apolice.cep }.compact
  end

  def segurado_nome
    (@apolice.company || @apolice.contact)&.name.presence
  end

  def documento
    dono = @apolice.company || @apolice.contact
    Relacionamentos::Documento.da_conta(@apolice.account).do_dono(dono).order(:id).first&.valor
  end

  # Sinistros não vão: a carteira não guarda (em branco, nunca zero).
  def da_renovacao(produto)
    nomes = renovacao(produto)
    dados = { nomes[:seguradora] => codigo_da_seguradora(produto), nomes[:numero] => @apolice.numero.presence,
              nomes[:fim] => @apolice.fim_vigencia.iso8601, nomes[:bonus] => bonus(produto) }
    dados[nomes[:marca]] = true if nomes[:marca]
    dados.compact
  end

  # Em auto, a classe como está; nos outros ramos, só quando é um dos valores da lista do formulário.
  def bonus(produto)
    classe = @apolice.bonus_classe
    return classe if classe.nil? || produto == AUTO

    nomes = renovacao(produto)
    opcoes = campo("#{nomes[:grupo]}.#{nomes[:bonus]}").to_h['valores']
    classe if opcoes.is_a?(Hash) && opcoes.key?(classe.to_s)
  end

  # Auto: o nascimento e o sexo do segurado pessoa, e a placa.
  def de_auto
    segurado = @apolice.company ? {} : { 'birthDate' => @apolice.segurado_nascimento, 'gender' => @apolice.segurado_sexo }.compact
    { 'insured' => segurado.presence, 'vehicle' => ({ 'plate' => @apolice.placa } if @apolice.placa) }.compact
  end

  def codigo_da_seguradora(produto)
    nomes = renovacao(produto)
    opcoes = campo("#{nomes[:grupo]}.#{nomes[:seguradora]}").to_h['valores']
    return unless opcoes.is_a?(Hash)

    iguais = opcoes.select { |_codigo, nome| Carteira::Chave.seguradora(nome.to_s) == @apolice.seguradora_chave }
    iguais.keys.first.to_s if iguais.size == 1
  end

  def campo(caminho)
    Array(@schema.to_h['campos']).find { |item| item.is_a?(Hash) && item['campo'] == caminho }
  end

  def faltam(produto, params)
    nomes = renovacao(produto)
    sem_valor = [nomes[:seguradora], nomes[:numero], nomes[:fim], nomes[:bonus]].reject { |nome| params[nomes[:grupo]].key?(nome) }
    do_seguro = sem_valor.map { |nome| "#{nomes[:grupo]}.#{nome}" }
    do_seguro + (produto == AUTO ? faltam_de_auto(params) : faltam_do_ramo(params))
  end

  # Auto: o QuoteInput lê o CPF, o nome e o CEP dos atalhos `cpf`, `nome` e `cep`; o nascimento e o sexo vêm no bloco.
  def faltam_de_auto(params)
    segurado = params['insured'].to_h
    tem = { 'insured.name' => params['nome'], 'insured.document' => params['cpf'], 'insured.birthDate' => segurado['birthDate'],
            'insured.gender' => segurado['gender'], 'address.zipCode' => params['cep'] }
    faltando = OBRIGATORIOS_DE_AUTO.reject { |caminho| tem[caminho].present? }
    veiculo = params['vehicle'].to_h
    VEICULO.any? { |nome| veiculo[nome].present? } ? faltando : faltando + [PLACA]
  end

  # Demais ramos: o obrigatório que o cliente informa, fora o que já vai (o CPF, o nome e o CEP do segurado), e o nome
  # sempre que não vai (é o que a busca paga acharia).
  def faltam_do_ramo(params)
    tem = { 'segurado.cpfCnpj' => params['cpf'], NOME_NOS_RAMOS => params['nome'], 'segurado.cep' => params['cep'] }
    do_formulario = obrigatorios_do_cliente.reject { |caminho| caminho.start_with?('renovacao.') || tem[caminho].present? }
    params['nome'].present? ? do_formulario : (do_formulario | [NOME_NOS_RAMOS])
  end

  def obrigatorios_do_cliente
    Array(@schema.to_h['campos']).select { |item| item.is_a?(Hash) && item['obrigatorio'] && item['origem'] == 'cliente' }
                                 .map { |item| item['campo'].to_s }
  end
end
