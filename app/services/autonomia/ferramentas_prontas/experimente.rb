# O "EXPERIMENTE" DA VITRINE (#2858, F2): a pessoa testa a fonte antes de ensinar ao agente, com um valor só (o CEP, o
# CNPJ, o DDD...), e vê o que o agente receberia. Roda a mesma `Execucao` do atendimento, numa ferramenta que não é
# salva: o mesmo catálogo, reserva, cache e motivo de falha, e a consulta CONTA no limite do dia da conta naquela
# fonte — é o freio contra quem usasse o botão como consulta grátis sem fim.
#
# O acesso da conta na fonte (`Acesso`, a chave interna) nasce aqui se ainda não existe: a `Execucao` exige um. Quem
# incluiu fica gravado no primeiro "Incluir".
#
# `EXEMPLOS`: a consulta de cada fonte e em qual parâmetro entra o valor digitado. Fonte sem campo (o Banco Central)
# responde a cotação do dólar. A localização recebe "latitude, longitude" num campo só. `senao`: a consulta de quando o
# valor não serve no campo (o banco: "341" vai pelo código, "Itaú" pelo nome). Quem decide é o formato do parâmetro
# (`Parametro#normalizar`), não uma lista de palavras.
#
# `COM_TEXTO_LIVRE`: a fonte em que a pessoa escreve como falaria ("Onix 2020", "Ribeirão Preto", "dias úteis até
# 30/11"). Quem entende o texto é o modelo, pela IA da conta (`Experimente::ComModelo`), como o agente faria.
#
# O card Premium (F7, decisão A do Rodrigo, 11/11) também tem o "Experimente", com texto livre: o teste é uma consulta
# normal, pelo caminho do agente (`FerramentasProntas.executor_para`, a `Premium::Execucao`), e usa as 20 grátis do mês
# do card, a mesma telemetria, a mesma cobrança e o mesmo cache do dia. Um clique é uma consulta que vale, no máximo
# (`ComModelo` com `uma_consulta`). Acabadas as grátis, só consulta quando a pessoa clica no botão com o preço
# (`confirmou_preco`); sem ele, a resposta é `confirmar_preco` e nada sai. A conferência roda fora da trava do saldo:
# na corrida (outro clique levou a última grátis), a consulta sem o clique nunca vai à fatura (`pode_cobrar`). A
# resposta do Premium leva o `premium` do card (o mesmo da lista), para o contador da tela se atualizar.
class Autonomia::FerramentasProntas::Experimente
  EXEMPLOS = {
    'cep' => { 'consulta' => 'endereco', 'campo' => 'cep' },
    'cnpj' => { 'consulta' => 'empresa', 'campo' => 'cnpj' },
    'cpf' => { 'consulta' => 'conferir', 'campo' => 'cpf' },
    'banco_central' => { 'consulta' => 'dolar' },
    'ddd' => { 'consulta' => 'ddd', 'campo' => 'ddd' },
    'localizacao' => { 'consulta' => 'cidade', 'campos' => %w[latitude longitude] },
    'bancos' => { 'consulta' => 'banco', 'campo' => 'codigo', 'senao' => { 'consulta' => 'por_nome', 'campo' => 'nome' } }
  }.freeze
  COM_TEXTO_LIVRE = %w[fipe cidades feriados hospitais procedimentos doencas ncm compras_governo estacoes chuva corretor_susep
                       planos_de_saude aeronaves geracao_solar transportadoras queimadas].freeze
  MAX_VALOR = 100

  def initialize(account:, fonte:, valor:, confirmou_preco: false)
    @account = account
    @fonte = Autonomia::FerramentasProntas::Catalogo.buscar(fonte)
    @valor = valor.to_s.strip.first(MAX_VALOR)
    @confirmou_preco = confirmou_preco == true
  end

  # -> o que o agente receberia, sem os textos de orientação ao modelo: { 'situacao', 'dados'? }.
  def call
    return { 'situacao' => 'desligada' } unless Autonomia::FerramentasProntas.na_vitrine?(@account, @fonte)
    return premium if @fonte.premium?

    Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: @account.id, fonte: @fonte.chave)
    return ComModelo.new(account: @account, fonte: @fonte, valor: @valor).call if COM_TEXTO_LIVRE.include?(@fonte.chave)

    resposta = JSON.parse(Autonomia::FerramentasProntas::Execucao.new(tool: ferramenta, params: argumentos).call)
    resposta.slice('situacao', 'dados')
  end

  private

  def premium
    return com_contador('situacao' => 'confirmar_preco') if sem_gratis? && !@confirmou_preco

    Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: @account.id, fonte: @fonte.chave)
    com_contador(ComModelo.new(account: @account, fonte: @fonte, valor: @valor, uma_consulta: true, pode_cobrar: @confirmou_preco).call)
  end

  def contador
    Autonomia::FerramentasProntas::Premium.para_tela(@account, [@fonte]).fetch(@fonte.chave)
  end

  def com_contador(resultado)
    resultado.merge('premium' => contador)
  end

  def sem_gratis?
    contador['restantes'].zero?
  end

  def ferramenta
    Autonomia::Agents::Tool.new(account: @account, fonte_pronta: @fonte.chave)
  end

  def serve?(exemplo)
    @fonte.consulta(exemplo['consulta']).parametro(exemplo['campo']).normalizar(@valor).present?
  end

  def argumentos
    exemplo = EXEMPLOS.fetch(@fonte.chave, {})
    exemplo = exemplo['senao'] if exemplo['senao'] && !serve?(exemplo)
    base = { 'consulta' => exemplo['consulta'] }.merge(exemplo.fetch('fixos', {}))
    return base.merge(exemplo['campo'] => @valor) if exemplo['campo']
    return base unless exemplo['campos']

    base.merge(exemplo['campos'].zip(@valor.split(',').map(&:strip)).to_h)
  end
end
