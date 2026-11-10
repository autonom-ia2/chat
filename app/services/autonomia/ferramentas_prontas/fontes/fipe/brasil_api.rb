# A FIPE na BrasilAPI (principal): as marcas, e o preço só pelo código FIPE (ela não tem a lista de modelos).
class Autonomia::FerramentasProntas::Fontes::Fipe::BrasilApi < Autonomia::FerramentasProntas::Provedor
  Fipe = Autonomia::FerramentasProntas::Fontes::Fipe

  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def self.aplica?(consulta, params)
    consulta.nome == 'marcas' || (consulta.nome == 'preco' && params['codigo_fipe'].present?)
  end

  def consultar(consulta, params)
    consulta.nome == 'marcas' ? marcas(params) : precos(params)
  end

  private

  def marcas(params)
    itens = lista!(get("/api/fipe/marcas/v1/#{params['tipo']}")).filter_map do |item|
      { 'codigo' => texto(item['valor']), 'nome' => texto(item['nome']) } if item.is_a?(Hash) && item['valor'].present?
    end
    Fipe.lista(exigir!(itens), 'marcas', Fipe::MAX_MARCAS)
  end

  def precos(params)
    itens = lista!(get("/api/fipe/preco/v1/#{params['codigo_fipe']}")).select { |item| item.is_a?(Hash) }
    itens = itens.select { |item| item['anoModelo'].to_i == params['ano'] } if params['ano']
    raise NaoEncontrado if itens.empty?

    { 'precos' => itens.first(Fipe::MAX_PRECOS).map { |item| preco_de(item) } }
  end

  def preco_de(item)
    Fipe.preco(valor: item['valor'], marca: item['marca'], modelo: item['modelo'], ano_modelo: item['anoModelo'],
               combustivel: item['combustivel'], codigo_fipe: item['codigoFipe'], mes_de_referencia: item['mesReferencia'])
  end
end
