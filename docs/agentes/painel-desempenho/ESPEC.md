# Painel de desempenho do agente — especificação final (#2226)

Épico autonom-ia2/chat#2226, filho de #1424. Base: worktree em `ed76999ef8`.
Esta especificação junta as três propostas (Negócio, UX, Eficiência) e responde
a todos os achados BLOQUEIA e IMPORTANTE dos cinco revisores. A seção 10 diz,
achado por achado, como cada um ficou.

Produção não foi consultada. Todo número de custo aqui é **hipótese** até
rodar o SQL de 90 dias (pergunta 5).

O repositório é público: este documento não traz nome de cliente, frase real
nem dado de conta. Exemplos são inventados.

## Decisões do Rodrigo (26/10/2026)

As cinco perguntas da seção 9 foram respondidas. Onde a decisão difere da
recomendação, vale a decisão:

1. **Totais:** do que a pessoa vê; admin vê a conta. Supressão abaixo de 5.
2. **Quem paga a leitura:** a **chave de IA do cliente** (`crm_kanban_ai`),
   não a nossa. O teto mensal continua existindo, agora sobre o gasto na
   chave dele. Sem chave do cliente, o estado "A leitura não está funcionando
   nesta conta" pede para conectar a chave.
3. **LGPD:** o recurso nasce **ligado**. Assuntos de saúde, frase real e
   audiências seguem as regras da seção 6.4.
4. **Passado:** ler o passado ao ligar. Poucos agentes estão ligados hoje, e
   o custo medido é baixo (abaixo).
5. **Medição:** feita em produção, só leitura. **A conta de referência é a
   maior** (agente de outro sistema, centenas de conversas em 2 semanas). Ela e a
   conta piloto com dois agentes de outro sistema são as que mais exigem do
   painel.

### O que a medição mostrou (sem dado de cliente)

- O histórico na plataforma começa em 12/10: são 2 semanas, não 90 dias.
- Conta de referência: centenas de conversas, dezenas de milhares de
  mensagens, na casa do milhão de caracteres. Mediana de algumas dezenas de
  mensagens por conversa; as 10% mais longas passam de uma centena, e a maior
  chega a centenas. **A conversa é longa e volta muitas vezes**: o mesmo
  contato fala dias seguidos na mesma conversa.
- Conta piloto: dezenas de conversas, mediana na casa de uma dezena e meia de
  mensagens.
- Ler todo o histórico da conta de referência custa centavos de dólar com o
  modelo leve (ordem de US$ 0,2 a 2, conforme o raciocínio).
- Anúncio identificado: só na conta piloto (dezenas de conversas). A conta de
  referência não tem anúncio ligado; o bloco 2 fica vazio para ela até ligar.
- As três contas medidas têm chave de IA própria configurada.

Consequência para o desenho: a unidade de leitura e de contagem não pode ser
a conversa inteira. Ver a pergunta aberta 6.

### Pergunta aberta 6 — o que conta como "um atendimento"

Na conta de referência uma conversa reúne dias de contato. Contar por
conversa esconde volume; ler a conversa inteira a cada retorno gasta à toa.
Proposta: um atendimento = trecho da conversa separado do anterior por mais
de 6 horas sem mensagem; a leitura é por atendimento, com a ficha anterior
como contexto. O painel de setembro usava janelas de 30 minutos.

### Decisão 6 — a unidade é a "procura", cortada pela mudança de assunto (26/10)

O Rodrigo recusou o corte por tempo. Vale:

- A própria leitura separa a conversa em **procuras**. Procura nova é **pedido
  novo**: outra peça, outro modelo, outro cliente do parceiro, ou outra dúvida
  que não depende da anterior. Voltar ao mesmo pedido dias depois continua a
  mesma procura. Quem decide é a IA, com a saída "não se aplica"; nenhuma lista
  de palavras.
- O tempo entre mensagens entra só como pista para a IA. Ele nunca corta
  sozinho.
- Leitura incremental: a IA recebe o resumo da última procura e as mensagens
  novas, e responde "continua" ou "começou outra".
- A ficha passa a ter uma linha por procura (`procura_inicio_message_id`,
  `procura_fim_message_id`, tema, detalhes, marcos ditos, desfecho dito). O
  índice único vira `(account_id, conversation_id, procura_inicio_message_id)`.
- Os assuntos que a IA do CRM já separa (`crm_subject_decisions`, cards por
  conversa) servem de conferência. Divergência vai para a amostra conferida.
  Na conta de referência, essa IA passou por menos de um terço das conversas
  do robô em 30 dias e abriu assunto novo poucas vezes. Por isso não dá para
  depender dela.
- Na tela, o número principal é **"procuras"**, com o número de conversas ao
  lado.

## A regra de interface

> **"UI-UX e design premium com jornada tão simples que até um ser humano com
> QI 70 e sem conhecimento em tecnologia consegue usar."**

O que ela obriga, nesta tela:

- uma ação principal por tela; o resto é link secundário;
- frase curta, sem termo técnico e sem sigla ("marco", "cobertura",
  "fricção", "certainty" nunca aparecem na tela);
- estado vazio = 1 frase + 1 botão; nunca mostrar zero no lugar de "não sei";
- botão "Alterar" escrito por extenso;
- nenhum `<select>` nativo: escolha usa `components-next/choice-select/ChoiceSelect.vue`;
- nada em caixa alta; só Tailwind; textos em en e pt_BR;
- texto geral sem vocabulário de ramo; o vocabulário do ramo vem do pacote da conta;
- gráfico só quando a forma é a resposta (tendência e ranking). Nada de
  pizza, radar, dispersão ou medidor.

---

## 1. Para quem e quais decisões o painel apoia

**Para quem:** o dono ou gestor da conta (admin) e quem tiver a nova chave
`desempenho_view`. Não é um painel de engenheiro: cada bloco responde a uma
decisão e termina numa ação.

**Critério de corte:** bloco que não responde a uma das seis decisões abaixo
sai do painel.

| Decisão | Serviço vendido por orçamento | Loja de motopeças | Energia solar | Clínica |
|---|---|---|---|---|
| 1. Onde pôr dinheiro em anúncio | O anúncio do plano completo traz quem pede orçamento; o de "barato" traz curioso | O criativo de um kit de peça gera pedido; o de promoção gera só pergunta de frete | O anúncio que fala de conta de luz alta traz quem pede visita | O anúncio de check-up traz quem marca; o de estética traz só pergunta de preço |
| 2. O que mudar na oferta | Muita gente pergunta de cobertura que o produto não tem | Uma peça muito pedida está sem estoque | Muitos pedem financiamento e ele não é oferecido | Muitos pedem horário à noite e não há |
| 3. Quem chamar de volta | Pediu orçamento e não fechou | Pediu preço e não comprou | Pediu visita e não marcou | Pediu horário e não confirmou |
| 4. O que ensinar ao agente | A mesma dúvida sobre o que está incluído vai para a equipe toda semana | Compatibilidade de peça sempre vai para a equipe | Dúvida sobre ligação na rede de energia vai para a equipe | Pergunta sobre preparo de exame vai para a equipe |
| 5. Onde a equipe perde gente | Passou para a equipe no domingo à noite e ninguém respondeu | Passou na segunda de manhã e demorou 4 horas | Passou e a visita nunca foi marcada | Passou e o paciente marcou em outro lugar |
| 6. Se o agente vale o que custa | Quanto custa cada orçamento que ele levou | Quanto custa cada pedido | Quanto custa cada visita pedida | Quanto custa cada consulta marcada |

A decisão 5 entrou por crítica do revisor de negócio: o lead costuma morrer
**depois** da passagem para a equipe, não na primeira resposta do agente.

---

## 2. A jornada e a tela, bloco a bloco

### 2.1 Como a pessoa chega

- **Página do agente** (`AgenteSemana.vue`): embaixo dos três cartões entra o
  link **"Ver tudo de {nome}"**. Os cartões continuam abrindo a gaveta.
- **CRM › Números › Equipe:** a linha da IA ganha o mesmo link.
- **Rota:** `/autonomia/agentes/:id/desempenho` para agente nosso e
  `/autonomia/agentes/:id/desempenho?origem=webhook` para agente de fora
  (o mesmo padrão de `AgenteOutroSistemaPage.vue`, porque os ids podem
  coincidir). Página inteira, não gaveta, para dar rolagem e link
  compartilhável.
- **Migalha:** "Agentes › {nome} › Desempenho".
- **Período padrão: 30 dias.** Com 7 dias, conta pequena não tem dado para
  concluir nada.

### 2.2 A moldura de todo bloco

Todo bloco tem a mesma forma, para a pessoa aprender uma vez:

1. título em pergunta;
2. resposta em uma frase grande;
3. o conteúdo (lista, barra ou frase);
4. **um** chip de pergunta para o Guia;
5. o link secundário **"Ver as conversas"**, que abre a lista identificada.

Nenhum bloco tem botão de mudar coisa. Toda ação de mudar fica no bloco
"O que fazer agora". Assim a tela tem uma ação principal só.

Acessibilidade: setas e barras são decorativas (`aria-hidden`); a frase
inteira vai no `aria-label`. A cor nunca carrega sozinha a informação.

### 2.3 Herói

Reaproveita `PaginaHeroi.vue`, que já usa o fundo `#0D2344`. A pessoa não
sente que saiu da página do agente: mesma foto, mesmo nome, mesma moldura.

De cima para baixo:

1. **Foto, nome e período:** "Últimos 30 dias · Alterar". O "Alterar" abre um
   `ChoiceSelect` com 7 dias, 30 dias, 90 dias e "Este mês".
2. **Frase do período**, montada por regra, sem IA. Ela **descreve, não
   julga**, e fala de resultado de negócio antes de autonomia:
   - com marco confirmado: "Das 320 conversas, 41 chegaram ao orçamento e 120
     pararam no meio do caminho."
   - sem marco confirmado: "{nome} atendeu 320 conversas. Ainda não sabemos
     quantas viraram negócio." (botão vira "Dizer o que conta como resultado")
   - com poucas conversas (menos de 20): "Ainda é cedo: com 12 conversas não
     dá para dizer muito."
   - cor neutra sempre. Verde ou âmbar só quando o admin definir uma meta
     (fica para depois do primeiro corte).
3. **Uma ação principal** logo abaixo da frase, no fluxo da página (nada
   fixo no rodapé do celular): o cartão mais forte de "O que fazer agora".
   Ex.: **"Ver o que fazer agora"**. Sem cartão: **"Ver as conversas"**.
4. **Quatro números**, todos da `Autonomia::ContaDaIa` (uma regra só):
   - conversas atendidas;
   - chegaram ao resultado principal (nome do marco do agente: "Cotações
     pedidas", "Visitas marcadas", "Pedidos feitos", "Consultas marcadas");
   - passadas para a equipe;
   - resolvidas sem a equipe (secundário: autonomia não é o objetivo).
   Comparação com o período anterior por extenso ("12 a mais que no período
   anterior") **só** quando os dois períodos têm leitura de pelo menos 80% e
   a mesma versão da ficha do agente. Fora disso, a comparação não aparece.
5. **Selo de confiança**, uma frase só, sem custo e sem jargão:
   - "Lemos quase todas as conversas deste período. Uma pessoa conferiu 60
     leituras: 54 estavam certas."
   - sem conferência por pessoa ainda: "Lemos quase todas as conversas. A
     conferência ainda está acontecendo."
   - leitura por amostra: "Lemos 3 de cada 10 conversas neste mês."
   - toque abre **"Como contamos"** (seção 4.8). O custo da leitura só aparece
     ali, e só para quem tem `financial_view`.

Celular: a mesma ordem empilhada; números em grade 2×2; nada fixo.

### 2.4 Bloco 1 — "Do que as pessoas estão procurando?" (decisões 1, 2, 4)

O coração do painel. Vem primeiro porque é o que o dono não tem em lugar
nenhum.

- **Resposta:** "O que mais se pede é {tema}: 128 procuras, 31 chegaram ao
  orçamento." (números inventados)
- **Conteúdo:** lista ordenada de 5 a 8 assuntos. Cada linha (exemplo
  inventado, loja de motopeças):

  ```
  Kit de relação                       128 procuras    ▬▬▬▬▬▬▬▬
  Mais pedido: moto 160 cc · original · entrega na semana
  "Tem o kit completo para a minha moto?" — {Contato} · Abrir
  31 chegaram ao orçamento · Volta a aparecer: 3 de cada 10 pessoas
  ```

  - **Detalhes do pedido** (linha "Mais pedido"): os 2 a 4 detalhes que a
    ficha do agente define (peça e modelo da moto; cidade e valor da conta
    de luz; especialidade e turno). Cada
    detalhe aceita "não se aplica".
  - **Frase real** com nome e link: só de conversa que a pessoa pode ver, e
    nunca em tema sensível (seção 6.4). Para tema sensível: só o número.
  - Tema com menos de 5 conversas visíveis: "menos de 5", sem frase e sem
    link. Com menos de 20: número sem porcentagem e o selo "Ainda pouco para
    concluir".
  - Temas que a IA sugeriu e o admin ainda não confirmou: o admin vê com o
    selo "Sugerido · Alterar"; os outros não veem até a confirmação.
  - Se houve fusão de temas no período: "Inclui 2 assuntos unidos em 12/10."
- **Sub-bloco "Onde a pessoa desistiu"** (atritos traduzidos): "12 pessoas
  pararam quando o agente pediu documento." Lista curta, 3 itens.
- **Sub-bloco "O que {nome} ainda não sabe"**: temas em que a conversa foi
  para a equipe com o motivo "não sabia responder" ou em que a leitura marcou
  "o agente não soube". Vira cartão em "O que fazer agora".
- **Chip do Guia:** "Do que as pessoas mais procuram?"
- **Estado vazio por motivo** (componente único `EstadoDoPainel`, seção 2.10).

### 2.5 Bloco 2 — "Qual anúncio traz quem vira negócio?" (decisão 1)

- Só aparece se a conta tem anúncios ligados. Sem anúncio ligado não há
  estado vazio aqui: não é problema do agente. Uma linha discreta diz
  "Ligue seus anúncios para ver isto · Ligar" só para admin.
- **Um cartão por anúncio**, nunca tabela de cinco colunas. No máximo 3
  cartões e "Ver todos".

  ```
  [miniatura]  Anúncio "Kit de relação com frete grátis"
  Quem veio daqui quer saber de preço e de prazo de entrega.
  1 em cada 5 chegou ao orçamento · R$ 38 por orçamento · 84 conversas
  ```

- **Duas visões**, trocadas por "Ver por campanha · Alterar":
  - **por anúncio:** só vínculos com certeza `ad` e `ad_name`;
  - **por campanha:** `ad`, `ad_name` e `campaign`.
  - Vínculo `unknown` e conversa sem vínculo: uma linha "Veio de anúncio, sem
    saber qual: 40 conversas". Nunca rateadas entre anúncios.
- **Custo** só no nível em que o gasto é real: por resultado do anúncio
  (gasto do anúncio ÷ conversas dele que chegaram ao marco). **Não existe
  "custo por assunto"**: a Meta não informa gasto por assunto, e ratear seria
  inventar número.
- **Cada conversa conta uma vez:** atribuída ao primeiro toque
  (`first_touch`) de `crm_meta_ad_links`.
- **Lacuna conhecida:** `Crm::MetaAdLink::ORIGINS` só tem `whatsapp` e `site`
  (`app/models/crm/meta_ad_link.rb:13`). Anúncio que abre o Direct do
  Instagram não gera vínculo. Antes da entrega deste bloco abrimos uma Issue
  para verificar e, se for o caso, ligar. Até lá a tela diz: "Anúncios que
  abrem o Direct do Instagram ainda não aparecem aqui."
- **Chip do Guia:** "Onde eu ponho mais dinheiro em anúncio?"

### 2.6 Bloco 3 — "O que acontece quando passa para a equipe?" (decisões 4 e 5)

- **Resposta:** "88 conversas foram para a equipe. 21 esperaram mais de 4
  horas, e 9 dessas não voltaram."
- **Conteúdo:**
  - **Por que passou:** barras horizontais em frase, a partir dos 15 códigos
    de `event_logger.rb:15-17`, traduzidos por `curate_reason` (já existe em
    `analytics.rb`) mais chaves i18n novas para os códigos internos.
    Ex.: "A pessoa pediu para falar com alguém", "Não sabia responder".
  - **Depois da passagem:** tempo até a primeira resposta de uma pessoa;
    quantas ficaram sem resposta da equipe por mais de 4 horas (o limite é
    ajustável pela conta, padrão 4h); quantas dessas chegaram ao marco.
  - **Silêncios:** reaproveita `AgenteSilencios.vue`.
- **Chip do Guia:** "Onde a equipe está perdendo gente?"

### 2.7 Bloco 4 — "Quando as pessoas aparecem?" (decisão 5)

- **Resposta:** "Mais movimento: terça à noite, das 19h às 22h."
- **Conteúdo:**
  - ritmo diário: barras, um dia por barra;
  - as 3 faixas de horário mais cheias, em frase;
  - a grade dia × hora fica atrás de "Ver todos os horários", e só com 200
    conversas ou mais. Cada célula leva o valor no `aria-label`.
  - tempo de resposta do agente: uma frase, sem destaque (é sempre de
    segundos; o que importa é o bloco 3).
- Tudo no fuso da conta (`Crm::Timezone::Resolver`), nunca em UTC.
- Se a instrução do agente mudou no período: aviso em texto acima do gráfico,
  "A instrução mudou em 12/10. Antes e depois não se comparam direto."
- **Chip do Guia:** "Em que horário falta gente?"

### 2.8 Bloco 5 — "Quem vale a pena chamar de volta?" (decisão 3)

- **Grupos**, montados **na hora da consulta**, cruzando a ficha com o CRM
  (nunca com o desfecho congelado na ficha):
  - "Chegaram perto e pararam": marco dito na conversa, sem venda, sem
    reunião marcada e sem card ganho depois.
  - "Voltaram várias vezes": mesmo contato, mesmo assunto, em sessões
    separadas por mais de 24h.
  - "Sumiram depois de mostrar interesse": intenção de compra e nenhuma
    mensagem do contato há 30 dias.
- **Cada linha:** nome do contato, caixa, último contato, assunto, "Abrir
  conversa". Só conversas visíveis para a pessoa. Tema sensível nunca entra
  em grupo.
- Sem exportação no primeiro corte.
- **Chip do Guia:** "Quem eu chamo de volta primeiro?"

### 2.9 Bloco 6 — "O que fazer agora?" (do sinal à ação)

- **No máximo 4 cartões**, ordenados pelo tamanho do efeito. Nenhum cartão
  com menos de 30 conversas no período.
- Cada cartão: o que vimos (com o número e o link das conversas), o que
  fazer, e **um** botão. Selo "Já dá para usar" ou "Ainda falta dado" (diz
  qual).
  - **Anúncio:** "Quem vem do anúncio X chega ao orçamento 2 vezes mais que a
    média." Botão: "Levar ao consultor de anúncios".
  - **Retomada:** "34 pessoas chegaram perto e pararam." Botão: "Chamar de
    volta". Leva ao fluxo de Campanhas existente, com as regras de opt-in e
    janela do canal. Se fora da janela de 24h e sem modelo aprovado, o
    cartão diz "Precisa de um modelo de mensagem aprovado · custo estimado
    de R$ X para 34 pessoas" e o botão vira "Criar o modelo". Só fica "Já dá
    para usar" com modelo aprovado. Exige também `campaign_manage`.
  - **Ensinar:** "{nome} passou 20 conversas por não saber sobre Y." Botão:
    "Ensinar a {nome}", que abre `GavetaOQueSabe` já preenchida.
  - **Instrução:** "Em 15 conversas, {nome} não pediu o que a instrução
    manda." Botão: "Ver as conversas".
- **Fim de jornada:** toda ação volta ao painel com a faixa "Feito: {nome}
  aprendeu sobre Y" (ou "Campanha criada"), e o cartão fica marcado como
  feito até a próxima atualização semanal.
- Sem cartão: "Nada novo esta semana." Nunca inventar recomendação.
- **Chip do Guia (destacado):** "Por onde eu começo?"

### 2.10 Bloco 7 — "O que estes números não provam"

Fixo, recolhido, com o mesmo peso visual dos outros. Frases i18n mais avisos
que mudam com os dados:

- "Assunto não é o motivo da compra. Mostra o que se fala, não por que se
  compra."
- "Só sabemos de venda marcada no CRM. Venda fechada fora daqui não aparece."
- "Só contamos quem veio de anúncio identificado."
- "Áudio sem transcrição e imagem sem leitura não foram lidos."
- "Conversas ainda em andamento ficam de fora até terminarem."
- Dinâmico: "Pouco dado: 7 conversas neste assunto." / "Lemos por amostra
  neste mês." / "Custo do agente só desde {data}."

### 2.11 Estados vazios e intermediários

Componente único `EstadoDoPainel.vue`, uma variante por motivo, com teste por
variante. Nunca zero no lugar de "não sei".

| Motivo | Frase | Botão |
|---|---|---|
| Sem conversas no período | "{nome} não atendeu ninguém neste período." | "Ver outro período" |
| Leitura desligada | "Ligue a leitura das conversas para ver do que as pessoas falam." | "Ligar" (só admin) |
| Lendo pela primeira vez | "Estamos lendo as conversas dos últimos 30 dias. Os assuntos aparecem em algumas horas." | "Ver o que já temos" |
| Teto do mês atingido | "A leitura parou este mês. As conversas novas ficam para o mês que vem." | "Ver o que já temos" |
| Conta sem IA disponível | "A leitura não está funcionando nesta conta agora. Já avisamos a equipe." | "Ver os números" |
| Resultado principal não definido | "Diga o que conta como resultado para {nome}." | "Dizer agora" |
| Conferência abaixo do aceitável | faixa: "Os assuntos podem estar imprecisos. Estamos revisando." | — |

### 2.12 Agente de fora (webhook)

Sempre no topo: "Agente de outro sistema: só vemos o que ele manda."

**Sem instrução colada:**
- herói, bloco 3 (passagens por "pessoa assumiu" e motivo `n8n`, sem motivo
  interno), bloco 4, bloco 2 e bloco 5 funcionam;
- bloco 1 funciona, porque a leitura usa só a conversa; temas e marcos são
  sugeridos a partir das primeiras leituras;
- no lugar de "seguiu a instrução?": cartão "Cole a instrução de {nome} para
  ver se ele faz o que deveria." Botão: "Colar a instrução" (só
  `autonomia_manage`).

**Com instrução colada:**
- etiqueta "Instrução colada por {autor} em {data} · Alterar", deixando claro
  que é o que foi colado, não necessariamente o que o outro sistema usa;
- passa a valer "seguiu a instrução?" e os marcos tirados dela;
- o trecho mostrado é a regra curta extraída pela IA, nunca o texto bruto.

**O que nunca teremos dele:** confiança, custo e motivo interno da passagem.
O bloco 7 diz isso.

---

## 3. Métricas universais × temas e marcos que nascem da instrução

### 3.1 Universais (banco, sem IA, qualquer ramo)

Todas saem do mesmo universo da `Autonomia::ContaDaIa`, estendido para o
"sujeito" do painel (agente nosso ou robô de fora, seção 7.3). A aba
Desempenho antiga (`Autonomia::Agents::Analytics`) deixa de alimentar números
de tela: ritmo, motivos e silêncios passam a ser calculados sobre o universo
da `ContaDaIa`. Da `Analytics` sobra só o que é de evento (confiança, uso da
base), fora da tela principal.

1. Conversas atendidas.
2. Passadas para a equipe, com motivo.
3. Resolvidas sem a equipe.
4. Depois da passagem: tempo até a primeira resposta humana; sem resposta da
   equipe em X horas.
5. Ritmo diário e faixas de horário, no fuso da conta.
6. Tempo de resposta do agente (calculado no rollup, seção 4.5).
7. Marcos do sistema: reunião marcada pela IA (`crm_meetings.source='ai'`),
   cotação concluída (`autonomia_agent_tool_runs`, slug da ferramenta), card
   em etapa de venda ou de perda, com `value_cents`.
8. Conversas com origem de anúncio.
9. Custo do agente (total, por conversa, por resultado) — só com
   `financial_view`, só desde a data em que o custo passou a ser gravado com
   o agente.

### 3.2 Ficha do agente: temas, marcos e detalhes saídos da instrução

Não existe lista fixa de palavras. Quem interpreta é a IA, sempre com a saída
"não se aplica".

**Marcos** (o que conta como resultado neste negócio):
- Ao ligar a leitura e quando o hash da instrução muda, um modelo forte lê
  **só a instrução, a lista de ferramentas e a base** (nada de conversa crua)
  e propõe de 3 a 8 marcos em palavras do negócio, com um marco principal.
- O admin confirma numa tela só, com no máximo 3 marcos visíveis e "Alterar"
  em cada um. É a única confirmação obrigatória, e o painel funciona sem ela
  (só os números universais e a frase "Ainda não sabemos quantas viraram
  negócio").
- **Id estável:** marco é criado ou aposentado só com o admin. Quando a
  instrução muda, a IA propõe o mapeamento do marco antigo para o novo
  ("cotou" continua sendo o mesmo marco). Série histórica não quebra.
- **Prova:** quando existe marco do sistema equivalente (reunião, cotação,
  card), o marco lido pela IA é conferido contra ele. Sem registro, o marco
  aparece como "dito na conversa", nunca como "comprovado".

**Detalhes do pedido** (2 a 4 por agente): saem da instrução junto com os
marcos (destino, peça, cidade, especialidade, valor citado). Cada um admite
"não se aplica".

**Temas:**
- Não se lê amostra crua para criar o catálogo. As primeiras 100 leituras
  saem com "tema novo sugerido"; um passo de agrupamento (modelo forte, só
  sobre os nomes e descrições sugeridos, sem texto de conversa) monta o
  catálogo inicial de 8 a 15 temas.
- Depois, cada leitura aponta para um tema do catálogo, sugere um novo ou diz
  "não se aplica".
- Uma vez por semana, a fusão junta temas parecidos. O tema absorvido vira
  apelido; o catálogo tem retrato por versão; a tela avisa "Inclui 2 assuntos
  unidos em DD/MM".
- **Sinal de encaixe forçado:** medimos por semana a fração de "não se aplica"
  e de "tema novo". Se cair perto de zero, a leitura está forçando o encaixe
  e o catálogo é revisto.

**Listas universais curtas** (intenção, tipo de atrito, desfecho dito): sempre
com `outro` e `nao_se_aplica`. A ficha do agente pode acrescentar tipos
próprios. Se `outro` passar de 30% numa conta, é sinal de que a lista não
serve àquele ramo e a ficha propõe tipos novos ao admin.

**Todo valor de lista tem frase i18n** (en e pt_BR) e um teste falha se faltar.
`parou_no_meio` nunca aparece na tela; aparece "Parou no meio do caminho".

---

## 4. Arquitetura de leitura eficiente

### 4.1 Princípio

A IA lê cada conversa **uma vez**, quando ela esfria, e guarda uma ficha
curta. O painel só soma no banco. O Guia lê agregados. Ninguém lê texto ao
abrir a tela.

### 4.2 Gatilho

- Job a cada hora, por conta, **agrupado por agente** (aproveita o cache do
  prompt com a instrução).
- Candidatas: conversas com `last_activity_at` nas últimas 24h (nunca
  varredura), que estão resolvidas ou sem mensagem há 6 horas, e cuja ficha
  vigente tem `lida_em < last_activity_at`.
- **Sem IA** (ficha mínima, "não se aplica"): conversa com menos de 2
  mensagens do contato; conversa marcada "não é negócio" (`nao_e_negocio.rb`).
  Ambas são **contadas** como excluídas, com motivo.
- Reaberta: a IA recebe a ficha anterior e só as mensagens novas. Mais de 40
  novas: relê inteira.
- Conversa longa demais: corte por tamanho, ficha marcada "lida em parte".

### 4.3 Ficha (schema)

Tabela `autonomia_conversa_leituras`. Só a versão vigente é mantida (a
anterior é apagada no upsert).

```
account_id, sujeito_type ('agente' | 'robo'), sujeito_id,
conversation_id, inbox_id, contact_id
lida_ate_message_id, lida_em, versao_leitura, versao_ficha_agente,
instrucao_hash, modelo, custo_usd (também em crm_ai_usage_events)
status: lida | lida_em_parte | minima | nao_lida
motivo_nao_lida: viva | teto | esquema | midia | curta | nao_e_negocio | null
sensivel: bool                      # decidido pela IA, com "não se aplica"
dados (jsonb, validado por esquema):
  aplica: bool, motivo_nao_aplica
  intencao: comprar | tirar_duvida | pos_venda | reclamar | outro | nao_se_aplica
            (+ tipos próprios da ficha do agente)
  temas: [{tema_id, principal: bool, prova_message_id}]
  tema_novo_sugerido: {nome, descricao} | null      # sem dado pessoal (4.7)
  detalhes: [{detalhe_id, valor_curto | nao_se_aplica, prova_message_id}]
  marcos_ditos: [{marco_id, alcancou: bool, prova_message_id}]
  atritos: [{tipo, resumo ≤120 sem dado pessoal, prova_message_id}]
  agente_nao_soube: [{tema_id, prova_message_id}]
  desfecho_dito: avancou | parou_no_meio | sem_retorno_do_contato
                 | passou_para_equipe | nao_se_aplica
  seguiu_instrucao: {avaliado: bool, desvios: [{regra_curta, prova_message_id}]}
conferencia_modelo: {campo: concorda|discorda} | null
conferencia_pessoa: {certo|corrigido, por_user_id, em} | null
```

Decisões:
- **A prova é o `message_id`**, nunca o texto. A frase é buscada na hora de
  mostrar, sempre por `ContaDaIa.visiveis(user:).joins(:messages)`, nunca com
  `Message.find`. Mensagem apagada some da tela e invalida a ficha.
- **Desfecho de negócio não é guardado**: a ficha guarda só o que a conversa
  disse. Venda, reunião e card são cruzados na consulta.
- **Sem `confianca_da_leitura`**: nota que o modelo dá a si mesmo não é
  calibrada e viraria falsa precisão.
- Índice único `(account_id, conversation_id)`; upsert; lock por conversa;
  chave do job = conversa + `lida_ate_message_id`; ficha fora do esquema não
  é gravada, volta à fila no máximo 2 vezes e depois fica `nao_lida` com
  motivo `esquema`.

### 4.4 Modelo e custo estimado

- **Leitura:** modelo leve que o CRM já usa (`gpt-6-luna`), saída em formato
  fixo, raciocínio `low` ou `medium` (medido no piloto; `high` só se a
  conferência mostrar perda).
- **Modo em lote (-50%) já no job de cada hora:** a conversa esfriou, a demora
  não importa. Exige estender `app/services/crm/ai/pricing.rb`, que hoje não
  cobre lote.
- **Conferência:** modelo forte (`gpt-6.1-sol`), às cegas, só nos campos
  conferidos (tema principal, marco dito, desfecho dito), saída curta.
- **Feature de custo própria:** `painel_leitura` e `painel_conferencia` em
  `crm_ai_usage_events`, com agente e conversa preenchidos.

**Estimativa (hipótese, não medida), por 1.000 conversas lidas:**

| Item | Conta | US$ |
|---|---|---|
| Leitura (≈3,5 mil entrada nova + 2,5 mil em cache + ≈1 mil saída com raciocínio baixo) | 3,5k×0,10 + 2,5k×0,01 + 1k×0,50 por milhão, com lote −50% | ≈ 0,45 |
| Mesma leitura sem lote e com raciocínio alto (pior caso) | 3,5k×0,10 + 2,5k×0,01 + 2,1k×0,50 | ≈ 1,40 |
| Releituras (≈30% reabrem, só mensagens novas) | | ≈ 0,10 a 0,30 |
| Conferência: 50 por agente por período, não 5% | 50 × (6k×2,0 + 0,5k×10) por milhão | ≈ 0,85 por agente/mês |
| Catálogo, fusão e recomendações semanais | fixo por agente | ≈ 0,30 a 1,00 por agente/mês |

Ordem de grandeza: **US$ 1,5 a 3,5 por mês para um agente com 1.000
conversas**. Conversa de 150+ mensagens custa 3 a 5 vezes a média. Nenhum
número é publicado ao cliente antes do SQL de 90 dias e de duas semanas de
piloto pago com teto (pergunta 5).

### 4.5 Agregação SQL

**Rollup diário** `autonomia_desempenho_diario` (não visão materializada,
porque o `REFRESH` seria de todas as contas):

- chave: `(account_id, sujeito_type, sujeito_id, inbox_id, dia_local, hora_local)`;
- contagens: entradas, atendidas, passadas por motivo, resolvidas sem a
  equipe, sem resposta da equipe em X horas, soma e contagem de tempo da
  primeira resposta do agente (primeira entrada → primeira saída do robô),
  soma e contagem de tempo até a primeira resposta humana após a passagem;
- `inbox_id` na chave permite filtrar pelo que a pessoa vê sem voltar a
  `messages`;
- job horário incremental; backfill de 90 dias em fila baixa;
- o painel de operação lê só essa tabela.

**Temas e marcos:** soma direta de `autonomia_conversa_leituras` com índices
`(account_id, sujeito_type, sujeito_id, lida_em)` e GIN em `dados->'temas'`
(ou tabela filha `autonomia_leitura_temas` com `(account_id, tema_id)`, se o
plano de execução pedir; decidir no PR com `EXPLAIN`).

Esboço da consulta de temas (escopo já filtrado por caixa visível):

```sql
SELECT coalesce(t.apelido_de, t.id) AS tema, count(*) AS conversas,
       count(DISTINCT l.contact_id) AS pessoas,
       count(*) FILTER (WHERE m.alcancou) AS chegaram_ao_marco
FROM autonomia_conversa_leituras l
JOIN LATERAL jsonb_to_recordset(l.dados->'temas') AS x(tema_id int, principal bool) ON x.principal
JOIN autonomia_temas t ON t.id = x.tema_id AND t.account_id = l.account_id
LEFT JOIN LATERAL (...) m ON true          -- marco principal dito ou do sistema
WHERE l.account_id = :conta AND l.sujeito_type = :tipo AND l.sujeito_id = :id
  AND l.inbox_id = ANY(:caixas_visiveis) AND l.lida_em BETWEEN :de AND :ate
GROUP BY 1;
```

**Recorrência:** mesmo contato, mesmo tema, em sessões separadas por mais de
24h (não por `conversation_id`, que depende de a caixa reabrir ou criar
conversa nova).

**Anúncio:** `crm_meta_ad_links` (primeiro toque) × leituras ×
`crm_meta_ad_insights_daily` por `(account_id, ad_id, date)`.

**Porcentagens:** base = conversas lidas; a tela mostra junto a cobertura por
motivo. Com leitura por amostra, ponderar pelo inverso da chance de sorteio;
sem peso confiável, não mostrar porcentagem.

### 4.6 Recomendações (bloco 6) com cache

- Uma vez por semana por sujeito, no fuso da conta. Entram só agregados e até
  5 `message_id` por tema.
- Saída estruturada: `{tipo, texto, metricas_citadas: [{metrica_id, valor}], pronto}`.
- **Trava contra número inventado:** cada `metrica_id` é conferido no código
  contra o agregado; número que não bate derruba a recomendação.
- Tema com menos de 30 conversas não entra; no máximo 4 cartões.
- Cache em `autonomia_recomendacoes` com chave `account_id + sujeito +
  hash_dos_agregados` (os agregados de conta inteira; o cartão é escondido
  na tela se citar conversa que a pessoa não vê).
- Recomendações suspensas quando a conferência fica abaixo do aceitável
  (4.7).

### 4.7 Confiança

1. **Cobertura por motivo:** "Lemos 412 de 450. Faltam 20 em andamento, 12
   de áudio sem transcrição, 6 cortadas pelo teto." Conversas excluídas
   (curtas, não é negócio) são contadas à parte.
2. **Acerto medido por pessoa (o único selo de "acerto"):** conjunto de
   referência de cerca de 60 conversas por agente no piloto, marcado por
   nós, repetido a cada nova `versao_leitura`. Para o cliente, uma tela
   opcional "Conferir 10 leituras" dentro da lista de conversas; o número só
   aparece com 20 ou mais conferidas, sempre com o n.
3. **Concordância entre leituras (não é acerto):** 50 conversas por agente
   por período, sorteadas por semana e por desfecho dito, relidas às cegas
   pelo modelo forte. Medida **campo a campo**. Na tela: "Duas leituras
   concordam em 9 de cada 10 no assunto", nunca "acerto".
4. **Alarme:** intervalo de Wilson; aviso e suspensão das recomendações só
   quando o limite superior fica abaixo de 80%. Com menos de 30 conferidas:
   "conferência insuficiente", sem número.
5. **Conferência com os números de operação:** se a contagem do painel
   divergir da `ContaDaIa`, o bloco mostra aviso.
6. **Todo número abre as conversas que o compõem** (com nome e link onde a
   pessoa pode ver), e cada ficha mostra a mensagem de prova destacada.
7. **"O que o dado não prova"** (bloco 7).

### 4.8 "Como contamos" (o que abre do selo)

Frases curtas: quando lemos (conversa terminada ou parada há 6 horas), o que
fica de fora e por quê, como conferimos, o que a leitura não sabe. O custo
aparece aqui, só para `financial_view`.

### 4.9 Teto de custo

- Segue o padrão de cota que já existe (`Guide::Triagem`, `Tarefas::Jev`):
  soma mensal em `crm_ai_usage_events` pela feature `painel_*`. Sem tabela
  nova de teto.
- Teto padrão por conta: US$ 10/mês (ajustável).
- Ao chegar a 80% do teto: passa a ler **amostra estratificada** por agente e
  dia, e a tela diz "Lemos 3 de cada 10 conversas neste mês".
- Ao chegar no teto: para, e a tela diz (estado "Teto do mês atingido").

### 4.10 Backfill (passado)

- Ao ligar a leitura: lê os últimos 30 dias **por amostra igual por semana**
  (ex.: 20%), mostrando antes o custo estimado (contagem × custo médio).
  Assim o primeiro uso já tem conteúdo e a tendência não ganha degrau falso.
- "Completar a leitura" e "Ler 90 dias": só a pedido do admin, com custo
  mostrado antes.
- Fila de baixa prioridade, modo em lote.
- Instrução mudou: **não relê** o histórico. Temas continuam (saem da
  conversa); "seguiu a instrução?" compara com a instrução da época
  (`instrucao_hash`). Reler o passado é opcional, pelo mesmo botão.

---

## 5. Guia da Plataforma

### 5.1 O que lê

- `GET /api/v1/accounts/:account_id/desempenho/:sujeito_type/:sujeito_id/resumo?periodo=30`:
  o painel já somado, calculado **com a permissão de quem pergunta**
  (`Current.user`), nunca com cache compartilhado entre usuários. Traz
  operação, os 10 principais temas com detalhes, marcos, anúncios, grupos de
  retomada (nome e link só das caixas visíveis; nunca de tema sensível),
  recomendações, cobertura e conferência. Cada número com `metrica_id`.
  Custo só para `financial_view`.
- `.../tema/:tema_id`: detalhe de um tema (até 20 conversas visíveis, com
  link).
- Entra no `ler_da_conta` sozinho, por `Rotas.recurso`, herdando as
  permissões. O limite real é o do `Guide::Resumo`
  (`app/services/autonomia/guide/resumo.rb:17-35`: 100 itens, 100.000
  caracteres no todo, 5.000 por item, 2.000 por campo). Não existe "teto de
  6.000"; o resumo é projetado para caber nesses limites.
- Regerar `bundle exec rails autonomia:guia:formatos` e `pnpm guia:build`;
  bloco novo em `lib/operator_guide/porques.md`.

### 5.2 Perguntas prontas

Um chip por bloco (o do bloco 6 em destaque). Abre o Guia com a pergunta e o
contexto (sujeito, período, bloco). Lista no item 2.

### 5.3 Limites

- **Trava de número:** todo número citado pelo Guia sobre o painel precisa de
  `metrica_id` e é conferido contra o resumo; frase com número que não bate
  sai da resposta.
- A resposta termina com **uma** ação e cita de onde veio o número.
- Tema com menos de 20 conversas não entra em ranking nem em conselho.
- "Se o painel não tem o dado, diga que não tem. Não estime." O Guia não
  abre conversa crua para responder sobre o painel; para exemplo, dá o link.
- **Vigia sobre desempenho** avisa só o próprio criador. O `Pulso` confere de
  novo `desempenho_view` e as caixas do criador antes de cada execução.
- `guia-instrucao.md` (seção 3.3): proibir anotar lembrança tirada do painel
  (tema com nome, frase de cliente), como já vale para conversa de cliente.

---

## 6. Permissão e privacidade

### 6.1 Chave nova

- `desempenho_view` em `CustomRole::PERMISSIONS`
  (`enterprise/app/models/custom_role.rb`), com o checklist completo do
  `CLAUDE.md`: policy/controller, módulo em
  `settings/customRoles/permissionMatrix.js`, i18n `CUSTOM_ROLE.MATRIX` en e
  pt_BR, `meta.permissions` da rota, item de menu, spec em `spec/enterprise`.
  Não entra em `DELEGATION_KEYS`. No OSS, `permission_granted?` responde
  `administrator?`.
- **Controller próprio** com `check_module_permission!('desempenho')`, fora
  do `Autonomia::BaseController` (que exige `autonomia_view`). As duas chaves
  são independentes: uma não implica a outra.
- `desempenho_view` **não** dá direito de abrir conversa. Listas e frases
  passam por `Conversations::PermissionFilterService` com `for_reading: true`.
- Custo: exige também `financial_view`, inclusive no resumo do Guia.
- Retomada: exige também `campaign_manage`. Instrução colada: `autonomia_manage`.

### 6.2 Totais

- **Todo agregado sai do que a pessoa vê** (`ContaDaIa.visiveis(user:)`; o
  rollup tem `inbox_id` para isso). Admin, ou quem vê todas as caixas, recebe
  a conta inteira. Uma regra só, sem "você vê X de Y" e sem "1 conversa de
  outra caixa" (as duas revelam volume de caixa alheia).
- **Supressão de célula pequena:** todo cruzamento com menos de 5 conversas
  mostra "menos de 5", sem frase e sem link.
- **Corrigir agora** o `index` da `AnalyticsController`
  (`app/controllers/api/v1/accounts/autonomia/agents/analytics_controller.rb`),
  que hoje conta a conta inteira enquanto as listas filtram.
- Esta é a recomendação; a confirmação está na pergunta 1.

### 6.3 Identificação

Nome do contato, frase real e link: só de conversa visível, buscada via
`visiveis.joins(:messages)`. Sem exportação no primeiro corte; quando vier,
presa a `contact_export`.

### 6.4 Dado sensível (LGPD art. 11)

- Campo `sensivel` na ficha, decidido pela IA (saúde, gravidez, doença,
  religião, etc.), com "não se aplica", sem lista de palavras.
- Tema sensível: nunca entra em grupo de retomada nem campanha; aparece sem
  nome e sem frase; só para admin.
- Interruptor por conta "ler assuntos de saúde", **desligado por padrão** nos
  pacotes de saúde. O pacote da conta também pode desligar a frase real
  (deixando só o link).
- Base legal e item no relatório de impacto registrados em
  `docs/agentes/painel-desempenho/` (pergunta 3).

### 6.5 Texto livre que a IA escreve

`atritos.resumo`, `tema_novo_sugerido`, nomes de tema e `regra_curta`:
- o prompt proíbe dado pessoal;
- uma segunda checagem pela IA ("contém dado de pessoa? sim/não"), sem regex,
  antes de gravar;
- tema novo só aparece para não-admin depois que o admin confirma.

### 6.6 Finalidade

"Chamar de volta" vai ao fluxo de Campanhas existente, com `propor_acao` e
todas as regras de opt-in e janela do canal. Não existe público "pronto" que
pule essas regras.

### 6.7 Isolamento entre contas

`account_id` em toda tabela nova; todo índice único começa por `account_id`;
fusão de temas filtra por conta e sujeito; chave de cache com `account_id +
sujeito + escopo do usuário`; spec cruzando duas contas.

### 6.8 Instrução colada

Só `autonomia_manage` cola e vê. Aviso "Não cole senhas nem chaves". No
prompt, entra como dado delimitado (não como ordem). Na tela, só a regra
curta extraída. Versões guardadas com autor.

### 6.9 Exclusão e retenção

- Retenção = vida da conversa; só a versão vigente da ficha fica.
- Entram nas exclusões: `app/services/autonomia/exclusao_da_conta.rb`,
  `Crm::Cards::Anonimizador`, `Crm::ExclusaoDefinitiva`, excluidor de card
  (`app/services/crm/cards/excluidor.rb`), `Contacts::BulkDeleteService`
  (contato apagado leva as fichas), `ExclusaoDoUsuario` (autor da
  conferência), registro de conversa excluída.
- Tabelas: leituras, temas, marcos, detalhes, recomendações, instruções
  externas, rollup diário.
- Um spec por caminho de exclusão.

### 6.10 Repositório público

Nada de trecho real em spec, fixture, documento, print de protótipo ou PR.
Specs usam ids e textos inventados. Prints só da demo local com dados falsos.

---

## 7. Dados

### 7.1 O que já existe

(caminhos relativos à worktree)

| Dado | Onde |
|---|---|
| Regra única de contagem | `app/services/autonomia/conta_da_ia.rb:23-47, 95-98` |
| Espelho agente ↔ robô | `db/schema.rb:415` (`autonomia_agent_inboxes`) |
| Mensagens (índice remetente+data) | `db/schema.rb:3689, 3719` |
| Conversas | `db/schema.rb:1896`; `campaign_source_ids` em `:1928` |
| Eventos de relatório | `db/schema.rb:3841`; `app/listeners/reporting_event_listener.rb:30-87` |
| `first_response` só para humano | `app/models/message.rb:236` |
| Eventos do agente (20 tipos) | `db/schema.rb:374`; `app/models/autonomia/agents/agent_event.rb:74-90` |
| Motivos de passagem (15) | `app/services/autonomia/agents/operate/event_logger.rb:15-17` |
| Ferramentas demoradas (cotação) | `db/schema.rb:517`; `app/models/autonomia/agents/tool_run.rb:36-62` |
| Passagens | `db/schema.rb:2765`; `app/models/crm/passagem.rb:12, 43-45` |
| Cards, etapas, venda/perda | `db/schema.rb:2193, 2828, 2850` |
| Card ↔ conversa | `db/schema.rb:2174` |
| Reuniões da IA | `db/schema.rb:2468`; `app/services/autonomia/agents/tools/native/agendar_reuniao.rb:43,192` |
| Vínculo de anúncio | `db/schema.rb:2609`; `app/models/crm/meta_ad_link.rb:12-13` |
| Objetos e gasto de anúncio | `db/schema.rb:2628, 2586` |
| Consultor de anúncios | `db/schema.rb:2687, 2716`; `app/services/crm/meta_ads/advisor/facts.rb:1-3` |
| Custo de IA | `db/schema.rb:2080`; `app/services/crm/ai/usage_recorder.rb:7` |
| Endpoint atual | `app/services/autonomia/agents/analytics.rb:40-55`; controller `:51-55` |
| Resumo do Guia (limites) | `app/services/autonomia/guide/resumo.rb:17-35` |
| Permissões | `enterprise/app/models/custom_role.rb:50, 129-130` |
| Herói da página | `app/javascript/dashboard/routes/dashboard/autonomia/agentes/components/pagina/PaginaHeroi.vue:52` |

### 7.2 O que precisa gravar

1. **Custo por agente e conversa:** `UsageRecorder.record` ganha `agent_id`,
   `card_id`, `conversation_id` e preenche nas chamadas existentes. As
   colunas `agent_id` e `card_id` já existem
   (`db/migrate/20261106104214_add_memoria_refs_to_tool_runs_and_usage.rb`);
   falta `conversation_id` e o índice `(account_id, agent_id, created_at)`.
   Sem backfill possível: a tela diz "custo desde {data}".
2. **Sujeito do painel:** `ContaDaIa#por_robo(agent_bot_ids)` pelo
   `sender_id` e pelas passagens `de_type='AgentBot'` ou motivo `n8n`.
3. **Rollup diário** (4.5).
4. **Leituras, temas, marcos, detalhes** (4.3, 3.2).
5. **Recomendações** com cache (4.6).
6. **Instrução colada** com versões.
7. **Índice de marcos de ferramenta:** `(account_id, slug, created_at)` em
   `autonomia_agent_tool_runs`.
8. **Fila do job:** índice parcial em `conversations (account_id,
   last_activity_at)`.
9. **Ferramentas comuns** (agendar, CEP): contador no `metadata` do evento
   `replied` (fica para depois do primeiro corte; o bloco 7 diz que não
   medimos).

### 7.3 Migrations (rascunho; versão pedida à Orquestração antes de cada PR)

```
add_column :crm_ai_usage_events, :conversation_id, :bigint
add_index  :crm_ai_usage_events, [:account_id, :agent_id, :created_at]
add_index  :autonomia_agent_tool_runs, [:account_id, :slug, :created_at]
add_index  :conversations, [:account_id, :last_activity_at]  # avaliar parcial

create_table :autonomia_desempenho_diario  # chave (account_id, sujeito_type, sujeito_id, inbox_id, dia_local, hora_local) única
create_table :autonomia_agente_fichas      # account_id, sujeito, versao, instrucao_hash, confirmada_por, confirmada_em
create_table :autonomia_marcos             # account_id, sujeito, id estável, nome, principal, aposentado_em, mapeado_de
create_table :autonomia_detalhes_pedido    # account_id, sujeito, nome, ordem
create_table :autonomia_temas              # account_id, sujeito, nome, descricao, apelido_de, versao_catalogo, confirmado, sensivel
create_table :autonomia_conversa_leituras  # 4.3; único (account_id, conversation_id)
create_table :autonomia_recomendacoes      # account_id, sujeito, hash_agregados, cartoes jsonb, gerada_em
create_table :autonomia_instrucoes_externas # account_id, agent_bot_id, versao, texto, hash, autor_id
```

Migration só com a fila vazia, versão única entre PRs (regra da Orquestração).

---

## 8. Entregas

Tudo atrás de flag nova (posição pedida à Orquestração), ligada primeiro nas
contas piloto da stack hub2you. Um PR por fatia; nenhum PR mistura decisão
nova com fatia já aprovada.

### 8.0 Protótipo em tela real (o Rodrigo aprova antes de tudo)

- **O que é:** a página real `/autonomia/agentes/:id/desempenho`, com os
  componentes Vue de verdade, na worktree, rodando no painel local (kit
  `bin/demo`). Sem backend novo.
- **Dados:** adaptador trocável `desempenhoFonte.js`, sempre com o mesmo
  contrato v2: a demonstração (`desempenhoDemo.json` e
  `desempenhoDemoPeriodos.json`, uma loja inventada, sem nada de cliente),
  a vida real (`public/desempenho-vida-real.json`, gerado fora do
  repositório e nunca versionado; só é lido com `?fonte=vida_real`, e a falha
  de leitura aparece como aviso na tela) e, depois, a API. O interruptor de
  demonstração só aparece em desenvolvimento ou quando o endereço já escolheu
  a fonte; quando a fonte é a demonstração, a tela avisa que os dados são
  inventados. Os nomes de marcos, temas e motivos vêm dos dados, nunca do
  código, para provar que o texto não tem nicho.
- **Entra no protótipo:**
  - link "Ver tudo de {nome}" no `AgenteSemana.vue`;
  - `DesempenhoPage.vue` com `PaginaHeroi.vue` reaproveitado, frase do
    período, ação principal, 4 números, selo de confiança e "Como contamos";
  - `BlocoMoldura.vue` e os blocos 1 a 7 com os textos desta especificação;
  - `EstadoDoPainel.vue` com todas as variantes da tabela 2.11 navegáveis;
  - agente de fora, com e sem instrução colada;
  - celular (360 px) e tema escuro;
  - os chips do Guia abrindo o Guia com a pergunta (resposta ainda falsa);
  - a lista "Ver as conversas" com nomes inventados e "menos de 5";
  - a tela de confirmação dos marcos.
- **Não entra:** banco, job, IA, permissão nova (a rota usa a permissão do
  agente só na demo).
- Conferência visual por mim antes de entregar (prints da demo local, só com
  dados falsos).

### 8.1 Ordem dos PRs

| PR | Conteúdo | Usa IA? |
|---|---|---|
| 1 | Protótipo (8.0), atrás da flag | não |
| 2 | Chave `desempenho_view` + controller próprio + correção do `index` atual para os visíveis | não |
| 3 | `UsageRecorder` com agente, card e conversa + migration + índice | não |
| 4 | Sujeito (`por_robo`) + rollup diário + backfill + endpoint de operação + blocos 3 e 4 reais + herói com números universais + resumo do Guia + `porques.md` + formatos | não |
| 5 | Ficha do agente (marcos, detalhes) + tela de confirmação + tabelas de leitura e temas + job + esquema + exclusões + teto + cobertura por motivo (piloto, flag) | sim |
| 6 | Bloco 1 real + selo de confiança + conferência (concordância, conjunto de referência) + bloco 7 dinâmico | sim |
| 7 | Issue do Instagram Direct resolvida ou registrada + bloco 2 + fato novo no consultor de anúncios (só tema com n ≥ 20 e concordância acima do limite) | não |
| 8 | Bloco 5 + bloco 6 com recomendações, trava de `metrica_id`, retomada pelo fluxo de Campanhas | sim |
| 9 | Instrução colada do agente de fora + "seguiu a instrução?" + conferência por pessoa opcional | sim |

Cada PR: specs locais antes do push, revisor independente, `pnpm guia:check`,
`autonomia:guia:formatos:check`, i18n en+pt_BR, OK de merge do Rodrigo.
Recomendações (PR 8) só ligam depois de 2 semanas de conferência no piloto.

---

## 9. Perguntas que só o Rodrigo decide

**1. Totais: do que a pessoa vê ou da conta inteira?**
- Contexto: as três propostas divergiam; dois revisores mostraram que total
  da conta vaza volume de caixa alheia (e, com tema, pode identificar
  pessoa). Hoje a página já mistura os dois critérios.
- (a) Do que a pessoa vê; admin vê a conta. Coerente com as listas, não
  vaza. Quem vê só uma caixa vê um painel menor.
- (b) Conta inteira para todos, com listas filtradas. Visão completa;
  vaza volume e pode expor tema sensível.
- (c) Conta inteira com "você vê X de Y". Transparente, mas revela Y.
- **Recomendo (a)**, com supressão abaixo de 5. É o que a especificação
  assume.

**2. Quem paga a leitura: chave do cliente ou nossa, com cota?**
- Contexto: o atendimento usa a chave do cliente quando configurada; Guia e
  decisores usam a nossa com cota. Uma stack está com a chave de assunto
  inválida desde 21/10.
- (a) Chave do cliente: custo dele; some quando a chave falta ou quebra.
- (b) Nossa, com teto de US$ 10/mês por conta: funciona igual em todas; custo
  nosso e nos torna operadora do tratamento (pergunta 3).
- (c) Nossa até um volume (ex.: 2.000 conversas/mês), do cliente acima.
- **Recomendo (b)** no piloto e decidir (c) com o custo medido.

**3. LGPD: base legal, provedor e conjunto de referência**
- Contexto: ler todas as conversas com IA (e reler parte com um segundo
  modelo) para inferir temas, inclusive de saúde, é tratamento novo. O
  conjunto de referência exige que alguém nosso leia ~60 conversas reais por
  agente piloto.
- (a) Recurso desligado por padrão; o admin liga com aviso; saúde desligada
  por padrão; termos e lista de suboperadores atualizados antes de ligar
  fora do piloto; referência marcada por nós só nas contas piloto, com OK.
- (b) Ligado por padrão no piloto, com os mesmos cuidados, e opt-in depois.
- (c) Só ligar após revisão jurídica completa.
- **Recomendo (a)**, com (b) apenas nas contas piloto já combinadas.

**4. Ao ligar a leitura, ler o passado automaticamente?**
- Contexto: sem passado, o dono vê "estamos lendo" por semanas; com passado
  completo, o custo dispara e o teto corta meses no meio.
- (a) Amostra de 20% por semana dos últimos 30 dias, automática, com custo
  mostrado antes; completar só a pedido.
- (b) 30 dias completos automáticos.
- (c) Nada; só daqui para frente.
- **Recomendo (a).**

**5. Medição em produção e piloto pago**
- Contexto: todo custo aqui é hipótese. O SQL de 90 dias (só leitura) foi rodado em 26/10;
  ver "Decisões do Rodrigo" no topo.
- (a) OK para rodar o SQL agora e um piloto pago de 2 semanas com teto de
  US$ 30 no total, nas contas piloto.
- (b) Só o SQL agora; piloto depois do protótipo aprovado.
- (c) Nada até o protótipo ser aprovado.
- **Recomendo (b)**: o SQL não custa nada e calibra o tamanho dos PRs 4 e 5.

---

## 10. Matriz: achado → como ficou

Legenda: B = BLOQUEIA, I = IMPORTANTE, M = MENOR. "Aceito" = resolvido como
o revisor pediu; "Ajustado" = resolvido de outro jeito; "Recusado" = com
motivo.

### Dono de negócio

| # | Nível | Achado | Como ficou |
|---|---|---|---|
| 1 | B | Veredito premia agente que perde cliente | Aceito: frase fala de marco e "parou no meio"; autonomia é secundária; sem marco, "ainda não sabemos" (2.3) |
| 2 | B | `certainty` errado; Instagram Direct sem vínculo | Aceito: visões por anúncio (`ad`,`ad_name`) e por campanha (+`campaign`); `unknown` à parte; Issue do Direct antes do PR 7 e aviso na tela (2.5) |
| 3 | B | Ficha congela desfecho | Aceito: ficha guarda só o dito; venda/reunião/card cruzados na consulta (4.3, 2.8) |
| 4 | B | Totais e Guia divergentes | Aceito: totais do que a pessoa vê; resumo do Guia com permissão de quem pergunta e com nome/link visível; pergunta 1 única (6.2, 5.1) |
| 5 | I | Tema grosso demais | Aceito: 2 a 4 "detalhes do pedido" por agente, da instrução (3.2, 2.4) |
| 6 | I | Falta o depois da passagem | Aceito: bloco 3 e decisão 5 (2.6) |
| 7 | I | Retomada impossível fora da janela | Aceito: cartão checa modelo aprovado, mostra custo, leva a Modelos (2.9) |
| 8 | I | "Acerto conferido" engana | Aceito: "duas leituras concordam" separado de acerto por pessoa com n ≥ 20 (4.7) |
| 9 | I | Primeiro uso vazio | Ajustado: amostra dos últimos 30 dias ao ligar, custo antes (4.10; pergunta 4) |
| 10 | I | Comparação enganosa | Aceito: só com cobertura ≥ 80% nos dois períodos e mesma ficha (2.3) |
| 11 | I | Padrão 7 dias | Aceito: padrão 30 dias (2.1) |
| 12 | I | Sem valor do negócio | Aceito: `value_cents` do card; "valor citado" como detalhe opcional; "não sabemos o valor" (3.1, 3.2) |
| 13 | M | Enfeites | Aceito: sem radar, sem "10%/40%", grade só ≥ 200 conversas, sem "mais ativos", custo fora do selo |
| 14 | M | Recomendações semanais | Aceito: trava de `metrica_id`, máximo 4, "nada novo esta semana" (4.6) |
| 15 | M | Listas fixas na ficha | Aceito: lista curta + `outro` + tipos próprios do agente (3.2) |
| 16 | M | Clínica, dado de saúde | Aceito: `sensivel` + pacote desliga frase real (6.4) |

### UX QI 70

| # | Nível | Achado | Como ficou |
|---|---|---|---|
| 1 | B | Muitas ações sem uma principal | Aceito: uma ação no herói; blocos só com "Ver as conversas"; ações no bloco 6 (2.2) |
| 2 | B | Radar | Aceito: lista com barra e "volta a aparecer" (2.4) |
| 3 | B | Tabela de 5 colunas | Aceito: cartão por anúncio com frase, máximo 3 (2.5) |
| 4 | B | Selo em jargão | Aceito: uma frase, custo fora, amostra como "3 de cada 10" (2.3) |
| 5 | B | Vocabulário do esquema na tela | Aceito: frase i18n por valor + teste que falha se faltar; "marco" nunca aparece (3.2) |
| 6 | I | Mapa 7×24 | Aceito: frase + 3 faixas; grade atrás de "Ver todos os horários" com `aria-label` (2.7) |
| 7 | I | Botão fixo no celular | Aceito: no fluxo, nada fixo (2.3) |
| 8 | I | Herói escuro diferente | Ajustado: conferido que `PaginaHeroi.vue` já usa `#0D2344`; reaproveitamos ele (2.3) |
| 9 | I | Veredito julga com limite escondido | Aceito: descreve; cor só com meta do admin (2.3) |
| 10 | I | Ação sem fim de jornada | Aceito: volta com faixa "Feito" e cartão marcado (2.9) |
| 11 | I | Aprovação da ficha como parede | Aceito: painel funciona sem; só marcos confirmados numa tela com 3 visíveis; temas "Sugerido · Alterar" (3.2) |
| 12 | I | Período como 1ª decisão | Aceito: "Últimos 30 dias · Alterar" (2.3) |
| 13 | I | "1 conversa de outra caixa" | Ajustado: removida junto com "X de Y", porque os totais já são do que a pessoa vê (6.2) |
| 14 | M | Setas e símbolos | Aceito: `aria-label` com a frase, barra `aria-hidden` (2.2) |
| 15 | M | Linha de mudança no gráfico | Aceito: aviso em texto (2.7) |
| 16 | M | Estados vazios | Aceito: `EstadoDoPainel.vue` com variantes e teste (2.11) |
| 17 | M | Chips demais | Aceito: um por bloco, o do bloco 6 em destaque (2.2) |

### Custo e confiança

| # | Nível | Achado | Como ficou |
|---|---|---|---|
| 1 | B | Concordância ≠ acerto | Aceito: conjunto de referência por pessoa; concordância campo a campo, rotulada como tal (4.7) |
| 2 | B | 5% e 80% são ruído | Aceito: 50 fixas por agente/período, estratificadas; Wilson; "conferência insuficiente" (4.7) |
| 3 | B | Não lidas não são aleatórias | Aceito: `motivo_nao_lida`, cobertura por motivo, peso inverso ou sem porcentagem (4.3, 4.5, 4.7) |
| 4 | B | Custo por tema inventado | Aceito: removido; custo só por resultado do anúncio (2.5) |
| 5 | I | Nível de `certainty` | Aceito: duas visões (2.5) |
| 6 | I | Tema direto ao consultor | Aceito: só com n ≥ 20 e concordância acima do limite, com n e intervalo (PR 7) |
| 7 | I | Recorrência depende da caixa | Aceito: por contato e sessões separadas por > 24h (4.5) |
| 8 | I | `confianca_da_leitura` | Aceito: retirado do esquema (4.3) |
| 9 | I | 30 conversas cruas | Aceito: marcos só da instrução; temas das 100 primeiras fichas (3.2) |
| 10 | I | Marcos quebram série | Aceito: id estável, mapeamento, admin cria/aposenta (3.2) |
| 11 | I | Fusão muda passado | Aceito: retrato por versão, aviso "inclui 2 assuntos unidos", monitor de "não se aplica"/"tema novo" (3.2) |
| 12 | I | Custo subestimado | Aceito: raciocínio baixo/médio, job por agente, lote no job horário, conferência curta; estimativa refeita como hipótese (4.4) |
| 13 | I | Backfill corta tendência | Aceito: amostra igual por semana, completar a pedido (4.10) |
| 14 | I | Guia pode inventar | Aceito: trava de `metrica_id` no Guia, tema < 20 fora (5.3) |
| 15 | M | Listas fixas | Aceito: monitor de `outro` > 30% (3.2) |
| 16 | M | Frase sem forma de guardar | Aceito: `prova_message_id` (4.3) |

### Privacidade e acesso

| # | Nível | Achado | Como ficou |
|---|---|---|---|
| 1 | B | Totais da conta vazam | Aceito: agregados do visível, supressão < 5, sem linha fantasma (6.2; pergunta 1) |
| 2 | B | Resumo do Guia e vigias | Aceito: `Current.user`, sem cache entre usuários, vigia só ao criador, `Pulso` reconfere, regra em `guia-instrucao.md` (5.1, 5.3) |
| 3 | B | Dado sensível inferido | Aceito: `sensivel`, fora de audiência, só admin, saúde desligada por padrão, base legal (6.4; pergunta 3) |
| 4 | B | Finalidade de campanha | Aceito: fluxo de Campanhas com opt-in e janela, `campaign_manage`, sem exportação (6.6) |
| 5 | B | Texto livre com dado pessoal | Aceito: proibição no prompt + checagem pela IA sem regex + tema só após confirmação para não-admin + ficha invalidada se a prova some (6.5) |
| 6 | I | Exclusão e retenção | Aceito: todos os caminhos listados, só versão vigente, spec por caminho (6.9) |
| 7 | I | Chave mal amarrada | Aceito: controller próprio, chaves independentes, `index` corrigido, custo com `financial_view` também no Guia (6.1) |
| 8 | I | Chave nossa = operadora | Aceito: desligado por padrão, termos e suboperadores, passado só com OK (pergunta 3) |
| 9 | I | Isolamento no job e cache | Aceito: `account_id` em tudo, índices compostos, cache com escopo, spec de duas contas (6.7) |
| 10 | I | Instrução colada | Aceito: `autonomia_manage`, aviso, dado delimitado, regra curta na tela (6.8) |
| 11 | M | Frase buscada por id | Aceito: sempre via `visiveis.joins(:messages)` (4.3) |
| 12 | M | Prints e PRs | Aceito: só dados falsos da demo local (6.10) |

### Viabilidade de dados

| # | Nível | Achado | Como ficou |
|---|---|---|---|
| 1 | B | Duas contagens | Aceito: tudo no universo da `ContaDaIa`; `Analytics` sai da tela (3.1) |
| 2 | B | Agente de fora sem número | Aceito: sujeito `(tipo, id)`, `por_robo`, rota com origem, leituras com `sujeito_type` (7.2) |
| 3 | B | Sem tempo de primeira resposta do robô | Aceito: calculado no rollup; fora do herói (4.5, 2.7) |
| 4 | B | Custo por agente não existe | Aceito: PR 3 próprio, "custo desde {data}", nunca zero (7.2) |
| 5 | I | Mapa direto em `messages` | Aceito: rollup diário em fuso local, sem visão materializada (4.5) |
| 6 | I | Fila do job sem índice | Aceito: `last_activity_at` × `lida_em`, índice em conversations, janela de 24h (4.2) |
| 7 | I | Vínculo e várias linhas | Aceito: duas visões e primeiro toque (2.5) |
| 8 | I | Totais vazam | Aceito: igual a privacidade 1 (6.2) |
| 9 | I | "6.000" não existe | Aceito: limites reais do `Guide::Resumo` (5.1) |
| 10 | I | Custo é chute | Aceito: rotulado hipótese; SQL + piloto; cota pelo padrão existente (4.4, 4.9; pergunta 5) |
| 11 | I | Conferência humana cedo demais | Aceito: cliente confere opcionalmente, depois (PR 9); no piloto, referência marcada por nós (4.7) |
| 12 | I | Marcos com pouco registro | Aceito: índice em `tool_runs`; "dito na conversa" vs "comprovado" (3.2, 7.2) |
| 13 | M | `confianca_da_leitura` | Aceito: retirado |
| 14 | M | Códigos de motivo | Aceito: `curate_reason` + chaves i18n novas (2.6) |
| 15 | M | Enterprise e chave | Aceito: checklist completo, fora de `DELEGATION_KEYS` (6.1) |
| 16 | M | Excluir leituras e rollups | Aceito: (6.9) |

Nenhum achado BLOQUEIA ou IMPORTANTE foi recusado. Três foram ajustados:
UX 8 (o herói já é escuro, então reaproveitar resolve), UX 13 (a linha
fantasma some porque o total já é do visível) e Dono 9 (o passado é lido por
amostra, não completo, para não estourar o teto).
