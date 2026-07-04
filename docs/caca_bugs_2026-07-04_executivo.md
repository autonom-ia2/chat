# Caça a Bugs/Issues — Sumário Executivo (2026-07-04)

*Apresentação para decisão. Linguagem de negócio. O detalhe técnico está no doc irmão
`caca_bugs_2026-07-04_plano_tecnico.md`.*

---

## O que foi feito

9 pontos levantados pelo Rodrigo foram investigados **causa-raiz** — não palpite. Cinco frentes rodaram
**em paralelo**, cruzando o código real, a infraestrutura AWS (via acesso de leitura) e a **documentação
oficial** de AWS e Meta. Cada achado tem arquivo/linha ou evidência de CLI por trás. Nada foi alterado:
este material existe para **decidir o que atacar e em que ordem**.

---

## Retrato em uma tela

| # | Ponto | Veredito | Impacto no negócio | Recomendação |
|---|-------|----------|--------------------|--------------|
| 3 | Ativar agente "pede testar antes" | Não é trava — é layout de botão | Fricção na ativação | ✅ Fazer já (rápido) |
| 4 | Etiqueta do funil cortada | CSS de largura fixa | Leitura ruim no dia a dia | ✅ Fazer já (rápido) |
| 6 | Marcar campanha Meta no Kanban | Dado do WhatsApp **já chega**, só não é usado | Atribuição de venda por anúncio | ✅ Ganho barato (WhatsApp) |
| 8 | "Regressão" na Gestão de IA | **Não há regressão** — foi corte de custo consciente | Nenhum. Custo sob controle | ✅ Nada a corrigir |
| 7 | Atributos usados pelas IAs | IA não enxerga os campos preenchidos | Decisão de IA mais pobre | 🔵 Planejar (médio) |
| 5 | Automações com eventos do Kanban | Eventos existem, mas não ligados ao motor de automação | Automação de funil | 🔵 Planejar (médio) |
| 9 | Fluxo "base primeiro" na criação | Viável, com 1 trava técnica + 3 decisões suas | Onboarding do agente | 🔵 Planejar + decidir |
| 1 | E-mail conta 6 não chega | Recebimento não está montado | Canal de e-mail inoperante | 🟠 Operação (não é código) |
| 2 | Domínio Amazon "pendente" | **Nunca foi criado** no SES + conta em modo restrito | Envio de e-mail frágil | 🟠 Operação + infra |

Legenda: ✅ rápido/decidido · 🔵 projeto de código a planejar · 🟠 operação/infra (fora de PR de código).

---

## As 4 surpresas que o conselho precisa saber

1. **O e-mail e o "domínio pendente" são dois problemas separados.** O teste de e-mail que "funcionou"
   testa só o **envio**. A conversa não aparece porque o **recebimento** nunca foi ligado. Verificar o
   domínio **não resolve** o e-mail não chegar — são trilhos diferentes.

2. **A infraestrutura de e-mail da Amazon simplesmente não existe.** Não é "verificação pendente":
   **nenhum domínio nosso foi cadastrado** no serviço da Amazon, a conta está em **modo restrito
   (sandbox)** e um pedido anterior de liberação foi **negado** (com texto de outro cliente). É um
   trabalho de fundação, não um ajuste.

3. **A "regressão" da IA não existe.** No dia 30 baixamos o "esforço de raciocínio" de 4 tarefas para
   **cortar custo** — de propósito. **Nenhuma regra de decisão mudou** (mesmos limites, mesmo fluxo), só
   ficou mais barata; no máximo a IA "pensa" um degrau menos ao mover card sozinho. Se quisermos voltar a
   "caro/mais preciso", hoje exige mexer no código; dá para transformar num **botão de ambiente** (baixo esforço).

4. **A atribuição de campanha do Meta já está no bolso.** Toda venda que chega por anúncio
   click-to-WhatsApp **já traz** os dados da campanha — só estamos **jogando fora**. Ligar isso a uma
   etiqueta no Kanban é barato e destrava relatório de "qual anúncio gerou qual venda". **Google, ao
   contrário, não tem por onde entrar** hoje — precisaria de um canal novo.

---

## Plano em 3 ondas

**Onda A — Ganhos rápidos (dias, baixo risco):** ativar agente (3), etiqueta do funil (4), campanha
WhatsApp→Kanban (6), botão de custo da IA (8). Entram juntos num deploy só.

**Onda B — Projetos de código (1–2 semanas):** IA enxergar atributos (7), automação por evento de
Kanban (5), fluxo "base primeiro" na criação (9 — **depende de 3 decisões suas**).

**Onda C — Operação/Infra (não é código):** ligar o recebimento de e-mail da conta 6 (1) e cadastrar +
verificar os domínios na Amazon e sair do modo restrito (2). Cada passo de DNS/infra pede seu 🟢.

---

## Decisões que preciso de você

1. **E-mail (conta 6):** o recebimento vai por **caixa própria do cliente (IMAP/OAuth — mais simples)**,
   por **encaminhamento**, ou pela **Amazon (mais pesado)**? Sem isso, não conserto às cegas.
2. **Domínios/Amazon:** autoriza cadastrar os domínios, publicar os registros de DNS e **reabrir o pedido
   de produção**? Padronizar tudo em **us-east-1**?
3. **Fluxo "base primeiro" (9):** (a) vale para agente **interno**, para **com base de conhecimento**, ou
   só os dois juntos? (b) "máximo 30 bases" conta cada arquivo/link como uma base? (c) se um arquivo
   falhar ou o usuário não subir nada, o que libera o chat?
4. **Google (6):** aceitamos deixar **fora de escopo** por ora (sem canal de entrada), focando no Meta?

---

## O que já foi entregue nesta sessão (contexto)

- **PR #119** — confirmação + aviso ao apagar material da base (a "lixeira que parecia não fazer nada").
- **PR #118 (no ar)** — conhecimento geral liberado, "não sei" honesto, chunking de FAQ, sem travessão.

*Próximo passo: sua aprovação deste plano → abrimos as issues e atacamos a Onda A.*
