# UMA CONSULTA DE UM CARD PREMIUM (#2858, F7): uma consulta do catálogo que é um dataset da BigDataCorp. Uma fonte só,
# sem reserva (`BigDataCorp`), e o prazo do dataset. A validade de 1 dia é só a marca de que passa pelo cache: o
# `Premium::Cache` guarda até o fim do dia da conta.
# `pelo_endereco: true` (regra "QI 70"): sem o CEP, ele vem da cidade e da UF, ou da rua (`Premium::Endereco.cep`). Sem
# CEP achado, o pedido é inválido no `cep`; com mais de um CEP para a rua, no `bairro` (o agente pergunta o bairro).
class Autonomia::FerramentasProntas::Premium::ConsultaPaga < Autonomia::FerramentasProntas::Consulta
  FOLGA = 2

  attr_reader :dataset

  def initialize(nome:, descricao:, dataset:, obrigatorios:, opcionais: [], pelo_endereco: false) # rubocop:disable Metrics/ParameterLists
    @dataset = dataset
    @pelo_endereco = pelo_endereco
    super(nome: nome, descricao: descricao, obrigatorios: obrigatorios, opcionais: opcionais,
          provedores: [Autonomia::FerramentasProntas::Premium::BigDataCorp], validade: 1.day, prazo_por_fonte: dataset.prazo,
          prazo_total: dataset.prazo + FOLGA)
  end

  # `conta`: o id da conta, que segue para a procura do CEP (a fatia da conta no teto do ViaCEP).
  def conferir(argumentos, conta: nil)
    params, campo = super(argumentos)
    return [params, campo] unless params && @pelo_endereco && params['cep'].nil?

    com_cep(params, conta)
  end

  def paga?
    true
  end

  private

  def com_cep(params, conta)
    return [nil, 'cep'] if params['cidade'].nil? || params['uf'].nil?

    achado = Autonomia::FerramentasProntas::Premium::Endereco.cep(cidade: params['cidade'], uf: params['uf'].upcase, rua: params['rua'],
                                                                  bairro: params['bairro'], conta: conta)
    return [params.merge('cep' => achado['cep']), nil] if achado&.dig('cep')

    [nil, achado&.key?('candidatos') ? 'bairro' : 'cep']
  end
end
