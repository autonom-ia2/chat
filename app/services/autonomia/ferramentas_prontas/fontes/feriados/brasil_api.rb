# Os feriados nacionais do ano na BrasilAPI (principal).
class Autonomia::FerramentasProntas::Fontes::Feriados::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(consulta, params)
    Autonomia::FerramentasProntas::Fontes::Feriados.responder(consulta, params) { |ano| do_ano(ano) }
  end

  private

  def do_ano(ano)
    feriados = lista!(get("/api/feriados/v1/#{ano.to_i}")).map do |item|
      { 'data' => exigir!(texto(objeto!(item)['date'])), 'nome' => exigir!(texto(item['name'])) }
    end
    exigir!(feriados)
  end
end
