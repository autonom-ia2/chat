# Causa raiz — rodada 2 de revisão do PRD de Agentes (05/10/2026)

Documento em revisão: `docs/agentes-ia-redesign/PRD.md` v2. Protocolo do PRD §10.3: a rodada 2 teve achados, então o trabalho
**parou** e a causa raiz de cada grupo foi encontrada antes de qualquer correção.

- Rodada 1: 60 achados (16 altos). Todos aplicados na v2.
- Rodada 2: 63 achados (16 altos, 32 médios, 15 baixos), dos quais ~10 repetidos entre lentes.
- Os 63 achados vêm de **5 causas**. Nenhuma é "faltou atenção" — cada uma é um passo de método que não existia.

## C1 — Controle decorativo: efeito real só foi checado onde alguém apontou

**Achados:** R2-28 (primeira mensagem e perguntas iniciais sem leitor), R2-29 (quando não souber responder só vale no caminho
com portão), R2-30/R2-45 ("Quando passa" na Lia sem efeito), R2-33 (horário em caixa sem horário = sempre), R2-36 (motivo da
"resposta errada" gravado e nunca lido), R2-38 (aviso da cotação sem campo), R2-47 (painel "já sabe" sem fonte), R2-35
(material aceito "fora do negócio" mostrado como pronto). Na análise da causa apareceram mais três, que nenhum revisor viu:
mídias "Para enviar" não são enviadas por nenhum código de atendimento (só o Construtor cita a lista); renomear o agente não
muda como ele se apresenta (o nome vive na instrução, `prompt_builder.rb` não usa `agent.name`); e "Para quem vai" só vale com
BE-06.

**Causa raiz:** o PRD foi escrito a partir do inventário do **frontend** (campos que a API aceita) e do protótipo (que simula
efeito no navegador). Em nenhum momento foi feito o caminho inverso, campo a campo: *quem lê este valor em tempo de
atendimento, em qual arquivo e linha, e o que muda*. A regra CA-GERAL-14 ("nada decorativo") existia, mas sem método para
cumpri-la; só pegou os casos que a pesquisa trouxe por acaso (régua de certeza, estratégia).

**Correção da causa:** o PRD ganha a **Matriz controle → leitor → efeito** (§6.5), com uma linha por controle do protótipo,
o leitor real (`arquivo:linha`) ou "nenhum", e a decisão para cada "nenhum". A lente de produto de toda revisão (do PRD e de
cada PR) passa a conferir a matriz linha a linha. Controle sem leitor não entra sem decisão registrada.

## C2 — Correção da rodada 1 criou defeito novo

**Achados:** R2-02/R2-32 (BE-23 grava versão guiada e o índice de versões expõe o texto em modo manual — vazamento da
instrução oculta que o controller apaga de propósito), R2-01/R2-49 (BE-25 filtrava só por caixa, mais fraco que o
`Conversations::PermissionFilterService` que o repo já usa), R2-03/R2-14/R2-54 (mudança de spec do BE-19 descrita errada),
R2-46/R2-13 (D15 exige teste, mas `ready` não considera a etapa e rascunhos antigos ficam sem saída), R2-50 (B3 sem depender
do B2), R2-12/R2-53 (motivo de passagem cru no Testar), R2-21 (`none` fora da garantia byte a byte), R2-41/R2-60 ("Automático"
impossível com a API atual).

**Causa raiz:** na rodada 1, cada correção foi aplicada a partir do texto sugerido pelo revisor, sem duas checagens que o
código exigia: (1) **invariantes de proteção** que a mudança toca (instrução oculta — NR-10; permissão de conversa —
`PermissionFilterService`; isolamento entre contas); (2) **efeito colateral** nos specs e fluxos vizinhos que a mudança
altera. O revisor da rodada 1 olhava uma lente; ninguém olhava o cruzamento.

**Correção da causa:** toda mudança de requisito passa a declarar, no próprio item, os invariantes que toca e como os preserva
(§7 ganha a coluna implícita "Invariantes" no texto de cada BE afetado), e o protocolo §10.3 ganha o passo **"conferir
invariantes"**: antes de reenviar para revisão, cada item alterado é checado contra a lista de invariantes do §9.

## C3 — Fluxo de criação sem modelo de estados real

**Achados:** R2-48 (a rota `build/:step` precisa do `agentId` antes de o rascunho existir), R2-46/R2-13 (`ready` × teste ×
rascunho antigo), R2-22 (rascunho vazio "fica guardado" mas é apagado), R2-47 (o painel "já sabe" supõe 4 respostas fixas,
o Construtor faz até 6 perguntas fora de ordem), CA-LISTA-06 com "Escolha" impossível.

**Causa raiz:** o protótipo guarda todo o estado no navegador (`S.build`), e o PRD descreveu as telas em cima dele. A sequência
real — conversa (thread) nasce antes do agente; o rascunho nasce na 1ª resposta ou na abertura com base; a instrução nasce no
fim do Conte; o teste é assíncrono e de leitura; o "no ar" é outra transação — nunca foi escrita. Sem ela, rotas, estados da
lista e critérios foram derivados da simulação.

**Correção da causa:** o PRD ganha a **Máquina de estados da criação** (§6.6): estados da thread e do agente, quem escreve
cada transição (endpoint e permissão), o que a lista mostra em cada estado e o que acontece com os registros antigos. Rotas
(§8), BE-03/BE-08/BE-14 e CA-LISTA/CA-CRIAR passam a ser derivados dela.

## C4 — Roteiro do tester sem aplicar a regra de produção linha a linha

**Achados:** R2-11 (T11/T15/T16 escrevem em agentes reais sem 🟢), R2-07/R2-17 (usuário só-ver e função personalizada são
escrita de permissão em produção, sem pré-requisito), R2-09/R2-15/R2-57 (T09 espera 200; é 202), R2-16 (T21 espera 201; é
200), R2-27 (T22 com 90 s; uma tentativa pode levar 180 s; config de produção que nenhum PR cria).

**Causa raiz:** a tabela foi escrita como lista de chamadas de API. A regra "escrita só em agente de teste, com 🟢" estava no
cabeçalho, não em cada linha; e os status HTTP foram escritos de memória, não lidos do controller.

**Correção da causa:** cada linha do tester ganha a coluna **Tipo** (leitura | escrita 🟢) e **Alvo** (id do agente de teste ou
"conta 16 só leitura"); status e tempos vêm do código, com `arquivo:linha` no próprio critério; pré-requisitos de escrita
(agente de teste, caixa de teste, usuário só-ver, função personalizada) listados com 🟢 e regra de BLOQUEADO.

## C5 — Sem passe de consistência depois de editar

**Achados:** R2-23/R2-42/R2-58 (§12 com D1–D11 e Q1–Q11; T24 com Q1–Q11), R2-59 (BE-24 fora de volta e riscos), R2-26/R2-40
("Ainda sem uso" fora da §6.4), R2-34 (botão de conectar WhatsApp para quem não é administrador), R2-43/R2-51 (B6 com dois
assuntos), R2-61 (`business_hours` sem tela), R2-44 (nome "Lia" fixo), R2-10/R2-25 (exceções de CA-GERAL-10), R2-24 (globs da
validação local), R2-37 (lista de telas do aceite visual), R2-39/R2-63 (estados e códigos do WhatsApp), R2-05/R2-62 (Q12
incompleta e aborto contra a foto errada), R2-55/R2-56 (alvo de passagem fora da caixa e convivência com o CRM).

**Causa raiz:** as edições da v2 foram feitas por trechos (substituições pontuais), sem uma passada final procurando cada
identificador alterado (D-n, BE-n, Q-n, T-n, nomes de campo) em todas as seções que o citam.

**Correção da causa:** o protocolo §10.3 ganha o passo **"passe de consistência"**: para cada identificador criado ou alterado,
buscar todas as menções no documento (e, nos PRs, no código e nos specs) e atualizar ou justificar; conferir que resumos
(§2, §12, §13, §14, Apêndice) refletem as tabelas.

## O que muda no processo (vale para o PRD e para cada PR do projeto)

1. Matriz controle → leitor → efeito conferida linha a linha pela lente de produto (C1).
2. Invariantes declarados e conferidos em toda mudança de requisito ou código (C2).
3. Fluxos com estado descritos como máquina de estados antes de rotas e telas (C3).
4. Tester com Tipo/Alvo por linha e valores lidos do código (C4).
5. Passe de consistência por identificador antes de reenviar para revisão (C5).

Os cinco passos entram no PRD (§10.3) e são aplicados na v3 antes da rodada 3.

---

# Rodada 3 (05/10/2026) — parou de novo

- 59 achados (17 altos, 25 médios, 17 baixos), ~15 repetidos entre lentes.
- Série das rodadas: 60 → 63 → 59; altos 16 → 16 → 17. **Não converge.**

## C6 — Os 5 passos foram aplicados às correções pedidas, não aos desenhos novos

**Achados:** R3-01/12/46 (`publish` exige etapa que ninguém grava; regra escrita de dois jeitos), R3-02/13/45 (nada dispara o
fechamento da instrução; o Construtor faz uma 5ª pergunta e trava em material com falha), R3-03/15/30/44 (`instruction_name`
não existe: o "Seu nome é…" entraria em todos os agentes no deploy), R3-04/14/37/52 (`out_of_scope` contradiz a salvaguarda
do retriever), R3-19/36/47 (`tested_at` nunca é invalidado), R3-08/20/59 (rascunho sem thread nunca liga), R3-31 (guarda de
modo manual só numa leitura), R3-51 (versões sem origem), R3-53 (NR-05 desatualizado de novo).

**Causa raiz:** na v3 eu criei mecanismos novos (máquina de estados com `tested_at`/etapa, BE-26–BE-31) a partir do texto dos
achados, sem passar esses desenhos pelos passos 2 e 3 (invariantes e máquina de estados conferida no código) — os passos
foram aplicados ao que os revisores apontaram, não ao que eu inventei. O passe de consistência (passo 5) cobriu §2/§12/§14,
mas não a tabela de NR.

## C7 — Altitude errada: o PRD especifica mecanismo interno que só estabiliza com código e teste

**Achados:** a maior parte dos altos das rodadas 2 e 3 está em detalhe de implementação do Construtor e do atendimento
(flags `force_close`/`no_materials`, chaves de `config`, ordem de guardas, hash de instrução, salvaguarda do retriever,
idempotência de nota). Cada correção abre um caso de borda novo um nível abaixo.

**Causa raiz:** o PRD tentou fixar o *como* de um pipeline complexo (Construtor com geração assíncrona, portões de material,
modo de ajuste; atendimento com portões e salvaguardas) apenas lendo o código, sem rodar nem testar. Esse nível de decisão só
converge quando é escrito com o código aberto e provado por teste — por PR.

**Correção da causa:**
1. O PRD fixa **comportamento, invariantes, critérios de aceite e decisões**. Cada BE passa a ter: regra de comportamento,
   invariantes que toca e a lista de **casos obrigatórios** (todos os achados técnicos das rodadas 2 e 3 viram casos dessa
   lista, com o ID do achado).
2. O **desenho técnico** (chaves, flags, endpoints exatos, ordem de guardas) vai para `docs/agentes-ia-redesign/design/<PR>.md`,
   escrito no PR com o código aberto, specs primeiro, e revisado pelo protocolo §10.3 (rodada 1; rodada 2 com achado → para e
   causa raiz). O PR só passa se cada caso obrigatório do BE tiver spec.
3. Os 5 passos de método valem também para todo desenho novo que o autor criar, não só para o que o revisor apontar.

---

# Rodada 4 (05/10/2026) — convergindo, parou de novo

- 46 achados (9 altos, 27 médios, 10 baixos). Série dos altos: 16 → 16 → 17 → **9**. A mudança de altitude (C7) funcionou:
  os achados agora são de comportamento, não de mecanismo.

## C8 — Máquina de estados só com um ator e só até ir ao ar

**Achados:** R4-02/13/26/35 (agente no ar vira "Falta terminar" quando a instrução muda; religar pausado sem regra), R4-01/27
(ligar sem teste por PATCH, Guia, API, criação da Lia), R4-15/36 (material terminado depois do teste invalida sem aviso),
R4-17/28/40/05 (voltar do manual para o guiado sem requisito), R4-39 (rascunho da API apagado com texto de "fica guardado"),
R4-14/38/09 (Testar do ajudante não é o caminho do ajudante), R4-37 (ajudante sem copiloto ligado na instalação).

**Causa raiz:** a §6.6 foi escrita a partir da jornada de uma pessoa na tela nova, do começo até ligar. Não listei **todos os
atores que mudam o estado ou a instrução** (a pessoa, o sistema — reescrita automática por material, `InstructionRefresher` —,
a tela antiga, o Guia, a API, a Cotação) nem os estados **depois** de ir ao ar.

**Correção da causa:** a §6.6 ganha a tabela "quem muda o quê" (ator × efeito em cada estado) e as regras de E5/E6. Toda
regra de estado passa a dizer para quais estados e quais atores vale.

## C9 — Ferramenta de edição deixou sobras

**Achados:** R4-06/16/34/42 (CA-LISTA-02, CA-LIG-12, CA-PTES-01, CA-AJU-03 com o texto novo seguido de pedaço do antigo).

**Causa raiz:** meu script de edição substituía a **primeira linha** de um critério que ocupa várias linhas; as linhas de
continuação ficavam.

**Correção da causa:** critérios passam a ser substituídos inteiros (do início do item até o próximo item), e o passe de
consistência ganha a busca de sobras (linhas de continuação órfãs e itens duplicados).

---

## Rodada 5 (05/10) — 43 achados (3 altos, 24 médios, 16 baixos)

Convergência: 60 → 63 → 59 → 46 → 43; altos 16 → 16 → 17 → 9 → 3. Pela regra, a rodada parou antes de corrigir.

**Onde caíram os achados:** 21 dos 43 estão nos mecanismos de produção que a própria rodada 4 criou (Q16, Q17,
evidência por id, tempo-limite de 12 min, T25, T26, volta). Outros 12 estão em regras novas (D23–D28) que não foram
cruzadas com todas as variantes de agente. Outros 7 são sobras entre seções.

### C10 — Validação de produção desenhada sem os dados, o código e o processo reais

- **Achado:** R5-03/23/24/25/26/33/34/35/36 e R5-19/27/29/30. A Q16 tem mínimo de 10 conversas em 2 h, mas a Clara tem
  3 em 7 dias. A Q17 trata como erro o administrador que o próprio BE-06 aceita. A evidência por id usa log de uma
  instância que o blue-green termina e janela que começa no deploy, não na foto. O tempo-limite de 12 min conta uma ida
  ao modelo, e há rodada + fechamento, e 6 rodadas na Lia. A T25 diz "nada recebido no meio P2", mas o Responder entrega
  a resposta antes de passar. A volta ignora o rollback de um degrau do `processo-de-release.md`.
- **Causa raiz:** o passo 4 do §10.3 pede valores "lidos do código" só para o tester. Para consulta, regra de aborto e
  volta, nenhum passo exige conferir o volume real (psql), o caminho do código até o fim, o processo de release nem a
  fonte da evidência depois da troca de instância. E regra de aborto não passava por análise de falso positivo:
  "uma ação legítima do cliente nesta janela dispara a volta?".
- **Correção da causa:**
  1. **Passo 6 novo no §10.3:** toda Q, regra de aborto, T e volta passa por 4 perguntas, com a resposta escrita:
     - (a) volume real lido por psql;
     - (b) caminho do código até o efeito observado;
     - (c) a fonte da evidência sobrevive ao blue-green?;
     - (d) o que dispara em falso com uso legítimo, e o que deixa passar com defeito.
  2. **Regra estrutural:** só aborta sozinho o que viola um invariante (Q2, Q5, Q6, Q8, Q11, Q17, Q4 sem resposta).
     Diferença de estado (Q1, Q7, Q10, Q12, Q13, Q15) **não** aborta sozinha: vira lista para decisão do Rodrigo,
     porque o cliente muda estado de propósito.
  3. **Comportamento ao vivo** (taxa de passagem, alvo, primeira mensagem) se prova no tester com afirmação dura,
     não por estatística de produção com volume baixo.

### C11 — Regra nova não cruzada com todas as variantes

- **Achado:** R5-01/02/15/16/17/22/28/32/13. Exemplos:
  - o Ligue edita nome e saudação depois do teste;
  - o ajudante interno mostra controles sem efeito;
  - o create ativo sem instrução fica aberto;
  - o rascunho manual sem instrução cai em E1, mas não tem Conte nem limpeza;
  - a retomada descarta `guardrails`;
  - `voice` vira só do Super Admin, mas é o Construtor que grava;
  - o D26 conflita com o D17.
- **Causa raiz:** a tabela de atores (C8) cobre **quem** muda. Mas cada regra foi escrita para o caso típico (externo
  guiado, criado pela tela nova). Ninguém a cruzou com as outras dimensões:
  - tipo de agente (externo, interno, os dois, cotação, sistema);
  - modo (guiado, manual);
  - porta de entrada (tela nova, tela antiga, Guia, API, Cotação, job);
  - campos que mudam o texto do modelo (instrução, nome, saudação, "quando não souber", tom, `guardrails`,
    "Quando passa").
- **Correção da causa:** o **passo 7 novo no §10.3** é a **matriz de variantes**. Toda regra nova, ou decisão, é
  conferida nas 5 × 2 × 6 combinações relevantes, e cada célula fica "vale", "não se aplica (motivo)" ou "decisão". A
  matriz fica no §6.7 do PRD.

### C12 — Passe de consistência feito de memória

- **Achado:** R5-14 (status do cabeçalho), R5-43 (BE-12 "PR próprio", B4b e B5 sem as Q e T novas, §13), R5-11 e
  R5-37 (lista de capturas e tester sem "vale a partir de").
- **Causa raiz:** o passo 5 virou "grep pelos termos de que eu lembrei". Os lugares de resumo (cabeçalho, §2, §10.1,
  §12, §13, §14, Apêndice) não têm lista fixa.
- **Correção da causa:** o passo 5 passa a ter **lista fixa** de lugares de resumo. Para cada ID criado ou mudado, o
  PRD registra onde ele aparece (D, BE, Q e T no §10.1 do PR que entrega, além dos lugares de resumo). O passe
  procura cada ID novo nessa lista.

---

## Rodada 6 (05/10) — 27 achados (5 altos, 16 médios, 6 baixos)

Convergência: 43 → 27. Pela regra, a rodada parou antes de corrigir.

**Onde caíram:** 17 dos 27 (e 4 dos 5 altos) estão de novo na validação de produção (§11.7 e §11.8):
- a Q4, a Q5 e a Q8 abortam com uso legítimo;
- os pacotes por deploy não acumulam;
- o P2 não define contato nem estado da conversa;
- a T25 depende da distribuição automática;
- a volta do B1 não relê o `.env`.

Os outros 10 são de comportamento de tela e backend (D29 × BE-30, `publish` com nome e saudação, ajudante interno,
andaime do legado, texto do motivo, reaper já corrigido pelo #1036).

### C13 — A validação de produção estava na altitude errada (é a C7 de novo, agora no §11)

- **Fato:** é a quarta rodada seguida (3, 4, 5 e 6) em que cada correção da §11.7/§11.8 abre furos novos no nível do
  código:
  - status de conversa, distribuição automática e lock de conversa do WAHA;
  - `.env` lido no boot e rollback por `start-instances`;
  - fila de merge que junta 2 PRs;
  - job que não limpa thread presa.
- **Causa raiz:** na rodada 3 (C7) eu tirei os mecanismos do BE do PRD, porque só estabilizam com o código aberto e com
  teste. Não apliquei a mesma regra à validação. Consulta SQL exata, ordem de cenários, contato de teste, prazo por
  agente e passo do rollback são mecanismos do mesmo tipo: dependem do código do PR, do volume do dia e do workflow de
  deploy vigente. Escritos no PRD, sem o código do PR, eles erram de novo a cada rodada. Os passos 6 e 7 da rodada 5
  pediam respostas por escrito, mas eu não registrei as respostas no documento, então não havia o que conferir (passo
  declarado não é passo feito).
- **Correção da causa:**
  1. O PRD (§11.7/§11.8) passa a fixar só o **contrato** da validação:
     - os invariantes em comportamento;
     - os princípios (só invariante aborta sozinho; diferença de estado vai para decisão; evidência do banco; janela a
       partir da foto; ausência com janela; afirmação dura);
     - a cobertura obrigatória por PR (o que cada deploy tem de provar em produção);
     - o núcleo que roda depois de todo deploy.
  2. As consultas e os cenários concretos vão para o **plano de validação do PR** (`design/<PR>.md`), escrito com o código
     do PR aberto, o volume lido por psql no dia e o workflow de deploy vigente. Ele leva por escrito as respostas 6(a–d)
     de cada Q e T e passa pelo protocolo §10.3 antes do merge.
  3. As tabelas atuais (Q1–Q17, T01–T31, P0–P5) viram o **ponto de partida** em `validacao-producao-base.md`, com os
     achados de validação das rodadas 5 e 6 anexados como **pendências obrigatórias**: cada plano de PR resolve as
     pendências que tocam o seu escopo.
- **O que não muda:** a regra de Rodrigo sobre tester (lista antes, motivo, afirmação dura, 18+ cenários, evidência)
  continua obrigatória; ela só deixa de ser escrita de antemão no PRD sem o código.

---

## Rodada 7 (05/10) — 28 achados (0 altos, 18 médios, 10 baixos)

Convergência: 27 → 28 em número, mas os altos caíram de 5 para 0. Pela regra, parou antes de corrigir.

**Onde caíram:**
- **Sobra da D31:** 4 lentes acharam a mesma. A D31 foi decidida, mas o BE-06 continuou mandando o funil do CRM respeitar o
  time (R7-02/07/14/23).
- **Invariantes I2, I3 e I6:** caem com estado legítimo ou anterior ao #1036 (espelho de pausado antigo, ajudante sem
  espelho, administrador troca o bot da caixa, chave gravada pelo Construtor), e isso dispararia volta automática
  (R7-09/10/15/16/20/21).
- **Lote misto** sem regra de volta (R7-17).
- **Teste válido** com três definições (R7-03/26).
- **Prova do BE-14** que depende de 48 h (R7-18/22).
- **Cobertura faltando** para BE-29, BE-31, BE-20 e D10 (R7-24/25/28).
- **Itens soltos:** sobras pontuais (R7-13) e casos de borda (R7-01/04/08/11/12/19/27).

### C14 — Passos de método declarados, sem registro de execução

- **Fato:** os passos 5 (consistência), 6 (perguntas da validação) e 7 (matriz de variantes) existem desde a rodada 5. Na
  rodada 6:
  - criei a D31 e não procurei o funil no resto do documento (passo 5);
  - escrevi I2, I3 e I6 sem responder por escrito "o que dispara em falso" (passo 6d).
  Os revisores acharam os dois.
- **Causa raiz:** os passos eram executados "de cabeça" no fim da edição, sem saída registrada. Sem registro, não há como
  eu nem o revisor ver que o passo foi pulado para um item. É a mesma lição da C13 ("passo declarado não é passo feito"),
  que eu registrei e não apliquei à edição seguinte.
- **Correção da causa:**
  1. **Registro de conferência** obrigatório no PRD (§15.1): para cada item criado ou alterado na rodada, uma linha com o
     resultado dos passos 5, 6 e 7 (onde o ID aparece; respostas a–d; células da matriz). Item sem linha não vai para
     revisão.
  2. **Invariantes do contrato:** as respostas 6(a–d) ficam escritas no próprio PRD, ao lado de cada I. Como são
     contrato, são do PRD, e não do plano do PR.
  3. **Regra estrutural** que elimina a classe de erro: todo invariante olha só o que **mudou depois da foto**; o estado
     anterior à foto é Estado (lista ao Rodrigo). Por construção, legado e estado antigo não disparam volta.

---

## Rodada 8 (05/10) — 28 achados (0 altos, 14 médios, 14 baixos)

Convergência: 28 → 28, com zero altos pela 2ª rodada. Pela regra, a rodada parou antes de corrigir.

**Onde caíram:**
- **Volta automática** (12 achados), que dispara em falso com uso legítimo:
  - I2 com conversa resolvida;
  - I4 com thread morta na troca de instância;
  - I5 com membro que saiu da caixa depois;
  - I6 com Seed do Guia e criação da Lia;
  - cenário que cai por indisponibilidade do provedor;
  - 401 × 404;
  - mudança que não é deploy (D10, Q12, flag).
- **Lacunas de comportamento** (16 achados), entre elas: trocar "Onde atua" e tirar material não invalidam o teste; não há
  fonte para o gênero da tela; "Nunca" promete passar quando a IA cai; restaurar versão manual; chaves `async_*`;
  compatibilidade do WAHA; avatar; conteúdo do registro do BE-31; "Ensinar" na Lia; textos de excluir; rascunho para quem
  só vê.

### C15 — Volta automática por regra mecânica

- **Fato:** desde a rodada 4, cada versão das regras de aborto (Q, depois I1–I6, depois "cenário falhou") ganha casos novos
  de falso positivo. Cada correção fecha alguns casos e expõe outros (rodadas 5, 6, 7 e 8).
- **Causa raiz:** eu quis que a volta fosse **sem julgamento**, para ser segura. Com isso, toda regra precisa prever **todo**
  estado legítimo do sistema (resolvida, adiada, seed, membro removido, provedor fora, conta alheia), e esse conjunto é
  aberto. A regra do Rodrigo (regra universal 3) não pede volta mecânica. Ela pede uma volta **pré-aprovada**, executada
  sem novo 🟢 **quando algo dá ruim**, o que pressupõe alguém que olha e decide.
- **Correção da causa:** violação de invariante ou cenário que falha **não** dispara volta sozinho. Dispara a
  **classificação**: o operador (tester ou sessão) usa a coluna (d) e o cenário repetido uma vez.
  - Defeito do lote → executa a volta pré-aprovada **na hora**, sem 🟢, e avisa.
  - Não é do lote (estado legítimo, provedor, ação de pessoa) → registra e lista ao Rodrigo.
  - Dúvida → volta, porque o lado seguro é voltar.

  Isso fecha a classe: a coluna (d) passa a orientar o julgamento, em vez de ter de ser exaustiva.

### C11 de novo — regra por lista enumerada

- **Fato:** a invalidação do teste foi escrita como **lista** de campos (instrução, nome, saudação, tom…). Cada rodada acha
  um campo que faltou ("Onde atua", tirar material).
- **Causa raiz:** lista enumerada de casos no lugar de uma regra pelo efeito.
- **Correção da causa:** regra pelo efeito. Invalida o teste toda mudança que altera **o que o agente responde ou por onde
  responde** (texto que o modelo lê, materiais que ele consulta, atuação). A lista vira exemplo, não fronteira.
