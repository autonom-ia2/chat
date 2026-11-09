# Prints da G32 (#2751), head ac808c28c7

Conferência visual do PR no painel local (`bin/demo`, demo `2751-g32` no M2), em 1440 e 390, tema claro. Fora do
head: esta pasta não vai no commit do PR.

## Como foi montado

- Branch `feat/2703-g32-reuniao` no head `ac808c28c7`, sem merge da main.
- Flags: todas as do `config/features.yml` (152), menos `customer_base` e `instagram_assisted_onboarding`, que ficaram
  fora em produção em 07/11. Não li as flags da conta 1 em produção: o token da AWS desta sessão estava inválido.
- `CRM_CALENDAR_MEETINGS_ENABLED=true` no Rails da demo. Sem ele, os gatilhos de reunião não aparecem. O kit
  (`script/demo/no_m2.sh`) foi mudado só na cópia local, sem commit.
- O seed (`seed_demo.rb`) monta a conta 1:
  - caixa WhatsApp oficial com o modelo `endereco_entrevista`;
  - funil Clientes (Entrada, Implantação) e página de agendamento Entrevistas;
  - três automações ligadas pelo motor (`assumir_e_religar!`, o mesmo caminho do botão Ligar).
- As jornadas estão em `jornadas.json`. `jornadas-execucao.json` é a parte da execução, tirada de novo depois.

## O que cada pasta mostra

| Pasta | Tela |
|---|---|
| `gatilho-reuniao-do-card/` | Automação "Reunião marcada pela página": o gatilho "Quando uma reunião é marcada", com funil e página (LivreGatilho); o passo de mensagem (LivreAlterar) |
| `lembrete-antes-da-reuniao/` | Automação "Lembrete da entrevista": o gatilho "Antes de uma reunião" (1 dia, página Entrevistas); o passo com o modelo e as variáveis |
| `contato-tem-reuniao-marcada/` | Automação "Cliente novo vai para Implantação": a espera "O contato tem reunião marcada (em qualquer card) é sim", no máximo 30 dias |
| `execucao-real/` | A lista: as três automações com "Rodou 1 vez esta semana". O "O que aconteceu" do cliente novo e do lembrete, com "terminou" |

## As execuções reais (seed, sem dublê)

1. O card "Contrato da Júlia" foi ganho, e a automação ficou esperando. A reunião foi marcada pela página num card
   novo do contato ("Júlia - Entrevistas"). A espera acordou na hora, e o card ganho foi para Implantação. Isso foi
   conferido no banco da demo (`card ganho na etapa: Implantação`). O quadro do CRM não mostra card ganho; por isso
   não há print dele.
2. A varredura do lembrete rodou com a entrevista marcada para o dia seguinte. A execução terminou.
3. A reunião marcada também disparou a automação "Reunião marcada pela página" (a lista mostra que ela rodou 1 vez).

## Observações (não são deste PR)

- No "O que aconteceu", a execução de alvo card aparece como "Uma conversa", sem os passos. Isso é o comportamento
  da main: o `Historico` esconde o alvo que não é conversa até o Contexto da F3 (comentário em
  `app/services/autonomia/automacao/historico.rb`).
- Em 390, a opção "O contato tem reunião marcada (em qualquer card)" aparece cortada com reticências no campo
  fechado.
- O aviso do lembrete ("Confere a cada 15 minutos…") explica o funcionamento do sistema. Fica o registro para a
  regra das telas para leigo.
- Erros 404 em todas as telas, que não vêm deste PR: `/autonomia/avisos`, `/enterprise/.../limits` e, na lista,
  `/autonomia/guide/execucoes`. Nenhum 5xx.
