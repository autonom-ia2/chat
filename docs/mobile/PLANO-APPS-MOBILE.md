# Apps mobile oficiais — Chat2You e chat.ai

Estado: plano (16/10/2026). Nenhum código escrito.

## Onde paramos (21/10/2026)

- Épico #1721; F0 contas Hub2You #1722; F1 base técnica #1723. Todos em Backlog no
  Project Autonom.ia Dev (Projeto Hub2You, P2).
- **Esperando o Rodrigo decidir:**
  1. Push: (a) troca em data marcada ou (b) mudança no servidor para convivência (risco 2).
  2. Repositório novo: `autonom-ia2/chat-mobile`?
- **Próxima ação:** pedir o D-U-N-S da Hub2You junto com o Rodrigo
  (https://developer.apple.com/enroll/duns-lookup/). Separar razão social exata do
  CNPJ, endereço da sede, telefone, nome legal e e-mail @hub2you.ai.
- Assumido, sem confirmação explícita: Rodrigo assina pelas duas empresas.

## Decisões tomadas (Rodrigo, 16/10/2026)

- Dois apps com marca própria, um por empresa:
  - **Chat2You** — Hub2You, servidor `chat.hub2you.ai`. **Sai primeiro.**
  - **chat.ai** — Autonom.ia, servidor `chat.autonomia.site`. Segundo app.
- CNPJs diferentes, ambos sociedades limitadas. Cada empresa publica o próprio app na
  própria conta Apple/Google (é a "dona do conteúdo", o que a regra 4.2.6 da Apple exige).
- Escopo principal: atendente responder no celular, Agentes, CRM e Campanhas.
- Base: fork do app oficial do Chatwoot (`chatwoot/chatwoot-mobile-app`, licença MIT,
  React Native 0.86 + Expo 57, ativo). Não reaproveita a aprovação deles: é app novo,
  identificador novo, revisão do zero.
- O teste com o app do Chatwoot já foi feito: a equipe usa hoje.

## Regras que valem para o app

- Licença MIT: manter o aviso de licença dentro do app.
- Não usar nome nem logo "Chatwoot".
- Celular é para **acompanhar e agir rápido**. Montar agente, funil ou campanha do zero
  continua no computador.
- Telas novas (F3–F5): jornada clicável aprovada antes do código.
- Cada app nasce preso ao seu servidor, sem tela de "digite o endereço".

## Riscos conhecidos

1. **Apple 4.3 (spam) com dois apps do mesmo código.** Mitigação: um app por vez, cada um
   na conta da própria empresa, e o segundo com visual e destaque próprios.
2. **Push: troca é tudo ou nada hoje.** `Notification::PushNotificationService` manda
   direto pelo Firebase quando `FIREBASE_PROJECT_ID` + `FIREBASE_CREDENTIALS` existem e,
   nesse caso, **não usa mais o relay do Chatwoot** (`send_push_via_chatwoot_hub` retorna
   cedo). O envio direto para um aparelho do app do Chatwoot falha, e
   `remove_subscription_if_error` apaga a inscrição. Ligar o nosso Firebase corta o push
   de quem ainda está no app do Chatwoot, de uma vez.
   Decisão pendente: (a) trocar em data marcada, com todos já no app novo; ou
   (b) mudança pequena no servidor para cada inscrição saber de qual app veio e seguir
   pelo caminho certo, o que permite convivência.
3. **Nome "chat.ai" nas lojas.** Há dezenas de apps "Chat AI" (genérico, difícil de achar
   na busca). Conferir disponibilidade e pensar em nome de loja com complemento
   (ex.: "chat.ai — Autonom.ia") antes de investir na marca.
4. **Prazo das contas.** D-U-N-S até 5 dias úteis; Google pode levar até 30 dias.

## Fases

### F0 — Contas (por empresa; começa pela Hub2You)
1. D-U-N-S (grátis, pela ferramenta da Apple).
2. Apple Developer como organização (US$ 99/ano): Apple ID com nome legal e verificação
   em duas etapas, e-mail no domínio da empresa, site no ar com conteúdo real, ligação de
   confirmação da Apple.
3. Google Play como organização (US$ 25, uma vez): D-U-N-S e documentos da empresa.
4. Firebase da marca, chave APNs ligada ao Firebase, conta Expo/EAS.
5. Páginas públicas de privacidade e suporte.
6. Conta de demonstração para a revisão das lojas (fora de conta de cliente real).

### F1 — Base técnica
- Repositório novo, fork do app do Chatwoot.
- Um código, várias marcas: arquivo de marca por app (nome, ícone, cores,
  identificador, servidor, Firebase).
- Push pelo nosso Firebase, com a decisão do risco 2 tomada antes.
- Build e envio pelo EAS; correções de tela e texto via EAS Update.

### F2 — v1 Chat2You: atendimento
Rebranding + push. TestFlight e trilha interna do Google Play com a equipe; depois lojas.

### F3 — Agentes na conversa
Ver que a IA está atendendo, "Atribuir a mim", ligar/desligar a IA na conversa.

### F4 — CRM
Card do contato, mover etapa, anotar.

### F5 — Campanhas
Acompanhar resultado, pausar.

### F6 — chat.ai
Mesma base, marca Autonom.ia, conta da Autonom.ia, visual próprio.

## Custo fixo
- Apple: US$ 99/ano por empresa.
- Google: US$ 25 por empresa, uma vez.
- EAS: plano grátis deve bastar no começo (confirmar na F1).

## Fontes
- Apple D-U-N-S: https://developer.apple.com/support/D-U-N-S/index.html
- Apple enroll: https://developer.apple.com/programs/enroll/
- Google verificação: https://goo.gle/developer-verification
- Regra 4.2.6: https://techcrunch.com/2017/12/20/apple-revises-its-controversial-guidelines-on-template-based-apps/
- App do Chatwoot: https://github.com/chatwoot/chatwoot-mobile-app
