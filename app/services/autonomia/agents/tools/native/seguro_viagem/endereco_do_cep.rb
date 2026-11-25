# O ENDEREÇO PELO CEP, DO LADO DO SERVIDOR (#3211): o endereço do segurado para a proposta nunca vem do modelo. Sai da
# ferramenta pronta de CEP do agente (ViaCEP, AwesomeAPI, BrasilAPI): lê o cache da fonte e, vazio, roda a pronta uma
# vez e lê o cache de novo.
#
# CEP de cidade com CEP único vem sem `logradouro` e sem `bairro` (R17): o hash devolvido só leva as chaves que existem,
# e quem lê (a `Compra`) aceita a ausência. CEP que não é de 8 dígitos, não achado ou sem a pronta no agente: nil.
module Autonomia::Agents::Tools::Native::SeguroViagem::EnderecoDoCep
  Cep = Autonomia::FerramentasProntas::Fontes::Cep
  CHAVES = %w[logradouro bairro cidade uf cep].freeze
  DIGITOS_DO_CEP = 8

  module_function

  # -> Hash com 'logradouro', 'bairro', 'cidade', 'uf', 'cep' (as que existem) ou nil.
  def buscar(agent:, cep:)
    params, falta = consulta.conferir({ 'cep' => so_digitos(cep) })
    return nil if falta

    cache = Autonomia::FerramentasProntas::Cache.new(Cep::FONTE, consulta, params)
    guardado = cache.ler || executar_e_reler(agent, params, cache)
    return nil unless guardado.is_a?(Hash) && guardado['situacao'] == Autonomia::FerramentasProntas::Cache::ENCONTRADO

    guardado['dados'].to_h.slice(*CHAVES).compact_blank.presence
  end

  def consulta
    Cep::FONTE.consulta('endereco')
  end

  # Só os dígitos, sem regex; fora de 8 dígitos vai vazio e a consulta recusa.
  def so_digitos(cep)
    digitos = cep.to_s.each_char.select { |caractere| caractere.between?('0', '9') }.join
    digitos.length == DIGITOS_DO_CEP ? digitos : ''
  end

  def executar_e_reler(agent, params, cache)
    pronta = agent.tools.find_by(fonte_pronta: 'cep')
    return nil if pronta.nil?

    Autonomia::FerramentasProntas::Execucao.new(tool: pronta, params: { 'consulta' => 'endereco' }.merge(params)).call
    cache.ler
  end
end
