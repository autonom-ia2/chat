# Revisão normal F1 — técnica e segurança

**Alvo:** `docs/agentes-ia-redesign/design/F1.md` (DRAFT), comparado ao PRD, ao desenho F0, ao contrato B2 e ao código atual.

**Escopo da revisão:** somente a lista/vazio/ações da F1, com foco em isolamento de conta, gate antigo/novo, retomada, rotas e persistência do estado no store. Não foram executados testes, build, navegador, banco ou produção; o B2 ainda não foi tratado como validado.

## Resultado

**F1 não está pronta para implementação/aceite nesta forma.** Há dois bloqueios concretos: a retomada de E2m não tem um destino compatível sob o novo gate e a ação de PATCH permite que o store destrua a projeção segura da lista antes da releitura.

## Achados

### F1-TEC-01 — E2m pode chamar um leitor que o contrato proíbe e cair na casca errada

**Gravidade: P1 — bloqueia o cenário obrigatório de retomada manual.**

**Prova:** F1 define E2m como “Continuar → Ajustes › O que faz no painel compatível” (`design/F1.md:49-55`) e, na tabela de ações, manda a retomada ler primeiro o BE-05 para E1–E4, deixando E2m no `autonomia_agent_panel`/`tune` até F7 (`design/F1.md:85-92`). O contrato F0, porém, diz que com o redesign ligado `autonomia_agent_panel` é a casca nova e que o legado só é preservado com a flag desligada (`design/F0-mapeamento.md:128-145`). O mesmo contrato define BE-05 como `422 manual_mode` para um agente manual (`design/F0-mapeamento.md:144`), justamente o caso de E2m (`design/B2.md:147-153`). No código atual, a rota nomeada aponta para `AgentPanelPage` (`app/javascript/dashboard/routes/dashboard/autonomia/autonomia.routes.js:129-139`), portanto não existe hoje um destino independente que resolva essa exceção.

**Efeito:** uma implementação que siga a tabela genérica pode fazer uma requisição proibida ao BE-05 e deixar a pessoa na lista com erro; se ignorar o leitor, o mesmo nome de rota, sob a flag ligada, pode abrir a casca nova antes de F7 em vez do painel compatível. Isso quebra a jornada manual e deixa o comportamento dependente da ordem de entrega.

**Correção mínima:** tornar E2m uma ramificação explícita antes do BE-05: não chamar o leitor, preservar conta/agente e encaminhar para um destino legado nomeado que continue disponível com a flag ligada, ou adiar a ação até F7. Atualizar o mapa F0 para registrar essa exceção e incluir um caso de rota com flag ligada/desligada que prove que E2m não chama `build_thread`, não cria thread e chega ao painel previsto.

### F1-TEC-02 — PATCH de pausa/religação ainda pode substituir a projeção da lista

**Gravidade: P1 — pode remover estado, canais e métricas do cartão e deixa uma resposta parcial no store.**

**Prova:** F1 reconhece que o `show` sem `list_row` não devolve `state`, `stats` nem `channels[]`, e que `EDIT` substitui o registro inteiro (`design/F1.md:94-97`), mas não define uma ação/mutação que impeça esse caminho. O módulo `autonomiaAgents` é criado com `createStore` e, portanto, herda `update` do CRUD (`app/javascript/dashboard/store/modules/autonomiaAgents.js:1-18`; `app/javascript/dashboard/store/storeFactory.js:83-89,118-125`). Esse `update` faz o PATCH e comita imediatamente `response.data` (`app/javascript/dashboard/store/storeFactoryHelper.js:53-66`); a mutação `EDIT` substitui o objeto inteiro (`app/javascript/dashboard/store/storeFactory.js:76-80`; `app/javascript/shared/helpers/vuex/mutationHelpers.js:18-24`). A própria API documentada por F1 é o `PATCH agents/:id` seguido de um GET (`design/F1.md:85-97`).

**Efeito:** se a tela reutilizar a ação permitida pelo desenho, o cartão perde os campos da projeção no intervalo entre PATCH e GET. Se a releitura falhar, o requisito de preservar a lista anterior (`design/F1.md:104-108`) também fica violado, porque a lista já foi sobrescrita por uma resposta incompleta. Pode haver ainda renderização errada de estado/ações durante esse intervalo, embora o backend tenha confirmado a escrita.

**Correção mínima:** especificar uma ação F1 própria para pausa/religação que envie somente `status`/`enabled`, não faça `EDIT`/`UPSERT` com a resposta do PATCH e só atualize a projeção após GET bem-sucedido. Em erro do GET, conservar o registro anterior e mostrar o alerta. O teste do contrato deve provar corpo mínimo do PATCH, ausência de mutação parcial, GET posterior e preservação da projeção quando a releitura falhar.

## Pontos conferidos sem achado

- O gate novo foi mantido aditivo ao gate antigo e com fallback explícito no desenho F1/F0; não encontrei bypass de conta nesse contrato.
- BE-05 está corretamente limitado a conta/agente, com 401/404 e proibição de fabricar ou iniciar thread; o problema é a exceção E2m não estar especificada.
- A conexão de WhatsApp permanece em Canais/Caixas, sem rota de conexão em Agentes.
- Voz usa apenas o enum seguro `feminina`/`masculina`, com fallback feminino; não há inferência pelo nome nem exposição de configuração privada.
- A superfície de só ver, o tratamento de SuperAdmin e a separação das escritas estão coerentes com o PRD, condicionados à correção dos dois fluxos acima.

Não há aprovação técnica desta rodada. Como o resultado é negativo, a próxima ação deve ser causa raiz e uma única correção/revisão final, conforme o critério do handoff.
