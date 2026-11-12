# O banco na BrasilAPI (principal): um pelo código, ou a lista inteira (para a busca pelo nome).
class Autonomia::FerramentasProntas::Fontes::Bancos::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(consulta, params)
    return todos if consulta.nome == 'por_nome'

    codigo = params.fetch('codigo')
    dado = objeto!(get("/api/banks/v1/#{codigo.to_i}"))
    Autonomia::FerramentasProntas::Fontes::Bancos.banco(
      codigo: codigo, nome: exigir!(texto(dado['name'])), nome_completo: texto(dado['fullName']), ispb: texto(dado['ispb'])
    )
  end

  private

  # Só os que têm código de compensação (os outros não servem a boleto nem transferência por código).
  def todos
    bancos = Autonomia::FerramentasProntas::Fontes::Bancos
    itens = lista!(get('/api/banks/v1')).filter_map do |dado|
      codigo = dado.is_a?(Hash) && bancos.codigo(dado['code'])
      next unless codigo && texto(dado['name'])

      bancos.banco(codigo: codigo, nome: texto(dado['name']), nome_completo: texto(dado['fullName']), ispb: texto(dado['ispb']))
    end
    { 'bancos' => exigir!(itens) }
  end
end
