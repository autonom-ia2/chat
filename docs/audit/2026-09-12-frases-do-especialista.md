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
| P1-1 | `Progress` descartava a entrega inteira ao achar caminho de campo, e `build_progress` já tinha gravado `entregues`: as ofertas nunca mais eram reemitidas, `delivered_count` ficava zero e o cliente lia a frase de falha sobre dezessete seguradoras pagas | `Progress` passa a **redigir** e nunca descartar por conteúdo; `DELIVERED_KEY` sai de `build_progress` e é gravada em `precos`, depois de o texto do lote existir. Ela grava o LOTE (`fresh`), não "as ofertas que entraram no texto": o corte por tamanho pode deixar as últimas de fora e elas ficam marcadas mesmo assim — ver a medição da folga abaixo |
| P1-2 | a mesma peneira devolvia nil para a entrega de arquivo com `PDF_SENT_KEY` já gravada: `comparison_pdf` devolvia nil para sempre | `fechar` põe a entrega na forma final (`Progress.entregavel`) e só então mescla as marcas |
| P2 (token) | o token nascia do texto CRU e o publicador o calculava sobre o texto aparado: `resultado_entregue?` nunca casava | `precos` e `fechar` depuram ANTES de calcular o token; `TextoAoCliente.depurar` é idempotente, então a segunda passada pelo `Progress` não muda o texto |
| P2 (aviso) | `AVISO_SENT_KEY` podia ser gravada sem o texto ter saído | a sentinela entra no mesmo merge do texto entregue |

A peneira antiga (`/\b[a-z][a-z0-9]*\.[a-z][a-zA-Z0-9]*\b/`) errava nos dois sentidos — cortava
`p.ex.`, `hub2you.ai`, `contato@corretora.com.br`; deixava passar `Já pedi.Aguarde` e `Ok.vou ver`.
A nova é **lista fechada**, derivada de `Parametros::GRUPOS` e `QuoteInput::GRUPOS_DE_AUTO`.

**A exclusão de URL veio junto com a peneira antiga, e voltou na rodada de correção.** A `main` tinha
`Progress::URL` e apagava o link antes de olhar; a lista fechada nasceu sem substituto. `quotation` é
grupo do formulário e a URL do comparativo do portal termina em `.../quotation.pdf`: sem a exclusão, a
reserva do comparativo saía com `https://portal.exemplo.com/v1/…` e o cliente recebia um link
quebrado. Era regressão contra a `main`. Hoje a exclusão mora em `TextoAoCliente::URL`, vale só para
`redigir` (em `vetar` o modelo não escreve link, e recuar ali custa uma frase) e é uma varredura só,
com a URL na frente da alternância.

### 1.1 A folga de truncamento, medida

A afirmação de que `MAX_FRASE = 350` mantém o texto composto longe de `MAX_DELIVERY_CHARS = 3.000`
estava no código sem número nenhum. Medida em 12/09/2026 pelo código real (`QuoteOffers.describe` +
`PremiumText`), com as DUAS frases do especialista no teto (abertura e aviso, 350 cada) e o **pior
item que o código produz**: preço sem período, que leva a ressalva `SEM_BASE` inteira na segunda
linha, com o nome de seguradora mais longo que o portal devolveu nas medições ("Bp Assinatura") —
**86 caracteres por item**.

| seguradoras no lote | texto composto | folga |
|---|---|---|
| 17 (o que o portal real devolveu) | 2.089/3.000 | 911 |
| 22 | 2.493/3.000 | 507 |
| 26 (o maior lote que ainda cabe) | 2.990/3.000 | 10 |
| 27 | estoura | — |

A folga é real e larga, e **não é guarda**: quando o corte morde, ele não avisa ninguém, e as ofertas
cortadas já foram marcadas em `DELIVERED_KEY`. Está em "o que NÃO foi verificado".

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
conjunto de perguntas do fecho: é o texto que a versão ANTIGA publicou nas execuções que já estavam
abertas, e sem ela esta versão poria um segundo desfecho ao lado do primeiro.

**Isso é proteção de ROLL-FORWARD, não de rollback** — o código dizia "rollback" em três lugares
(`Encerramento::FRASES_DE_FECHO`, `Declaracao::PARCIAL` e `Declaracao.partial_message`) e foi
corrigido na rodada de correção. A volta atrás leva este arquivo junto, e com ele a pergunta: a
versão antiga pergunta só pelas constantes dela, e `FECHO_COM_RESULTADO` não está entre elas. Ver
"Ordem de deploy e rollback".

**Ninguém publica `partial_message` hoje.** `Encerramento#parcial` era o único caminho que a pedia.
O que sobrou dela é a PERGUNTA. O comentário de `Native::Base#partial_message` dizia que nas demais
ferramentas ela continuava sendo o fecho; nenhuma ferramenta a redefine nem a publica.

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
  `9cc4cffcba4a269acc61e29154ecc2b0` → `f4cac7c3a923066421ef0e4529c1f372` (o segundo md5 já
  inclui a correção da §2.1 feita na rodada de correção).
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
   entrega É o texto. A regra fica no manual, e o manual agora DIZ ao modelo que ela não é
   conferida (§2.1). A medição de 96 frases citada aqui é de rodada anterior e não foi refeita neste
   PR — ver "o que NÃO foi verificado".
4. **`depurar` redige só o caminho de campo pontuado, não o camelCase.** O texto final carrega o
   nome da seguradora vindo do portal, e uma marca como `eSeguros` seria mutilada. O camelCase
   continua sendo regra de `vetar`, que é onde o texto de fora entra.
5. **A prosa dos manuais continua usando travessão.** Só a REGRA foi acrescentada. A peneira
   reprova travessão de qualquer forma, e reescrever um texto aprovado pelo PO por imitação não
   medida não se justifica. (A medição de "0 travessões em 96 frases" é de rodada anterior, com
   outro manual em disco; não foi refeita neste PR.)
6. **`QuoteOffers.describe` perdeu `first:` e ganhou `abertura:`.** Quem escolhe entre as três
   aberturas é quem conhece o lote (`InsuranceQuote#abertura_de_precos`); quem as escreve é o
   especialista. `describe` compõe.

## O que NÃO foi verificado

- **Três dos cinco itens da proibição do CEO não têm guarda nenhuma.** A peneira cobre o que se
  reconhece pela FORMA: algarismo, `R$`, travessão, meia-risca, acento grave, caminho de campo e
  folha camelCase. **Contagem por extenso** ("chegaram três opções"), **prazo por extenso** ("volto
  em cinco minutos") e **nome de seguradora** ("a Porto respondeu") passam inteiros e chegam ao
  cliente. Isso depende da obediência do modelo, e só dela. Está dito com todas as letras no manual
  do especialista (§2.1), que é quem precisa saber, e no comentário de `TextoAoCliente::DIGITO`.
  Construir a guarda de nome de seguradora é decisão em aberto (ver a decisão 3): a lista só existe
  dentro da conexão, e a peneira precisa ser pura.
- **O resíduo do `already`: o handle avança na EMISSÃO, não na publicação aceita.** `precos` grava
  `DELIVERED_KEY` assim que o texto existe; se a publicação for recusada depois (conversa encerrada,
  erro transitório do publicador — `deliver` roda antes de `record_attempt!`), aquelas ofertas
  ficam marcadas como entregues sem o cliente as ter lido, e `fresh` não as devolve. A entrega
  resolveu o caso "o texto não sobreviveu à depuração"; este não. É o mesmo motivo pelo qual
  `AVISO_SENT_KEY` precisou de sentinela própria, e vale também para as ofertas cortadas pelo teto
  de 3.000 (ver a medição da folga).
- **A medição das 96 frases não é deste trabalho.** As afirmações de "0 travessões" e "0 nomes de
  seguradora" em 96 frases geradas vêm de uma rodada anterior, com outro estado do manual em disco.
  Não foram reproduzidas neste PR e não devem ser lidas como evidência dele.
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

Números da rodada de correção (os da primeira rodada eram 1777 exemplos; a diferença são os
exemplos novos):

- `spec/services/autonomia`, `spec/jobs`, `spec/models/autonomia`: **1790 exemplos, 0 falhas**,
  5 pending (exit 0).
- `rubocop` com lista explícita (8 arquivos de app + 4 de spec, os alterados): **0 offenses**
  (exit 0).
- `rails zeitwerk:check`: `All is good!` (exit 0).
- **15 mutações da primeira rodada, 15 reprovadas** — cada correção desfeita derruba o exemplo que a
  guarda:

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

## Rodada de correção — 12/09/2026

Três revisores adversariais independentes reprovaram a entrega. Convergiram num bloqueio de código e
numa lista de afirmações que diziam mais do que o código entrega. O que foi feito:

### O bloqueio: a redação mutilava o link do comparativo

`TextoAoCliente.redigir` perdeu a exclusão de URL que a `main` tinha em `Progress`. A regra de
caminho de campo nasceu de uma lista fechada de grupos, e `quotation` é um deles: a URL do
comparativo do portal termina em `.../quotation.pdf`, então o link saía como
`https://portal.exemplo.com/v1/…` e o cliente recebia uma aba que não abre. **Regressão contra a
`main`**, num caminho que só aparece quando o download do PDF falha e sai a reserva.

Pior: **dois exemplos diziam cobrir o caso e não cobriam.** Os dois usavam
`https://portal.exemplo.test/cotacao/9.pdf`, e `cotacao` não é grupo do formulário — a regra nunca
disparava, e os dois passavam com e sem a exclusão. Um comentário em `progress_spec` ("por isso a URL
sai antes de olhar") sobreviveu à remoção da guarda que ele descrevia.

Corrigido: `TextoAoCliente::URL`, usada só em `redigir`, numa varredura única com a URL na frente da
alternância — o que casa pelo lado da URL volta intacto, o que casa pelo outro é caminho de campo e
vira o sinal de corte. Exemplos com URL que **dispara de verdade** (caminho do portal, query string,
grupo no host) e um que prova que a exclusão não virou anistia: o `insured.document` fora do link
continua sendo redigido na mesma passada.

### As afirmações corrigidas

| onde | dizia | passou a dizer |
|---|---|---|
| `texto_ao_cliente.rb` (`DIGITO`) | a regra cumpre "número, contagem, valor e prazo" inteiros | cumpre a forma ESCRITA EM ALGARISMO; o resto é do manual |
| `texto_ao_cliente.rb` (`MAX_FRASE`) | mantém o texto composto "longe do corte", sem número | a folga medida, com a tabela de §1.1 |
| `especialista_auto.md` §2.1 | "frase com qualquer um deles é descartada" | o que a peneira descarta e **o que ela não enxerga** — contagem por extenso, prazo por extenso e nome de seguradora dependem do modelo |
| `insurance_quote.rb` (`DELIVERED_KEY`) | grava "as ofertas que entraram no texto" | grava o LOTE; o corte por tamanho pode deixar as últimas de fora |
| `base.rb` (`partial_message`) | "nas demais ferramentas ela continua sendo o fecho" | nenhuma ferramenta a publica; o que sobrou dela é a pergunta |
| `encerramento.rb`, `declaracao.rb` (×2) | o conjunto ampliado protege o rollback | protege o ROLL-FORWARD; o rollback leva a pergunta junto |
| `comparativo.rb` | a depuração decide a identidade da entrega | a identidade de um arquivo é `"arquivo:#{url}"`; legenda e reserva não entram nela |
| `frases.rb` | `frases_catalogo_spec` | `frases_spec` |

### Limpeza

- `Progress.texto`, `.arquivo` e `.descartar` voltaram a ser privadas (`private_class_method`): elas
  viraram método de classe junto com `entregavel`, e o `private` do arquivo só alcança instância.
  Só `entregavel` precisava sair.
- `Frases.de` lia a chave do nó com `argumentos.deep_stringify_keys` — copiava o formulário inteiro
  (~90 campos de auto) para ler quatorze frases, umas seis vezes por fecho. Passa a ler só a chave,
  nas duas grafias, e a normalizar só o nó.
- `spec/tmp_probe/` (probe_a/b/c) **não existe neste worktree nem no commit**: `git ls-files`,
  `git status --untracked-files=all` e `--others --ignored` não o encontram. Nada a apagar.

### O que NÃO foi feito, de propósito

Não foi criada guarda nova para nome de seguradora, contagem por extenso ou prazo — é decisão do
Rodrigo e está com ele. O trabalho desta rodada foi **declarar a fronteira** nos três lugares onde
ela precisa estar: no código (`TextoAoCliente::DIGITO`), no manual do especialista (§2.1, que é quem
garante esses três) e nesta auditoria. `fecho_publicado?` não foi tocado além do comentário.

### Mutações desta rodada

| id | mutação | veredito |
|---|---|---|
| M16 | `redigir` volta a olhar o texto sem apagar a URL | REPROVOU — 7 exemplos em `texto_ao_cliente_spec` e `progress_spec` |
| M17 | `Progress.texto/.arquivo/.descartar` voltam ao público | REPROVOU — `progress_spec` |
| M18 | `Frases.de` volta a copiar o hash inteiro para ler a chave | REPROVOU — `frases_spec` |
| M19 | o manual volta a dizer "frase com qualquer um deles é descartada" | REPROVOU — 2 exemplos em `builder_instrucao_do_especialista_spec` (a âncora da promessa e o md5) |

A promessa nova (`não enxerga contagem por extenso, prazo por extenso nem nome de seguradora`) é
provada nos DOIS sentidos: a âncora prende o texto do manual, e a lambda mostra que a peneira de
fato deixa passar `Chegaram três opções:`, `Volto em cinco minutos.` e `A Porto respondeu.`.
Construída a guarda um dia, a promessa cai e obriga a reescrever o manual junto.

md5 do manual do especialista depois desta rodada: `f4cac7c3a923066421ef0e4529c1f372`.

## Ordem de deploy e rollback

O conjunto ampliado de perguntas do fecho (`FRASES_DE_FECHO`, com `partial_message` dentro) está no
MESMO commit das frases, e **o que ele protege é o deploy, não a volta atrás**: a execução aberta
antes do deploy recebeu `PARCIAL` da versão antiga, e esta versão pergunta por ela antes de fechar de
novo.

**O rollback não tem essa proteção**, e não pode ter: voltar para `origin/main` leva junto o arquivo
que faz a pergunta. A versão antiga pergunta só pelas constantes dela, e `FECHO_COM_RESULTADO` — o
que esta versão publica — não está entre elas; o cliente que já recebeu o fecho novo receberia um
segundo desfecho, contradizendo o primeiro. Voltar atrás só é seguro com o cliente que ainda não
recebeu fecho nenhum. O caminho conservador é não fazer rollback parcial de fecho já publicado.

Nada aqui exige migration, secret, env var nova ou mudança de infraestrutura.
