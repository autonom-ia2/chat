# `null` quando ainda não existe — é assim que a tela sabe se oferece criar ou abrir.
if @agent
  json.payload do
    json.id @agent.id
    json.name @agent.name
    json.agent_type @agent.agent_type
    json.enabled @agent.enabled
    # Os ramos que este agente sabe cotar. Um agente sem especialista responderia sobre seguro e não
    # cotaria — a tela precisa poder mostrar isso. Só os que atendem nesta conta: residencial existe em todo
    # agente, mas só cota onde a conexão tem o ramo (`Builder.disponivel?`).
    disponiveis = @agent.specialists.enabled.order(:id).select { |s| Autonomia::Insurance::QuoteAgent::Builder.disponivel?(s) }
    json.specialists(disponiveis.map { |s| { slug: s.slug, name: s.name } })
  end
else
  json.payload nil
end
