# Cadastros públicos gratuitos de CNPJ (porte de registry/* do Orth, #679): OpenCNPJ, BrasilAPI, CNPJ.ws e CNPJá, nessa
# ordem. A primeira fonte que responde com cadastro válido ganha; fonte fora do ar, recusada ou inválida cai para a
# próxima. Não grava nada no banco e não usa credencial nenhuma: só lê.
#
# Registry.fetch(cnpj) devolve Registry::Company ou Registry::Failure (as duas respondem failed?).
module Autonomia::Prospecting::Research::Registry
  Provider = Data.define(:name, :host, :path, :parser) do
    def url(cnpj) = "https://#{host}#{path}#{cnpj}"
  end

  PROVIDERS = [
    Provider.new(name: 'OpenCNPJ', host: 'api.opencnpj.org', path: '/', parser: OpenCnpjParser),
    Provider.new(name: 'BrasilAPI', host: 'brasilapi.com.br', path: '/api/cnpj/v1/', parser: BrasilApiParser),
    Provider.new(name: 'CNPJ.ws', host: 'publica.cnpj.ws', path: '/cnpj/', parser: CnpjWsParser),
    Provider.new(name: 'CNPJá', host: 'open.cnpja.com', path: '/office/', parser: CnpjaParser)
  ].freeze

  module_function

  def fetch(cnpj, hydrator: Hydrator.new)
    digits = Autonomia::Prospecting::Research::Normalization.digits(cnpj)
    return Failure.new(cnpj: digits, reason: :invalid_cnpj, attempts: []) unless digits.length == 14

    hydrator.hydrate([digits]).first.result
  end

  # Endereço público da consulta, gravado como fonte do dado.
  def source_url(provider_name, cnpj)
    PROVIDERS.find { |provider| provider.name == provider_name }.url(cnpj)
  end
end
