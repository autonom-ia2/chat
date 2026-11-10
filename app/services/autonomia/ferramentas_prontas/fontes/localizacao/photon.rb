# A localização no Photon (principal, OpenStreetMap). O município vem em `city` (ou `county`, fora da sede).
class Autonomia::FerramentasProntas::Fontes::Localizacao::Photon < Autonomia::FerramentasProntas::Provedor
  NOME = 'photon'.freeze
  HOST = 'photon.komoot.io'.freeze

  def consultar(_consulta, params)
    dado = objeto!(get("/reverse?lat=#{params.fetch('latitude')}&lon=#{params.fetch('longitude')}&lang=default&limit=1"))
    lugar = lista!(dado['features']).first
    raise NaoEncontrado if lugar.nil?

    propriedades = objeto!(objeto!(lugar)['properties'])
    raise NaoEncontrado unless propriedades['countrycode'].to_s.casecmp?('BR')

    uf = Autonomia::FerramentasProntas::Ufs.sigla_pelo_nome(propriedades['state'])
    Autonomia::FerramentasProntas::Fontes::Localizacao.cidade(texto(propriedades['city']) || texto(propriedades['county']), uf)
  end
end
