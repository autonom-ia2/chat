# O plano de numeração (reserva, sem rede): o estado de cada DDD em uso no Brasil (Anatel). O 61 é o Distrito Federal
# (também atende cidades de Goiás vizinhas; a reserva diz só o estado-sede).
class Autonomia::FerramentasProntas::Fontes::Ddd::Plano < Autonomia::FerramentasProntas::Provedor
  NOME = 'plano'.freeze
  HOST = nil
  # Resposta incompleta (só o estado): não vai ao cache, para a BrasilAPI dar as cidades quando voltar.
  VALIDADE = 0
  ESTADOS = {
    'SP' => %w[11 12 13 14 15 16 17 18 19], 'RJ' => %w[21 22 24], 'ES' => %w[27 28], 'MG' => %w[31 32 33 34 35 37 38],
    'PR' => %w[41 42 43 44 45 46], 'SC' => %w[47 48 49], 'RS' => %w[51 53 54 55], 'DF' => %w[61], 'GO' => %w[62 64],
    'TO' => %w[63], 'MT' => %w[65 66], 'MS' => %w[67], 'AC' => %w[68], 'RO' => %w[69], 'BA' => %w[71 73 74 75 77],
    'SE' => %w[79], 'PE' => %w[81 87], 'AL' => %w[82], 'PB' => %w[83], 'RN' => %w[84], 'CE' => %w[85 88],
    'PI' => %w[86 89], 'PA' => %w[91 93 94], 'AM' => %w[92 97], 'RR' => %w[95], 'AP' => %w[96], 'MA' => %w[98 99]
  }.flat_map { |uf, ddds| ddds.map { |ddd| [ddd, uf] } }.to_h.freeze

  def consultar(_consulta, params)
    ddd = params.fetch('ddd')
    Autonomia::FerramentasProntas::Fontes::Ddd.resposta(ddd, ESTADOS.fetch(ddd))
  end
end
