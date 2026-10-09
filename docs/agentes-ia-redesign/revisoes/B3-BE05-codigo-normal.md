# Revisão normal de código — B3/BE-05

**Alvo:** snapshot 23 em `/Users/Shared/maccluster-workspaces/chat2you/20261007-184308-532a5b7b-9803329751-205ae53c/src`  
**SHA:** `9803329751ae3fce6fd8cec442e77faa9170b38434587aac62a8e81438e480ad`  
**Fontes:** `design/B3.md`, `revisoes/B3-desenho-final.md`, PRD BE-05, RED/GREEN B3 e o código do snapshot.  
**Escopo:** reader/writer BE-05, API/store e integração do painel existente.  
**Método:** leitura estática; não executei testes, build, banco, navegador, serviços, rede ou produção.

## Resultado

**STOP — não aprovado nesta rodada.** Encontrei um bloqueio P1 concreto na integração da jornada real. O reader nested, o isolamento/permissionamento, a ordem de locks, o reset idempotente, as duas guardas de manual/Lia, o writer D22 e a ação de store `resume` estão coerentes no snapshot. Isso não compensa o fato de o consumidor real do botão de retomada ainda usar criação.

## Achado

### B3-BE05-COD-01 — painel existente não usa a retomada e cria outra thread (P1)

**Prova.** O botão do painel real está em `app/javascript/dashboard/routes/dashboard/autonomia/components/panel/PanelTune.vue:415-422` e chama `openReconverse`. Essa função, em `:209-214`, faz:

- `store.commit('autonomiaBuildThreads/RESET')`;
- abre a gaveta imediatamente;
- não despacha `autonomiaBuildThreads/resume`.

O primeiro envio, em `:228-239`, lê o thread do store. Como a função anterior acabou de executar `RESET`, não há id; o ramo determinístico despacha `autonomiaBuildThreads/start` com `agentId`, que chama POST de criação em `app/javascript/dashboard/store/modules/autonomiaBuildThreads.js:128-163` e `app/javascript/dashboard/api/autonomia/buildThreads.js:26-35`.

**Efeito.** Ao usar **Mudar conversando** em um agente já existente, a pessoa não vê a última conversa real. A UI abre vazia e o primeiro envio cria uma nova `BuildThread`, em vez de chamar `GET /autonomia/agents/:agent_id/build_thread` e depois `POST .../build_threads/:thread_id/messages`. Isso viola diretamente `design/B3.md:208-220` e os critérios `:253-258`: perde o histórico, pode criar sessões adicionais e não exercita os erros 401/404/422 do reader. O novo endpoint e os testes unitários do store não são alcançados por esse percurso de produto.

**Causa.** O backend/API/store foram implementados, mas a migração do consumidor legado `PanelTune` ficou pendente; os comentários do componente ainda codificam a premissa antiga de “criar sob demanda”.

**Correção mínima.** Fazer `openReconverse` aguardar `resume({ agentId })` e abrir somente após sucesso. O envio do painel deve usar exclusivamente o id retornado e `send`; remover o fallback `start` desse painel, preservando `start` somente no fluxo de criação de `AgentBuilderPage`. Adicionar prova de componente/integração para GET nested, histórico, id real e zero POST de criação; provar que erro 401/404/422 mantém a tela do agente sem conversa cenográfica.

## Checagem das demais lentes

- **Produto:** bloqueado pelo achado acima; a jornada “retomar e continuar” não entrega a conversa real.
- **Técnica:** o contrato de reader e store existe, mas não está conectado ao chamador do painel.
- **Segurança/produção:** o painel ainda abre a criação top-level, aumentando sessões e contornando a superfície de autorização/erro prevista para a retomada; não há evidência de vazamento no reader nested neste snapshot.
- **Testes:** os testes do store cobrem `resume` isoladamente; não há prova do fluxo `PanelTune`. O resultado conhecido de JS23 não fecha esse caminho; não o reexecutei.

O residual exige parada. Não alterei produto, não rodei testes/build/DB/navegador e não fiz commit, push, PR, merge, fila, deploy ou produção.
