# O "EXPERIMENTE" DA VITRINE (#2858, F2): a pessoa testa a fonte antes de ensinar ao agente, com um valor só (o CEP, o
# CNPJ, o DDD...), e vê o que o agente receberia. Roda a mesma `Execucao` do atendimento, numa ferramenta que não é
# salva: o mesmo catálogo, reserva, cache e motivo de falha, e a consulta CONTA no limite do dia da conta naquela
# fonte — é o freio contra quem usasse o botão como consulta grátis sem fim.
#
# O acesso da conta na fonte (`Acesso`, a chave interna) nasce aqui se ainda não existe: a `Execucao` exige um. Quem
# incluiu fica gravado no primeiro "Incluir".
#
# `EXEMPLOS`: a consulta de cada fonte e em qual parâmetro entra o valor digitado. Fonte sem campo (o Banco Central)
# responde a cotação do dólar. A localização recebe "latitude, longitude" num campo só.
#
# `COM_TEXTO_LIVRE`: a fonte em que a pessoa escreve como falaria ("Onix 2020", "Ribeirão Preto", "dias úteis até
# 30/11"). Quem entende o texto é o modelo, pela IA da conta (`Experimente::ComModelo`), como o agente faria.
class Autonomia::FerramentasProntas::Experimente
  EXEMPLOS = {
    'cep' => { 'consulta' => 'endereco', 'campo' => 'cep' },
    'cnpj' => { 'consulta' => 'empresa', 'campo' => 'cnpj' },
    'cpf' => { 'consulta' => 'conferir', 'campo' => 'cpf' },
    'banco_central' => { 'consulta' => 'dolar' },
    'ddd' => { 'consulta' => 'ddd', 'campo' => 'ddd' },
    'localizacao' => { 'consulta' => 'cidade', 'campos' => %w[latitude longitude] },
    'bancos' => { 'consulta' => 'banco', 'campo' => 'codigo' }
  }.freeze
  COM_TEXTO_LIVRE = %w[fipe cidades feriados hospitais procedimentos doencas ncm compras_governo estacoes chuva produtos_seguradoras
                       corretor_susep planos_de_saude aeronaves geracao_solar transportadoras queimadas].freeze
  MAX_VALOR = 100

  def initialize(account:, fonte:, valor:)
    @account = account
    @fonte = Autonomia::FerramentasProntas::Catalogo.buscar(fonte)
    @valor = valor.to_s.strip.first(MAX_VALOR)
  end

  # -> o que o agente receberia, sem os textos de orientação ao modelo: { 'situacao', 'dados'? }.
  def call
    return { 'situacao' => 'desligada' } unless Autonomia::FerramentasProntas.disponivel?(@account, @fonte)

    Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: @account.id, fonte: @fonte.chave)
    return ComModelo.new(account: @account, fonte: @fonte, valor: @valor).call if COM_TEXTO_LIVRE.include?(@fonte.chave)

    resposta = JSON.parse(Autonomia::FerramentasProntas::Execucao.new(tool: ferramenta, params: argumentos).call)
    resposta.slice('situacao', 'dados')
  end

  private

  def ferramenta
    Autonomia::Agents::Tool.new(account: @account, fonte_pronta: @fonte.chave)
  end

  def argumentos
    exemplo = EXEMPLOS.fetch(@fonte.chave, {})
    base = { 'consulta' => exemplo['consulta'] }.merge(exemplo.fetch('fixos', {}))
    return base.merge(exemplo['campo'] => @valor) if exemplo['campo']
    return base unless exemplo['campos']

    base.merge(exemplo['campos'].zip(@valor.split(',').map(&:strip)).to_h)
  end
end
