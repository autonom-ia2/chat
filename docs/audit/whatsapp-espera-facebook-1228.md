# Espera da janela do Facebook no cadastro do WhatsApp (#1228)

## Problema

`useWhatsappEmbeddedSignup` desistia 5 minutos depois de abrir a janela do Facebook. Em 10/10/2026, no teste da #1217 (caixa 111), a coexistência feita com calma passou desse tempo:

- a janela abriu às 08:05:29 e a tela falhou entre 08:10:22 e 08:11:01;
- o servidor não registrou nenhuma chamada;
- na Meta, o número ficou conectado, mas sem assinatura de webhook.

A segunda tentativa, feita rápido, concluiu.

## Decisão

- Nenhum prazo curto enquanto a janela está aberta.
- 60 s de espera só depois que o `FB.login` devolve o código (janela fechada), pela confirmação final da Meta.
- Trava de 30 min para a janela que nunca responde. O SDK do Facebook chama o callback quando a janela fecha, então a trava só cobre falha do próprio SDK; aceita como compromisso.
- Estouro marcado com `SIGNUP_TIMEOUT_CODE`.
- Se a Meta já confirmou e a janela fecha sem código, a tela trata como "não confirmado", não como "cancelado".
- Quem usa o cadastro (Trocar de conta, nova caixa, primeiro acesso, Reconfigurar) mostra "não deu para confirmar" e recarrega as caixas, sem texto técnico.

## Validação local

- Vitest: 17 arquivos e 212 testes passando. A suíte inclui os testes do composable, de `WhatsappSwitchAccount`, de `WhatsappEmbeddedSignup` (novo), de `ConfigurationPage`, do onboarding e da pasta `settings/inbox`.
- ESLint sem erro, e o `--fix` só mudou formatação. `i18n:fork:check` passou.
- Duas revisões independentes. Todos os achados foram corrigidos ou registrados aqui (a trava de 30 min).
