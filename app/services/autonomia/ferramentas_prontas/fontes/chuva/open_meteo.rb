# A soma diária de chuva no arquivo histórico do Open-Meteo (fonte única). Período fora do que a fonte tem: 400, que
# vira falha ("não consegui"); a regra da consulta já barra o futuro antes de sair.
class Autonomia::FerramentasProntas::Fontes::Chuva::OpenMeteo < Autonomia::FerramentasProntas::Provedor
  NOME = 'openmeteo'.freeze
  HOST = 'archive-api.open-meteo.com'.freeze

  def consultar(_consulta, params)
    chuva = Autonomia::FerramentasProntas::Fontes::Chuva
    latitude, longitude, rotulo = exigir!(chuva.ponto(params))
    diario = objeto!(objeto!(get(caminho(latitude, longitude, params)))['daily'])
    dias = lista!(diario['time'])
    valores = lista!(diario['precipitation_sum'])
    raise Falha, 'resposta_invalida' unless dias.size == valores.size && dias.all?(String)

    chuva.resposta(rotulo, dias, valores) || raise(NaoEncontrado)
  end

  private

  def caminho(latitude, longitude, params)
    casas = Autonomia::FerramentasProntas::Fontes::Chuva::CASAS
    "/v1/archive?latitude=#{format("%.#{casas}f", latitude)}&longitude=#{format("%.#{casas}f", longitude)}" \
      "&start_date=#{params.fetch('de')}&end_date=#{params['ate'] || params.fetch('de')}&daily=precipitation_sum&timezone=auto"
  end
end
