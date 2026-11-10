# Os feriados do ano na Nager.Date (reserva): só os de alcance nacional (`global`); os estaduais ficam de fora.
class Autonomia::FerramentasProntas::Fontes::Feriados::Nager < Autonomia::FerramentasProntas::Provedor
  NOME = 'nager'.freeze
  HOST = 'date.nager.at'.freeze

  def consultar(consulta, params)
    Autonomia::FerramentasProntas::Fontes::Feriados.responder(consulta, params) { |ano| do_ano(ano) }
  end

  private

  def do_ano(ano)
    nacionais = lista!(get("/api/v3/PublicHolidays/#{ano.to_i}/BR")).select { |item| objeto!(item)['global'] == true }
    exigir!(nacionais.map { |item| { 'data' => exigir!(texto(item['date'])), 'nome' => exigir!(texto(item['localName'])) } })
  end
end
