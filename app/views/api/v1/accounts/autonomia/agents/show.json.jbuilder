json.partial! 'api/v1/accounts/autonomia/agents/agent', agent: @agent
# #1428 (parte 3, piloto) — a última mudança feita conversando que ainda dá para desfazer (a faixa da tela "Mudar
# conversando", mesmo depois de recarregar). Só aqui, não na listagem: uma consulta por agente. Só a conversa e os
# resumos do que entrou; nunca o campo, a instrução ou o andaime. Fora do piloto (ou já sem Desfazer), não vem.
ultima_mudanca = Autonomia::Agents::ResultadoDoAjuste.ultima_mudanca_desfazivel(@agent)
json.ultima_mudanca_desfazivel ultima_mudanca if ultima_mudanca
