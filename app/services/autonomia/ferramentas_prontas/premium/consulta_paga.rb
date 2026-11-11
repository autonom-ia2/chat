# UMA CONSULTA DE UM CARD PREMIUM (#2858, F7): uma consulta do catálogo que é um dataset da BigDataCorp. Uma fonte só,
# sem reserva (`BigDataCorp`), e o prazo do dataset. A validade de 1 dia é só a marca de que passa pelo cache: o
# `Premium::Cache` guarda até o fim do dia da conta.
# `pelo_endereco: true` (regra "QI 70"): sem o CEP, ele vem da cidade, ou da rua e da cidade (`Premium::Endereco.cep`). A
# UF é opcional: sai da cidade (`Municipios`); a cidade homônima sem UF é recusada na `uf`, com as candidatas, e a que
# não existe, na `cidade`. O bairro e o número escolhem entre os CEPs da rua (`Fontes::Cep::Referencia.cep`). Sem CEP
# achado, o pedido é inválido no `cep`; com mais de um CEP sobrando, no que falta (o `bairro`, se ele não veio e os CEPs
# estão em bairros diferentes; senão o `numero`), com os CEPs em `candidatos`. A recusa é uma `Falta`, como nas grátis.
# `exige_rua: true` (empresas na região): o dado é da região do CEP, e o CEP geral da cidade daria a conta de outra
# região. Sem o CEP, só a cidade não serve: pede a rua.
class Autonomia::FerramentasProntas::Premium::ConsultaPaga < Autonomia::FerramentasProntas::Consulta
  Falta = Autonomia::FerramentasProntas::Falta
  FOLGA = 2

  attr_reader :dataset

  SEM_RUA = 'a rua do endereço (e o bairro e o número, se souber): a contagem é da região do CEP, não da cidade inteira, ' \
            'e o CEP geral da cidade não serve'.freeze

  def initialize(nome:, descricao:, dataset:, obrigatorios:, opcionais: [], pelo_endereco: false, exige_rua: false) # rubocop:disable Metrics/ParameterLists
    @dataset = dataset
    @pelo_endereco = pelo_endereco
    @exige_rua = exige_rua
    super(nome: nome, descricao: descricao, obrigatorios: obrigatorios, opcionais: opcionais,
          provedores: [Autonomia::FerramentasProntas::Premium::BigDataCorp], validade: 1.day, prazo_por_fonte: dataset.prazo,
          prazo_total: dataset.prazo + FOLGA)
  end

  # `conta`: o id da conta, que segue para a procura do CEP (a fatia da conta no teto do ViaCEP).
  def conferir(argumentos, conta = nil)
    params, falta = super(argumentos)
    return [params, falta] unless params && @pelo_endereco && params['cep'].nil?

    com_cep(params, conta)
  end

  def paga?
    true
  end

  private

  def com_cep(params, conta)
    falta = falta_antes_de_procurar(params)
    return [nil, falta] if falta

    achado = Autonomia::FerramentasProntas::Premium::Endereco.cep(cidade: params['cidade'], uf: params['uf']&.upcase, rua: params['rua'],
                                                                  bairro: params['bairro'], numero: params['numero'], conta: conta)
    achado&.dig('cep') ? [params.merge('cep' => achado['cep']), nil] : [nil, falta_do_endereco(achado)]
  end

  # Sem a cidade: o CEP. Empresas na região sem a rua: a rua. A cidade homônima sem UF ou que não existe (`Municipios`).
  def falta_antes_de_procurar(params)
    return Falta.new(campo: 'cep') if params['cidade'].nil?
    return Falta.new(campo: 'rua', orientacao: Autonomia::FerramentasProntas::Resposta.pergunte('rua', SEM_RUA)) if @exige_rua && params['rua'].nil?

    Autonomia::FerramentasProntas::Municipios.falta(params['uf'], params['cidade'])
  end

  # Vários CEPs: o que falta para escolher (o bairro ou o número), com os CEPs em `candidatos`. Nenhum: o CEP.
  def falta_do_endereco(achado)
    return Falta.new(campo: 'cep') unless achado&.key?('candidatos')

    Falta.new(campo: achado['falta'] || 'bairro', candidatos: achado['candidatos'])
  end
end
