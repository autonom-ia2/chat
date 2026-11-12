json.partial! 'api/v1/accounts/autonomia/agents/agent', agent: @agent
# #2881 — o modelo pronto de ramo de que este agente nasceu, como a tela o mostra (listas do dono, ferramentas com a
# frase "Use quando", cartões pagos sugeridos, perguntas de teste). Só aqui, não na listagem. Não vem para o agente que
# não nasceu de um modelo, para a conta sem o pacote `seguros` ou sem a flag, nem para a Lia. O roteiro não sai daqui.
# Só enquanto o agente é rascunho: depois do "Começar" as listas já não mudam por aqui. Nem no modo manual.
modelo_pronto = Autonomia::Agents::ModelosDeRamo::Rascunho.do_agente(@agent) if @agent.draft? && !@agent.manual?
json.modelo_pronto modelo_pronto.para_tela if modelo_pronto
# #1428 (parte 3, piloto) — a última mudança feita conversando que ainda dá para desfazer (a faixa da tela "Mudar
# conversando", mesmo depois de recarregar). Só aqui, não na listagem: uma consulta por agente. Só a conversa e os
# resumos do que entrou; nunca o campo, a instrução ou o andaime. Fora do piloto (ou já sem Desfazer), não vem.
ultima_mudanca = Autonomia::Agents::ResultadoDoAjuste.ultima_mudanca_desfazivel(@agent)
json.ultima_mudanca_desfazivel ultima_mudanca if ultima_mudanca
# #1430: quantas ferramentas estão ligadas, para quem vê o agente sem a chave de ferramentas. Só o número: endereço,
# cabeçalho e nome ficam na API de ferramentas. #2858: a pronta conta só quando entra no turno (flag ligada, fora da Lia).
json.ferramentas_ligadas(@agent.tools.enabled.count { |tool| Autonomia::FerramentasProntas.no_turno?(tool, @agent) })
