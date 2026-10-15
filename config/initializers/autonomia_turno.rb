# "Um turno, uma ordem" (#1606, ponto 2): quando o dono da conversa muda (Sync do CRM ou PassarParaIa), o turno que
# ainda está em andamento é refeito pelo dono novo. O evento sai depois do commit de quem trocou. Assinado uma vez, no
# boot; as constantes são lidas na hora do evento, então o recarregamento do desenvolvimento não duplica o assinante.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe('crm.ai.responsible_agent_changed') do |*, payload|
    Autonomia::Agents::Operate::ReenfileirarTurno.ao_trocar_dono(payload)
  end
end
