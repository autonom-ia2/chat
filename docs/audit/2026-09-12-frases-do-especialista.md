# As frases do especialista, e a fronteira de saída que as sustenta (#420)

Data: 12/09/2026 · Branch `feat/cotacao-frases-do-especialista` · base `origin/main` (`1e95a2b5c0`).

## Objetivo

As quatorze frases que o Agente de Cotação publica ao cliente durante uma cotação deixam de ser
constantes em Ruby e passam a ser **escritas pelo especialista de auto, no pedido** — parâmetros da
chamada de `cotar_seguro`, sem uma chamada de modelo a mais. Antes disso, a fronteira de saída que
essas frases atravessam foi consertada: ela descartava entregas inteiras e fazia o cliente perder
preço que a corretora já tinha pagado.

## Decisões do CEO aplicadas

- As frases que o código publicava passam a ser do especialista, escritas no pedido.
- Nenhuma frase ao cliente carrega número, contagem, valor, prazo ou nome de seguradora.
- `"Algumas seguradoras não responderam a tempo. Os preços acima são os que chegaram."` deixa de
  existir para o cliente. Nada foi acrescentado ao Super Admin.
- Continuam do código: valor em reais e período, nome da seguradora, molde do item, nome do arquivo,
  rótulos de campo e lista de ramos.
- Travessão sai do texto que chega ao cliente: **dois pontos** no item da lista (`• *Suhai*: R$
  2.358,84 no total`) e **vírgula** no nome do arquivo (`Comparativo de seguro, placa HIK9383.pdf`),
  porque o Windows recusa `:` em nome de arquivo e `EntregaDeArquivo::NOME_DE_PDF` só barra `/` e `\`.
- Sem regressão: todo estado que produzia palavra ao cliente continua produzindo.

## O que foi consertado, na ordem

### 1. A fronteira de saída (P1-1, P1-2, ordem de gravação, identidade)

| defeito | o que acontecia | conserto |
|---|---|---|
| P1-1 | `Progress` descartava a entrega inteira ao achar caminho de campo, e `build_progress` já tinha gravado `entregues`: as ofertas nunca mais eram reemitidas, `delivered_count` ficava zero e o cliente lia a frase de falha sobre dezessete seguradoras pagas | `Progress` passa a **redigir** e nunca descartar por conteúdo; `DELIVERED_KEY` sai de `build_progress` e é gravada em `precos`, sobre as ofertas que entraram no texto que vai sair |
| P1-2 | a mesma peneira devolvia nil para a entrega de arquivo com `PDF_SENT_KEY` já gravada: `comparison_pdf` devolvia nil para sempre | `fechar` põe a entrega na forma final (`Progress.entregavel`) e só então mescla as marcas |
| P2 (token) | o token nascia do texto CRU e o publicador o calculava sobre o texto aparado: `resultado_entregue?` nunca casava | `precos` e `fechar` depuram ANTES de calcular o token; `TextoAoCliente.depurar` é idempotente, então a segunda passada pelo `Progress` não muda o texto |
| P2 (aviso) | `AVISO_SENT_KEY` podia ser gravada sem o texto ter saído | a sentinela entra no mesmo merge do texto entregue |

A peneira antiga (`/\b[a-z][a-z0-9]*\.[a-z][a-zA-Z0-9]*\b/`) errava nos dois sentidos — cortava
`p.ex.`, `hub2you.ai`, `contato@corretora.com.br`; deixava passar `Já pedi.Aguarde` e `Ok.vou ver`.
A nova é **lista fechada**, derivada de `Parametros::GRUPOS` e `QuoteInput::GRUPOS_DE_AUTO`.

### 2. O nó das frases (P1-4)

`frases_ao_cliente`, objeto de 14 folhas, **nó e folhas obrigatórios, sem `null`** — a forma que a
medição aprovou. Medido neste repositório: 110 propriedades recursivas com o formulário de auto
inteiro, contra o teto de 5000 por função (2,2%).

A colisão de nome com um campo de RAIZ do adapter dá HTTP 400 na chamada inteira (`has non-unique
elements`) e o agente fica MUDO. Duas defesas: o nome em português com sublinhado, que o vocabulário
camelCase do adapter não produz, e a **falha dura em `Native::Base.objeto`** — que vale para a classe
do defeito, não para este nome (uma raiz nova chamada `vehicle` apagaria o grupo `vehicle` do mesmo
jeito).

### 3. O resolvedor

`Frases.de(arguments)` é função pura dos argumentos, total e determinística. Três garantias:

1. todo papel produz palavra (ausente, vazio, reprovado ou de tipo errado recuam para a constante);
2. os quatorze textos de uma execução são dois a dois distintos (a identidade de uma entrega é o SHA
   do texto num espaço por execução — duas iguais fariam a segunda ser lida como já publicada);
3. nunca levanta.

As aberturas de preço ganharam constante de recuo sem número (`Mais opções:` no lugar de
`"Mais #{quantas} opções:"`).

### 4. A morte da PARCIAL

O ESTADO continua falando: `Encerramento#parcial` publica `closing_message`
(`FECHO_COM_RESULTADO`) no lugar de `partial_message`. A constante `PARCIAL` **fica no código** e no
conjunto de perguntas do fecho: é o texto que a versão anterior publica, e sem ela o rollback poria
dois desfechos contraditórios na mesma conversa.

`insurance_quote_nenhum_estado_mudo_spec` percorre **todos os estados que produzem palavra**, sob as
quatro formas de o especialista não escrever (sem o nó, nó vazio, frases em branco, frases
reprovadas): 47 exemplos, nenhum estado mudo.

### 5. O fecho total (6a)

`fecho_publicado?` ganhou `rescue → false` ("não sei é publicar, nunca calar") e a resolução do texto
de cada papel (`Encerramento#frase`) recua para a constante de classe quando levanta.
`FRASES_DE_FECHO` passou a quatro papéis × duas formas cada (resolvida e constante).

### 6. Os dois manuais

- `especialista_auto.md`: §2.1 (as frases são suas, o que não entra nelas, cada uma sai sozinha),
  §2.2 (a pontuação), e a §6.5 ligada ao executor. md5 atualizado:
  `9cc4cffcba4a269acc61e29154ecc2b0` → `2e05afb8cbbc67671a48ed1325e54a3e`.
- `principal.md`: a regra de voz do travessão em §4 (fora dos blocos assinados por md5).
- A descrição do papel `espera` **não contradiz `ACEITA`** (P1-5): ela manda não afirmar um envio que
  ainda não aconteceu, e `ESPERANDO` deixou de dizer "estou consultando as seguradoras agora" — ela
  é publicada por `notify_start` ANTES de `tool.start`, que tem cinco caminhos de recusa.

## Decisões tomadas onde o desenho não fechou sozinho

1. **São 14 papéis, não 12 nem 13.** O desenho contou 13 papéis vivos e matou a `PARCIAL`; matá-la
   sem substituto deixaria mudo um estado que hoje fala, o que o CEO proibiu. O 14º é
   `fecho_com_resultado`.
2. **`AVISO_SEM_BONUS` perdeu o "(é um número de 0 a 10)".** Ela é a constante de RECUO do papel, e
   um recuo que publicasse dígito faria a regra valer para o modelo e não para nós. Custo: o cliente
   perde a dica de qual é a cara do dado na apólice.
3. **A peneira não tem a regra de nome de seguradora (regra 9 do desenho).** Não há fonte
   code-owned barata: o catálogo só existe dentro da conexão, e a peneira precisa ser PURA — a mesma
   frase é lida pela ferramenta (com conexão), pelo motor (sem) e pelo encerramento (sem agente).
   Vetar diferente em cada lugar daria textos diferentes para o mesmo papel, e a identidade de uma
   entrega É o texto. A regra fica no manual; a medição achou 0 nomes de seguradora em 96 frases.
4. **`depurar` redige só o caminho de campo pontuado, não o camelCase.** O texto final carrega o
   nome da seguradora vindo do portal, e uma marca como `eSeguros` seria mutilada. O camelCase
   continua sendo regra de `vetar`, que é onde o texto de fora entra.
5. **A prosa dos manuais continua usando travessão.** Só a REGRA foi acrescentada. A medição achou
   0 travessões em 96 frases geradas com o manual atual (que é cheio deles), e a peneira reprova de
   qualquer forma; reescrever um texto aprovado pelo PO por imitação não medida não se justifica.
6. **`QuoteOffers.describe` perdeu `first:` e ganhou `abertura:`.** Quem escolhe entre as três
   aberturas é quem conhece o lote (`InsuranceQuote#abertura_de_precos`); quem as escreve é o
   especialista. `describe` compõe.

## O que NÃO foi verificado

- **Nada foi exercitado contra o portal real nem contra a OpenAI.** As medições de schema e de
  aceitação da API são as da rodada anterior (documento de medição), não refeitas aqui.
- **O custo em tokens do nó de 14** não foi remedido: a medição aprovou 12 folhas a +353
  tokens/turno; 14 folhas acrescentam duas descrições curtas.
- **A lista de grupos da peneira não cobre grupo que exista só no `quote/schema` do adapter** e não
  em `Parametros::GRUPOS`. A folha camelCase desse grupo ainda reprova em `vetar`; um caminho
  `novogrupo.plate` passaria. Registrado no comentário de `TextoAoCliente::GRUPOS_DO_RAMO`.
- **`Answerer#enabled_agent_tools`**: com o especialista DESLIGADO, o slug volta ao principal e a Lia
  escreveria as frases sem ter o manual delas. Com este desenho isso degrada para a constante de
  recuo (a peneira vale para quem quer que escreva), não para vazamento — mas não foi exercitado.

## Validação

- `spec/services/autonomia`, `spec/jobs`, `spec/models/autonomia`: **1777 exemplos, 0 falhas**,
  5 pending (exit 0).
- `rubocop` com lista explícita (12 arquivos de app + 19 de spec): **0 offenses** (exit 0).
- `rails zeitwerk:check`: `All is good!` (exit 0).
- **15 mutações, 15 reprovadas** — cada correção desfeita derruba o exemplo que a guarda:

| id | mutação | veredito |
|---|---|---|
| M1 | a peneira da saída volta a DESCARTAR a entrega com caminho de campo | REPROVOU |
| M2 | `build_progress` volta a gravar `entregues` antes de o texto existir | REPROVOU |
| M3 | `fechar` volta a marcar o comparativo sem conferir se a entrega existe | REPROVOU |
| M4 | o token do preço volta a nascer do texto cru | REPROVOU |
| M5 | a montagem do schema deixa de recusar nome de parâmetro duplicado | REPROVOU |
| M6 | o desempate entre frases iguais sai de cena | REPROVOU |
| M7 | a frase reprovada pela peneira passa em vez de recuar | REPROVOU |
| M8 | a frase que copia a constante de outro papel deixa de ser recusada | REPROVOU |
| M9 | a pergunta pelo fecho já publicado volta a poder levantar | REPROVOU |
| M10 | o item da lista volta a separar nome e valor por travessão | REPROVOU |
| M11 | o nome do arquivo volta a levar travessão | REPROVOU |
| M12 | o aviso sem bônus volta a carregar número | REPROVOU |
| M13 | o fecho de quem tem resultado volta a ser a frase parcial | REPROVOU |
| M14 | o aviso de espera volta a sair sem os argumentos da execução | REPROVOU |
| M15 | a peneira deixa de recusar dígito na frase do modelo | REPROVOU |

**Duas mutações não pegaram na primeira rodada**, e as duas eram guarda mal apontada, não código
frouxo: M7 apontava para exemplos que só afirmavam "não fica mudo" (uma frase reprovada continua
presente) e M9 para um exemplo que a totalidade de `Encerramento#frase` já absorvia. Os dois alvos
foram corrigidos, e a segunda guarda de M9 — a pergunta que vai ao BANCO e o banco cai — nasceu daí.

## Ordem de deploy e rollback

O conjunto ampliado de perguntas do fecho (`FRASES_DE_FECHO`, com `partial_message` dentro) está no
MESMO commit das frases. Rollback para `origin/main` é seguro: a versão antiga publica `PARCIAL`, que
esta versão já pergunta; e a versão nova publica `FECHO_COM_RESULTADO`, que a antiga não pergunta —
por isso a volta atrás só é segura com o cliente que ainda não recebeu fecho nenhum. O caminho
conservador é não fazer rollback parcial de fecho já publicado.

Nada aqui exige migration, secret, env var nova ou mudança de infraestrutura.
