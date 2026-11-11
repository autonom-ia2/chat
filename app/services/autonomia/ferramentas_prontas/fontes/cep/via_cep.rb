# O CEP no ViaCEP: a reserva do endereço pelo CEP e a única fonte do CEP pela rua. CEP que não existe: 200 com
# `{"erro": true}` (ou "true"). Rua que não existe: lista vazia.
class Autonomia::FerramentasProntas::Fontes::Cep::ViaCep < Autonomia::FerramentasProntas::Provedor
  NOME = 'viacep'.freeze
  HOST = 'viacep.com.br'.freeze

  def consultar(consulta, params)
    return por_endereco(params) if consulta.nome == 'por_endereco'

    dado = objeto!(get("/ws/#{params['cep']}/json/"))
    raise NaoEncontrado if dado.key?('erro')

    Autonomia::FerramentasProntas::Fontes::Cep.enxuto(
      cep: params['cep'], logradouro: texto(dado['logradouro']), bairro: texto(dado['bairro']),
      cidade: exigir!(texto(dado['localidade'])), uf: exigir!(texto(dado['uf']))
    )
  end

  # -> os CEPs da `rua` no município, só os da própria cidade (pelo código IBGE que o ViaCEP devolve em cada um):
  # [{ 'cep', 'logradouro', 'complemento', 'bairro' }]. O ViaCEP pede o nome sem acento; a resposta tem até 50.
  def ceps_da_rua(municipio, rua)
    caminho = "/ws/#{municipio.uf}/#{codificar(sem_acento(municipio.nome))}/#{codificar(sem_acento(rua))}/json/"
    lista!(get(caminho)).filter_map do |item|
      next unless item.is_a?(Hash) && item['ibge'].to_s == municipio.codigo && item['cep'].present?

      { 'cep' => texto(item['cep']), 'logradouro' => texto(item['logradouro']), 'complemento' => texto(item['complemento']),
        'bairro' => texto(item['bairro']) }.compact
    end
  end

  private

  def por_endereco(params)
    cep = Autonomia::FerramentasProntas::Fontes::Cep
    municipio = cep::Municipios.buscar(params['uf'], params.fetch('cidade')) || raise(Falha, 'municipio_desconhecido')
    ceps = ceps_da_rua(municipio, params.fetch('logradouro'))
    raise NaoEncontrado if ceps.empty?

    cep.lista(municipio, params['logradouro'], ceps)
  end

  def sem_acento(texto)
    I18n.transliterate(texto.to_s).squish
  end
end
