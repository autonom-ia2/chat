# Agentes · Fase 1 — decisões fechadas

Issue #1181 (épica #1114). Fonte de UX e textos: `prototipo/jornada.html` (aprovado pelo Rodrigo em 09/10/2026).
`spec-final.json` é a especificação anterior ao protótipo; onde divergir, vale o protótipo e esta página.
`plano-mapas.json` traz o mapeamento do código e o plano de PRs com as críticas.

## Produto (Rodrigo)
- Fase 1 só frontend, atrás da flag `autonomia_agents_journey` (fim de `config/features.yml`, `feature_flags_ext_1`,
  posição 14, bit `1 << 13` = 8192). Piloto na conta 16, ligado só depois dos 3 PRs no `main`.
- Saem da tela nova: Primeira mensagem, Perguntas iniciais, Transferir para um humano, Limite de confiança, Quando não
  souber e qualquer percentual de certeza/confiança/nota.
- Quem recebe a conversa passada para a equipe é definido em Atribuição (de propósito). Tela mostra só a frase e o link
  "Escolher quem recebe".
- Menu "Agentes" (um item só), "Criar agente", "Mudar conversando". Arquivos sempre opcionais.
- Backend permitido: a flag e duas leituras novas em arquivos novos, atrás da flag: L1 números da semana, L2 canais
  ocupados. Nada de runtime, contrato existente, Construtor, prompt.

## Orquestrador (qualidade delegada)
1. Entrada: as rotas atuais (`autonomia_agents_index`, `autonomia_agents_builder`, `autonomia_agent_panel`) ficam com o
   mesmo nome, caminho, meta e guarda. Um seletor fino escolhe o componente pela flag. O seletor importa a página antiga
   de forma estática e a nova com `defineAsyncComponent`; decide UMA vez no setup (não reativo). Flag desligada = nenhuma
   chamada nova de API (teste com mock).
2. "Conversas respondidas" na semana = conversas com resposta do agente (evento de resposta), não o `handled` que inclui
   repasse por público/horário. "Passadas para a equipe" = conversas distintas com handoff (nunca contagem de eventos).
   A página do agente lê a mesma L1 (filtro por agente) para não divergir da lista.
3. Chips: só "ideias para começar" no primeiro turno (preenchem o campo, a pessoa pode editar). Respostas às perguntas
   do Construtor são texto livre (com clipe para arquivo/foto). Sem chips fixos fingindo responder pergunta da IA.
4. `useComecarAAtender` (ativar + conectar + troca de canal ocupado) nasce no PR1. Ordem: PATCH status active no novo →
   DELETE canal no antigo (se troca) → POST canal no novo; falha depois do PATCH desfaz o status do novo ("Nada mudou").
5. Rascunho que sai no Confira continua draft ("Falta terminar"). Só começa a atender quem escolheu onde.
6. Versões (T13): só o que a API tem — data, hora e frase pelo motivo (atualizado pelo que sabe / escrito por você /
   voltou a um jeito anterior). Sem selo "Em uso".
7. Agente manual: sem "Mudar conversando"; "Editar instruções" no lugar. Agente de cotação: só nome, foto, horário,
   status e números; resto leva ao módulo de cotação. Modo manual + instrução num PATCH só, e só ao salvar texto não vazio.
8. Links "Escolher quem recebe" e "Conectar seu WhatsApp ou outro canal" só aparecem para quem tem permissão; sem
   permissão, frase "Peça a um administrador para …".
9. Vocabulário: "Começar a atender", "Atendendo", "Parado", "Parar de atender", "Voltar a atender"; nunca "Ligar".
   Etapas Conte · Confira · Comece. Neutro em gênero com `{nome}`.
10. Botão primário AA em componente próprio (`bg-n-blue-11` claro; validar escuro). Navy de herói como no
    AutomacaoHeroi. Componentes compartilhados do produto não são editados; o que faltar nasce em
    `app/javascript/dashboard/routes/dashboard/autonomia/agentes/`.
11. A store `autonomiaBuildThreads` tem um poll único: telas novas chamam `stopPolling` ao sair.

## Revisão do PR1 (09/10/2026) — riscos aceitos e pontos em aberto
12. Enquanto a lista carrega (e no erro), a tela mostra o herói compacto do T02. Não há como saber se a conta está
    vazia antes de a lista chegar; numa conta sem agentes, o herói troca para o do T01 quando ela chega. Aceito.
13. L2 (`canais_ocupados`) lista nome e tipo de todas as caixas da conta para quem tem `autonomia_view`, inclusive
    função personalizada sem acesso às caixas. É o mesmo nível que `agents/:id/channels` já expõe. Risco aceito.
14. O catálogo de leituras do Guia é montado das rotas GET: ganha `autonomia/numeros_da_semana` e
    `autonomia/canais_ocupados`, que respondem 404 com a flag desligada. Tirá-las do catálogo mexeria no Guia; fora do PR1.
15. Bundle: a lista antiga passa a vir dentro do arquivo do seletor (`AgentesListaEntrada`); a página nova continua num
    arquivo à parte (import dinâmico). Só muda o nome e a composição do arquivo.
16. **Decidido: (a) reconectar o antigo; se falhar, motivo `troca_sem_agente`.** Na troca de canal, se o DELETE no
    agente antigo funciona e o POST no novo falha, o `useComecarAAtender` desfaz o status do novo e depois tenta
    reconectar o antigo à caixa (mesmo POST, com o id do antigo). Reconectou: o retorno é o "Nada mudou" das outras
    falhas (motivo da falha do POST no novo: `comecar`, `canal` ou `offline`). Não reconectou: `motivo:
    'troca_sem_agente'` com `troca`, e a tela diz `AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE` /
    `TROCA_SEM_AGENTE_GARANTIA` ("A caixa ficou sem agente. As conversas vão para a equipe."). O motivo `troca` deixou
    de existir.
