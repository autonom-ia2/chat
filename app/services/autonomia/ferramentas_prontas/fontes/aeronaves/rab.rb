# A aeronave no RAB baixado (#2858, F5): a linha da matrícula (a ANAC repete algumas; vão todas, no máximo `MAXIMO`).
class Autonomia::FerramentasProntas::Fontes::Aeronaves::Rab < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'rab'.freeze
  BASE = 'aeronaves'.freeze
  MAXIMO = 5

  def consultar(_consulta, params)
    exigir_base!
    escopo = Autonomia::FerramentasProntas::Bases::Aeronave.vigente.where(matricula: params.fetch('matricula')).order(:id)
    com_data(listar(escopo, 'aeronaves', MAXIMO) { |item| { 'matricula' => item.matricula }.merge(item.dados) })
  end
end
