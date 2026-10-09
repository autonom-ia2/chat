# Confirmação final limitada R1 — produto/D9

**Data:** 2026-10-07  
**Alvo:** snapshot32 `fe3bcb720ead758c83aaafacb3b262a24277363fde5ea3af028261ee8bda79f1`.  
**Escopo:** somente os resíduos `F0-F1-R1-01` e `F0-F1-R1-02`, após a causa raiz registrada em `docs/audit/2026-10-07-agentes-f0-f1-limitada-causa-raiz.md`.  
**Método:** leitura final dos componentes e specs. Não executei testes, navegador, build, banco ou produção.

## Resultado estático

**Sem residual estático identificado.** O resultado final ainda fica condicionado ao recibo unitário do snapshot32; não marcar como GREEN antes desse recibo e da confirmação visual coordenada.

### R1-01 — adaptadores de etapas e locale

Fechado na leitura final:

- `AgentSteps.spec.js` exercita `en` e `pt_BR`, as quatro etapas, textos visíveis, `aria-label`, etapa atual, bloqueio e eventos `go`.
- `JourneyStepBar.spec.js` exercita `en` e `pt_BR`, as três etapas, textos visíveis, `aria-label`, etapa atual, bloqueio e eventos `go`.
- `Pronto` permanece fora da barra; o spec genérico não é usado como substituto dos catálogos reais.

### R1-02 — `AgentSwitch` real na lista

Fechado na leitura final:

- `AgentSwitch.spec.js` monta o wrapper real sobre `LabeledSwitch` e prova E5/E6, `aria-checked`, rótulo, payload booleano e `disabled`.
- `AgentRow.spec.js` desativa apenas o stub de `AgentSwitch` (`AgentSwitch: false`) e monta o componente real em E5 e E6.
- O spec da linha confirma, no E5, rótulo visível `Atendendo`, nome somente no `aria-label`, diálogo de pausa e payload `{ status: 'paused', enabled: false }`; no E6 confirma `Pausado`, `aria-label` com Clara e `{ status: 'active', enabled: true }`; também confirma o bloqueio real por `busy`.
- `AgentRow.vue` mantém a separação de rótulo visível e nome acessível, além de passar `checked`, `disabled`, `aria-label` e `label` ao wrapper.

## Gate de execução

Recibo do coordenador após esta leitura: snapshot32, job
`m2-e96f647731d048a09a4bda1e14b9f8f8`, 38 arquivos/224 testes passaram,
exit 0. As duas lacunas D9 passaram na execução. **F1 como conjunto permanece
STOP:** a passagem final de navegador encontrou contraste insuficiente no
H1 do vazio; 26 cenários não rodaram. Não há aceite visual nem autorização
de release. Registro: `docs/audit/2026-10-07-agentes-f0-f1-final32-stop.md`.

O recibo unitário do coordenador e a checagem visual continuam sendo a evidência de execução; esta leitura não os substitui. Se ambos passarem, estes dois resíduos podem ser considerados confirmados sem nova rodada. Se qualquer um falhar, aplicar STOP e registrar a causa antes de qualquer ação. Nenhum código, produto, merge, fila, deploy ou produção foi alterado nesta passagem.
