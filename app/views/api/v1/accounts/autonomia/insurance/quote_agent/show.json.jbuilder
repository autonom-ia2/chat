# `null` quando ainda não existe — é assim que a tela sabe se oferece criar ou abrir.
if @agent
  json.payload do
    json.id @agent.id
    json.name @agent.name
    json.agent_type @agent.agent_type
    json.enabled @agent.enabled
    # Os ramos que este agente sabe cotar. Um agente sem especialista responderia sobre seguro e não
    # cotaria — a tela precisa poder mostrar isso.
    json.specialists @agent.specialists.enabled.order(:id).map { |s| { slug: s.slug, name: s.name } }
  end
else
  json.payload nil
end
