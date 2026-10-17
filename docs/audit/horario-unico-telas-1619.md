# Horário único da caixa: telas (#1619, PR 2)

## Contexto

O PR 1 (#1651) fez a IA e o SLA lerem só o horário do canal (`inboxes.working_hours`) no fuso da conta, atrás da flag de conta `horario_unico_caixa` (ligada nas contas 1, 16 e 18). Este PR leva as telas para o mesmo modelo, seguindo o mockup aprovado. Tudo atrás da mesma flag: sem ela, as telas ficam como hoje.

## Decisões

- **Horário do canal** (Configurações › Caixa › Horário de funcionamento): componente novo do fork, `HorarioDoCanal.vue`, no lugar do `WeeklyAvailability`. Sem o campo de fuso. Mostra que a IA e o SLA seguem este horário e o fuso da conta, pelo rótulo de `rotuloDoFuso`, nunca "Brasília". As horas são escolhidas no `ChoiceSelect`, em 24 h, dentro do `DiaDoHorario.vue`. O salvamento usa a mesma API de hoje, sem mandar `timezone`. O único toque em `Settings.vue` é a troca condicional dos dois componentes.
- **CRM › SLA**: com a flag, sai a lista de calendários por caixa. Entram "Horário de cada pessoa" (o mesmo `CrmScheduleEditor`, com dono pessoa, que um calendário novo abre no fuso da conta) e "Horário dos canais" (só leitura, com link para a aba do canal). O `CrmInboxScheduleList` continua em uso sem a flag.
- **Agentes › Onde e quando**: a nota nova, `NotaHorarioDoCanal.vue`, entra com uma linha em `OndeQuandoEscolha.vue` e uma em `GavetaOndeQuando.vue`. Com horário, mostra a linha do fuso da conta e "Mudar o horário do canal". Sem horário, mostra "Definir o horário do canal". O link abre a aba do canal; ao voltar para esta, as caixas são relidas.
- **Textos**: catálogo novo do fork, `horarioDoCanal.json` (en e pt_BR), registrado em `config/fork_i18n.json` e excluído do Crowdin.
- **Guia**: `porques.md` não manda mais "conferir o fuso". Diz que vale o fuso da conta e que a IA e o SLA usam o horário do canal.

## Validação local

- Vitest focado, com `agentes`, `crm`, `settings/inbox`, `settings/agents`, `i18n` e os helpers: 159 arquivos, 2132 testes, 0 falhas.
- O gate `email-protection-eslint.mjs` e o Prettier nos arquivos tocados: 0 bloqueios. O separador "–" do `CrmScheduleEditor`, texto solto que já existia, foi para o i18n.
- `pnpm i18n:fork:check` e `pnpm guia:check` passaram.
- Visual: as telas reais foram montadas num host Vite local, com a store e a API falsas, em 1440 e 390 px e nos temas claro e escuro. Nenhuma ficou em branco ou com rolagem lateral.
