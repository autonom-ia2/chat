# O gatilho de card que um evento do emissor do CRM dispara, na consulta do gate (Escuta.assinante?): o parâmetro que o
# evento traz e o pedaço de SQL que casa a receita com ele. Saiu da Escuta para ela caber no tamanho.
module Autonomia::Automacao::GatilhoDoEvento
  module_function

  # "tipo = X AND (parâmetro vazio OR parâmetro = valor do evento)", com os valores escapados.
  def casa_sql(tipo, mudou)
    nome, valor = parametro(tipo, mudou)
    gatilho = "autonomia_automacao_versoes.receita -> 'gatilho'"
    return ::Autonomia::Automacao::Definicao.sanitize_sql_array(["(#{gatilho} ->> 'tipo' = ?)", tipo]) if valor.nil?

    ::Autonomia::Automacao::Definicao.sanitize_sql_array(
      ["(#{gatilho} ->> 'tipo' = ? AND (#{gatilho} ->> ? IS NULL OR #{gatilho} ->> ? = ?))", tipo, nome, nome, valor.to_s]
    )
  end

  # O parâmetro do gatilho e o valor que o evento traz, sem reler o card. O atualizado (G27) não filtra aqui: o job
  # confere a mudança.
  def parametro(tipo, mudou)
    case tipo
    when ::Autonomia::Automacao::Gatilhos::ATUALIZADO then [nil, nil]
    when 'card.entrou_na_etapa' then ['etapa_id', mudou[:to_stage_id] || mudou[:stage_id]]
    when 'card.saiu_da_etapa' then ['etapa_id', mudou[:from_stage_id]]
    else ['funil_id', mudou[:pipeline_id]]
    end
  end
end
