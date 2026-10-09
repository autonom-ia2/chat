# Agentes de IA — correções F1 da R1

**Data:** 2026-10-07  
**Escopo:** primeira tela real (lista), seus componentes, composable e catálogos
en/pt-BR.  
**Referência:** `docs/agentes-ia-redesign/revisoes/F0-F1-R1-tecnica.md`.

Este registro documenta o bloco único de correção da R1. A confirmação limitada,
a execução dos testes e a inspeção das telas reais ainda são gates posteriores;
nenhuma aprovação visual ou de release é afirmada aqui.

## Causas e correções

- **F1-R1-01 — aviso de pausa ausente:** a lista não tinha o callout fixo exigido
  pelo CA-LISTA-11. `AgentsListPage` agora o exibe somente quando há agentes e usa
  `AGENTS.V2.list.pauseNotice` nos dois catálogos.
- **F1-R1-02 — estado do interruptor opaco:** `AgentRow` passava uma ação
  genérica ao `AgentSwitch`. O rótulo agora deriva E5/E6 de
  `AGENTS.V2.status.active/paused` e inclui o nome do agente.
- **F1-R1-03 — pausa do ajudante com cópia externa:** a confirmação agora usa
  `pauseInternalDescription` para `actuation === internal` e conserva a cópia de
  transferência para agentes externos.
- **F1-R1-04 — exclusão lógica descrita como destrutiva:** a confirmação agora
  informa que o rascunho sai da lista, sem afirmar remoção dos materiais.
- **F1-R1-05 — menu sem Escape e foco instável:** o menu fecha com Escape, fecha
  antes de abrir a confirmação e guarda o gatilho correto para restaurar o foco
  ao fechar o diálogo.
- **F1-R1-06 — sem canal sem hierarquia visual:** o contexto de agente externo
  ao vivo sem canal usa ícone de alerta e token âmbar; os demais contextos seguem
  neutros.
- **F1-R1-07 — cabeçalho fora da coluna visual:** o cabeçalho agora compartilha
  `max-w-6xl` e alinhamento do corpo, com escala de título/subtítulo ajustada e
  quebra preservada em telas estreitas.
- **F1-R1-08 — métricas duplicadas:** a linha visual mantém a prioridade
  semana → mês → sem conversas. Os quatro valores do payload continuam sendo
  lidos pelo contrato do composable; a segunda linha foi removida.
- **F1-R1-09 — cartão móvel em três blocos:** a grade mantém avatar e corpo na
  primeira linha e faz as ações ocuparem a linha seguinte abaixo de `sm`.
- **F1-R1-10 — modelos visualmente iguais:** os três modelos da tela vazia agora
  carregam life-buoy/teal, target/blue e concierge-bell/amber, com tile de
  `3.25rem` e exemplo ancorado ao fim do cartão.

## Ajuste após a primeira captura local

A primeira captura real encontrou contraste insuficiente em texto secundário e
nos CTAs azuis. Como correção do mesmo bloco, os textos pequenos sob esta
ownership usam `text-n-slate-11` e os CTAs da lista, do herói vazio e de
continuação usam `bg-n-blue-11` com `hover:bg-n-blue-12`. `ConfirmDialog`,
`AgentStatusPill` e `LabeledSwitch` permanecem na ownership do coordenador.

## Gates da mesma R1

- Os chips de resumo mantêm contorno e usam `rounded-xl`.
- A tela vazia não monta o cabeçalho da lista, portanto tem um único H1 no herói;
  o CTA usa azul de marca, a cópia é `Criar meu primeiro agente` e os anéis
  usam o token de marca. A lista com agentes conserva `Criar agente`.
- Continue e menu ficam desabilitados enquanto o cartão está ocupado.
- A leitura de retomada BE05 foi removida da lista. E1/E2 apenas navegam para
  `autonomia_agent_build` em `tell`; E3/E4 apenas navegam para sua etapa. A rota
  e o painel continuam donos da retomada e do carregamento antes do filho.
- `actionError` é limpo antes de pausa/religação e exclusão.
- Não foi criado fluxo de conexão, QR ou convite dentro de Agentes.

## Verificação local

- `python3 -m json.tool` passou nos catálogos en/pt-BR.
- Os specs da lista/linha foram atualizados para a métrica visual única e para
  os estados de foco, alerta de canal e bloqueio de ações.
- Não foram executados RSpec, Vitest, build, banco, navegador ou produção neste
  bloco. O parecer não substitui a confirmação limitada nem a inspeção de todas
  as telas reais nos cenários do aceite.
