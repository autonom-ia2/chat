# A CHAVE DA PROPOSTA DO SEGURO VIAGEM (#3211), fora de `GerarPropostaSeguroViagem` só pelo tamanho da classe (#3246b).
#
# A mesma cotação, o mesmo plano e o mesmo dado inteiro (viajantes já normalizados por `Viajantes`, com o contato e o
# endereço do titular como vieram, e o contato de emergência) são a mesma proposta. Os demais viajantes entram ordenados
# pelo CPF: a mesma gente em outra ordem é a mesma proposta. JSON canônico, chaves ordenadas. É um HMAC com uma chave
# derivada do segredo da aplicação, e não um hash que se reverte pelos CPFs possíveis: a proposta guardada não leva dado
# pessoal.
module Autonomia::Agents::Tools::Native::SeguroViagem::ChaveDaProposta
  # Separação de domínio: a chave do HMAC é derivada só para isto, nunca o `secret_key_base` cru.
  DOMINIO_DA_CHAVE = 'seguro_viagem/proposta'.freeze

  module_function

  def de(cotacao:, codigo:, viajantes:, contato:)
    titular, *demais = viajantes.map { |pessoa| pessoa.merge('nascimento' => pessoa['nascimento'].iso8601) }
    dado = { 'cotacao' => cotacao.id, 'plano' => codigo, 'titular' => titular,
             'demais_viajantes' => demais.sort_by { |pessoa| pessoa['cpf'] }, 'contato_de_emergencia' => contato }
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.key_generator.generate_key(DOMINIO_DA_CHAVE),
                            JSON.generate(canonico(dado)))
  end

  def canonico(valor)
    case valor
    when Hash then valor.sort_by { |nome, _| nome.to_s }.to_h { |nome, item| [nome.to_s, canonico(item)] }
    when Array then valor.map { |item| canonico(item) }
    else valor
    end
  end
end
