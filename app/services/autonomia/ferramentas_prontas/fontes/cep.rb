# ENDEREÇO PELO CEP (#2858): BrasilAPI, com o ViaCEP de reserva (`cep/brasil_api.rb`, `cep/via_cep.rb`). O endereço de
# um CEP muda pouco: 30 dias de cache. Termos: as duas são gratuitas e sem chave; o ViaCEP pede uso moderado e bloqueia
# por abuso, e o cache e o limite por conta são a moderação. Só o endereço vai ao agente (sem coordenada nem código de
# serviço).
module Autonomia::FerramentasProntas::Fontes::Cep
  # `campos`: cep (8 dígitos), logradouro, bairro, cidade, uf. O CEP volta formatado; o vazio sai.
  def self.enxuto(campos)
    cep = campos.fetch(:cep)
    campos.merge(cep: "#{cep[0, 5]}-#{cep[5, 3]}").transform_keys(&:to_s).compact
  end

  CEP = Autonomia::FerramentasProntas::Parametro.new(
    nome: 'cep', descricao: 'O CEP como o cliente escreveu (8 dígitos, com ou sem traço).',
    pergunte: 'o CEP, com 8 dígitos'
  ) { |valor| Autonomia::FerramentasProntas::Parametro.digitos(valor, 8) }

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'cep', slug: 'pronta_cep', nome: 'Endereço pelo CEP',
    descricao: 'Consulta oficial e gratuita do endereço de um CEP: rua, bairro, cidade e UF.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'endereco', descricao: 'o endereço do CEP', obrigatorios: [CEP], provedores: [BrasilApi, ViaCep],
        validade: 30.days, prazo_por_fonte: 3, prazo_total: 6
      )
    ],
    limite_diario: 500,
    termos: 'BrasilAPI e ViaCEP: gratuitas, sem chave; o ViaCEP bloqueia uso abusivo. Cache de 30 dias.'
  )
end
