# A localização no Photon (principal, OpenStreetMap). O município vem em `city` (ou em `county`, fora da sede). O nome
# só vale se for um município daquele estado na tabela das sedes (o nome no OpenStreetMap é editável por qualquer um,
# e um nome que não confere não vai ao modelo): senão, falha, e a reserva responde.
class Autonomia::FerramentasProntas::Fontes::Localizacao::Photon < Autonomia::FerramentasProntas::Provedor
  NOME = 'photon'.freeze
  HOST = 'photon.komoot.io'.freeze

  def consultar(_consulta, params)
    dado = objeto!(get("/reverse?lat=#{params.fetch('latitude')}&lon=#{params.fetch('longitude')}&lang=default&limit=1"))
    lugar = lista!(dado['features']).first
    sem_lugar!(params) if lugar.nil?

    propriedades = objeto!(objeto!(lugar)['properties'])
    pais = exigir!(texto(propriedades['countrycode']))
    raise NaoEncontrado unless pais.casecmp?('BR')

    uf = exigir!(Autonomia::FerramentasProntas::Ufs.sigla_pelo_nome(propriedades['state']))
    Autonomia::FerramentasProntas::Fontes::Localizacao.cidade(municipio(uf, propriedades), uf)
  end

  private

  # Nenhum lugar no ponto: longe de toda sede de município (o mar, 0,0), não há cidade ali e a fonte respondeu "não tem"
  # (varredura F16); perto de uma, falha, e a sede mais próxima responde.
  def sem_lugar!(params)
    sedes = Autonomia::FerramentasProntas::Fontes::Localizacao::Sedes
    _sede, km = sedes.mais_proxima(params.fetch('latitude'), params.fetch('longitude'))
    raise NaoEncontrado if km > sedes::MAX_KM

    raise Falha, 'sem_lugar'
  end

  def municipio(uf_sigla, propriedades)
    sedes = Autonomia::FerramentasProntas::Fontes::Localizacao::Sedes
    nome = %w[city county].lazy.filter_map { |campo| sedes.municipio(uf_sigla, propriedades[campo]) }.first
    nome || raise(Falha, 'municipio_nao_confere')
  end
end
