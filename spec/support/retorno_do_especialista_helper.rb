# O QUE O MODELO DUBLADO DO ESPECIALISTA DEVOLVE (item 9 da auditoria de voz, 26/09/2026). O de cotação responde no
# schema de fatos (`Insurance::QuoteAgent::RetornoDoEspecialista::SCHEMA`); os outros, na prosa
# (`Specialists::Runner::RESULT_SCHEMA`). O dublê olha o schema que o `Runner` pediu, como o modelo real em `strict`.
module RetornoDoEspecialistaHelper
  FATOS_VAZIOS = { 'o_que_fez' => '', 'resultado_lido' => '', 'pedido_que_entrou' => [], 'pedido_que_nao_coube' => [],
                   'falta_perguntar' => [], 'contexto_da_pessoa' => [] }.freeze

  # -> o JSON dos fatos, com as partes dadas e o resto vazio.
  def fatos_do_especialista(**partes)
    FATOS_VAZIOS.merge(partes.stringify_keys).to_json
  end

  # -> o texto que o modelo dublado devolve no `schema` pedido: a prosa com as pendências, ou os mesmos fatos nas partes.
  def resposta_do_especialista(schema, resposta:, faltando: [], lido: '')
    if schema.to_h[:name] == Autonomia::Agents::Specialists::Runner::RESULT_SCHEMA[:name]
      return { resposta: [resposta, lido].compact_blank.join("\n"), dados_faltando: faltando }.to_json
    end

    fatos_do_especialista(o_que_fez: resposta, resultado_lido: lido,
                          falta_perguntar: faltando.map { |dado| { 'dado' => dado, 'por_que' => '' } })
  end

  # -> a chamada ao modelo é a de um especialista (qualquer dos dois schemas)?
  def schema_do_especialista?(schema)
    [Autonomia::Agents::Specialists::Runner::RESULT_SCHEMA[:name],
     Autonomia::Insurance::QuoteAgent::RetornoDoEspecialista::SCHEMA[:name]].include?(schema.to_h[:name])
  end
end

RSpec.configure do |config|
  config.include RetornoDoEspecialistaHelper
end
