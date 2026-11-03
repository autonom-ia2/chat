# F7: IA como passo (#2500, épico #2414)

Este é o desenho da F7 sobre o motor que está no ar: `Executor`, `Roteiro`, `Receita`, `Valores`, a cadeia (F1) e os
passos `mensagem` e `avisar` (F4). As decisões abertas estão em **Decisões para o Rodrigo**, no fim do documento.
Cada uma traz uma recomendação.
- **Sem migration.**
- **Sem código de produção antes de o Rodrigo aprovar o protótipo.**

## O que entra e o que fica de fora

**Entram quatro passos novos**, no grupo IA do seletor:

| Passo | O que faz | Onde o resultado vai |
|---|---|---|
| `decidir` | Escolhe um entre 2 e 8 caminhos, ou "nenhum se aplica". | No caminho escolhido. |
| `extrair` | Tira dados da conversa (placa, CPF, data, valor). | Grava nos atributos do contato ou da conversa. |
| `escrever` | Gera um texto com a instrução de quem montou a automação. | Numa mensagem ao cliente ou numa nota de sugestão. |
| `resumir` | Resume a conversa. | Num aviso à equipe ou numa nota privada. |

**Ficam de fora:**
- **As IAs do CRM:** o follow-up IA, a avaliação de etapa e as rotas `crm/ai`. Nenhum arquivo delas é tocado (F7.5).
- **O Decisor salvo das regras antigas (#858):** o `perguntar_ao_decisor`, o `PerguntarJob` e o fluxo de dúvida. Seguem
  como estão. A F9 converte as regras.
- **Card como alvo:** entra com os gatilhos de card (F6). Antes disso, os quatro passos leem e gravam só na conversa,
  no contato e na empresa.

## Regra principal: sem freio no uso do cliente (Rodrigo, 31/10/2026)

A F7 não tem nenhum teto de chamadas de IA: nem por dia, nem por automação, nem por conta.
- **A linha do épico que diz "teto padrão de 1.000/dia por automação e 10.000/dia por conta"** foi substituída por esta
  regra. O ADR D8 já está assim.
- **O `LIMITE_MENSAL` do Decisor antigo (5.000 por mês) não vale nos passos novos.** Eles não usam o Jev nem a tabela
  de decisões.
- **Ficam só as proteções contra defeito:**
  - a cadeia comum, que impede a automação de disparar a si mesma e corta na profundidade 3;
  - o anti-laço da mensagem, para robô do outro lado (F4);
  - as 3 tentativas do executor para erro passageiro;
  - o erro permanente, que não se repete.

## A ideia central: o resultado da IA não fica guardado entre passos

Cada passo de IA entrega o resultado ali mesmo, dentro do próprio passo. Por exemplo:
- o `escrever` com destino mensagem chama o `PassoDeMensagem` com o texto pronto;
- o `resumir` com destino aviso chama o `PassoDeAviso`.

Assim, nada do que a IA escreveu sobre a conversa precisa esperar no banco até um passo seguinte. Isso tem três
efeitos:
- **Sem migration.** A execução não ganha coluna de contexto, e o registro continua guardando só ids e custo, como
  diz o contrato dele (`Registro`: "nunca o texto da conversa").
- **As proteções da F4 valem sem cópia:** janela, contato que pediu para não receber, tweet, anti-laço e autor
  "Automação".
- **O texto da IA nunca chega a quem não vê a conversa.** Ele mora na própria conversa, como mensagem ou nota.
  O histórico da automação, que quem tem só `automation_view` enxerga, mostra o id da mensagem e não o texto.

A outra forma seria um `$valor` como `ia.p3.texto`, lido por passos seguintes. Ela pede uma coluna na execução e
abre o caso do texto que espera dias e sai fora de hora. Também deixa o texto da conversa num lugar que não segue o
acesso dela. Fica de fora.

## O que a IA lê

Os quatro passos usam o `Autonomia::Decisores::Estado` que já existe, com a lista fechada de `leituras`. O passo
tem o campo `le`:
- **Valores aceitos:** `mensagens_recentes`, `mensagens_com_respostas`, `ultima_mensagem`, `conversa`, `contato`,
  `empresa`.
- **Padrão:** `mensagens_recentes`.
- `card` entra na F6.

Pela decisão de 03/10/2026, o texto das mensagens vai para a IA, e o e-mail e o telefone do contato nunca vão. A
instrução fixa de cada passo repete a regra de sempre: o que vem da conversa é dado e nunca é seguido como ordem.

## A chave e o custo

- **Chave:** a resolução é a mesma das outras IAs da conta, pelo `Crm::Ai::CredentialResolver`. Ver a decisão D2.
  Sem chave, o passo falha com `ia_nao_configurada`, e o erro é permanente (não repete).
- **Modelo:** `Crm::Ai::Config::MODEL_CLASSIFY` (hoje `gpt-6-luna`) para decidir e extrair, e
  `Crm::Ai::Config::MODEL_SUMMARY` para escrever e resumir. A resposta é sempre estruturada (JSON schema), com esforço
  `low`.
- **Uso:** cada chamada grava um `Crm::AiUsageEvent` com a feature do passo: `automacao_decidir`,
  `automacao_extrair`, `automacao_escrever` ou `automacao_resumir`. Elas entram na Gestão IA como as outras.
- **Custo no passo:** o passo soma o custo assinando o evento `crm.ai_usage` enquanto roda, do mesmo jeito que o
  registro do Guia (#861). O registro leva `custo_usd`, `modelo`, `tokens_entrada` e `tokens_saida`.
- **Na tela:**
  - **No histórico**, cada passo de IA mostra em frases o que decidiu e o custo daquela vez (F7.4). Pela regra da
    Automação de 03/11, a frase não traz o prompt nem dado do cliente além do que a tela já mostra. O formato da frase
    é da F2 (#2498).
  - **No editor**, o cartão do passo mostra "cerca de US$ X por vez", pela média dos registros desse passo nos últimos
    30 dias. Antes da primeira vez, mostra "o custo aparece depois da primeira vez".
  - **Na lista**, cada automação mostra a soma dos últimos 30 dias.
  - É só informação: nenhum número trava nada.

## Passo `decidir`

```json
{ "id": "p2", "tipo": "decidir", "le": ["mensagens_recentes"],
  "pergunta": "Sobre o que o cliente está falando?",
  "caminhos": [
    { "chave": "sinistro", "descricao": "batida, roubo, dano no carro", "passos": [ ... ] },
    { "chave": "cotacao", "descricao": "quer preço de seguro novo", "passos": [ ... ] }
  ],
  "nenhum": [ ... ] }
```

- **Caminhos:** de 2 a 8, cada um com `chave` única no passo, `descricao` e `passos`. A lista `passos` pode ficar
  vazia: nesse caso, a receita segue no passo depois do `decidir`.
- **"Nenhum se aplica":** é sempre uma saída. O schema da resposta tem `caminho` no enum das chaves mais `nenhum`, e
  `motivo` com até 200 caracteres. A instrução manda escolher `nenhum` quando a conversa não deixa claro, em vez de
  chutar (F7.1). O ramo `nenhum` é opcional.
- **Roteiro e Receita:** os dois passam a conhecer os ramos dinâmicos `caminhos[].passos` e o ramo `nenhum`.
  - O `Roteiro#mapear` anda por eles.
  - O executor entra no ramo com `@roteiro.entrar_no_caminho(passo, chave)`.
  - A `Receita` confere três coisas: ids únicos em todos os ramos, as chaves e o limite de 2 a 8.
- **Registro:** guarda `ramo` (a chave ou `nenhum`), o custo e o id da nota do motivo (ver D3).
- **Retomada:** depois de uma espera dentro de um caminho, o cursor aponta para um passo do caminho, e o `Roteiro`
  sabe sair dele. A IA não é perguntada de novo, porque o cursor já passou do `decidir`.
- **Por que não reaproveitar o Decisor salvo (#858):** ver D1.

## Passo `extrair`

```json
{ "id": "p3", "tipo": "extrair", "le": ["mensagens_recentes"],
  "campos": [
    { "chave": "placa", "descricao": "placa do carro", "destino": "contato.atributos.placa" },
    { "chave": "data_sinistro", "descricao": "data da batida", "destino": "conversa.atributos.data_sinistro" }
  ],
  "trocar": false }
```

- **Destinos:** `contato.atributos.<chave>`, `conversa.atributos.<chave>`, `contato.nome` e `empresa.nome`. Ao
  salvar, a receita confere que o atributo existe na conta (`Valores.atributo_definido?`). Até 10 campos por passo,
  o mesmo limite do Decisor. E-mail e telefone não entram como destino: ver D4.
- **Extração:** o schema tem um campo por chave, do tipo `string | null`. A instrução é a do
  `Decisores::Extrator`: preencher só com o que está escrito e devolver nulo quando o dado não aparece.
- **Gravação pela porta da frente, como quem ligou (D1 do ADR):** a gravação passa pelo `PassoDeAcao`, com a ação do
  catálogo já liberada (`PATCH contacts/:id` ou `POST conversations/:id/custom_attributes`).
  - A permissão de quem ligou é conferida pela plataforma.
  - Quem não pode gravar pausa a automação, como na ação (`quem_ligou_sem_acesso`).
  - A escrita não toca no banco por fora.
- **Só preenche (padrão):** não troca o valor que já existia, pela mesma regra do `Decisores::Aplicador`, porque o
  texto é de terceiros. Com `trocar: true`, o valor novo entra mesmo assim.
- **Resultado (F7.2):** o registro diz `gravados` e `ausentes` (as chaves que a IA não achou) e, quando há, os
  `ja_tinha`. Os valores ficam de fora. O histórico mostra a frase "Não achou na conversa: placa". Os passos
  seguintes leem o que foi gravado pelos caminhos de sempre (`contato.atributos.placa`), no `se` e no texto.
- **Falha:** quando nada foi achado, o passo dá `pulado` com `dado_ausente`, e a automação segue. A gravação recusada
  pela plataforma dá `falhou` com o motivo, como a ação.

## Passo `escrever`

```json
{ "id": "p4", "tipo": "escrever", "le": ["mensagens_com_respostas", "contato"],
  "instrucao": "Agradeça o contato e diga que um corretor responde em até 1 hora. Tom cordial, até 3 frases.",
  "destino": "mensagem" }
```

- **`destino: mensagem`:** a IA gera o texto, que sai pelo `PassoDeMensagem`. Valem todas as regras da F4:
  - autor "Automação";
  - janela de 24 h, como envio automático;
  - pula o contato que pediu para não receber;
  - pula o tweet;
  - anti-laço;
  - não reenvia.

  Exige também a flag `automacao_mensagens`, e sem ela o passo para com `mensagens_desligadas`.
- **`destino: sugestao`:** o texto vira uma nota privada na conversa ("Sugestão da automação: …"), para a pessoa da
  equipe revisar e mandar. É a aprovação humana da F7.3 sem um estado novo de espera. Ver D5.
- **Ordem:** a IA só é chamada depois das conferências baratas do `PassoDeMensagem`. Fora da janela ou com o contato
  opt-out, o passo pula antes de gastar.
- **Instrução:** até 2.000 caracteres. A instrução fixa diz que o texto é para o cliente, no idioma da conversa,
  sem inventar preço, prazo ou promessa que não esteja na instrução.
- **Ensaio (F7.3), pela regra da Automação de 03/11:** o ensaio e o histórico são da F2 (#2498). Cada tipo de passo
  declara como se ensaia, e o passo de IA nunca chama o modelo no ensaio. No ensaio:
  - o `escrever` mostra "aqui a IA escreveria o texto", com a instrução e o destino;
  - o `resumir` mostra "aqui a IA resumiria a conversa";
  - o `decidir` mostra "aqui a IA escolheria o caminho" e lista os caminhos;
  - o `extrair` mostra "aqui a IA procuraria: placa, data" e diz onde gravaria.

  O ensaio não toca o Redis do AntiLaco nem a Cadeia, não despacha evento e não publica no Cable. A forma de cada
  passo declarar a frase do ensaio é combinada com a F2 antes de codar.
- **Ver o texto de verdade antes de ligar:** o ensaio não mostra o texto da IA. Uma opção à parte, fora do ensaio, fica
  para o Rodrigo decidir (D6).

## Passo `resumir`

```json
{ "id": "p5", "tipo": "resumir", "le": ["mensagens_com_respostas"], "linhas": 3,
  "destino": { "avisar": { "responsavel": true, "times": [3] } } }
```

- **`destino.avisar`:** o resumo sai pelo `PassoDeAviso`, com as regras da F4. A nota privada menciona só quem vê a
  conversa, e a lista vazia pula. Exige `automacao_mensagens`.
- **`destino: nota`:** uma nota privada sem menção. Só precisa da flag da F7.
- **`linhas`:** de 1 a 10, com padrão 3.

## Erros e tentativas

O executor já sabe o que fazer com cada tipo de resultado. Os passos de IA só devolvem o tipo certo:

| Caso | Tipo | Efeito |
|---|---|---|
| timeout, 429, 5xx, rede (`ResponsesClient::Error#passageira?`) | transitório | 3 tentativas (1 min, 5 min), depois `falhou` |
| sem chave, chave recusada (401/403), resposta fora do schema | permanente | `falhou` com o motivo, sem repetir |
| destino recusado pela plataforma (extrair) | permanente | `falhou` com o motivo |
| quem ligou não pode gravar ou não vê a conversa | sem acesso | pausa a automação (F3.7) |

- **Nova tentativa:** pergunta de novo à IA e paga de novo. O `escrever` com destino mensagem nunca manda duas vezes,
  pela regra da F4.
- **Sem freio:** a IA de uma conta sem crédito falha a cada execução com o motivo no histórico. Isso não pausa a
  automação nem vira teto.

## Flag `automacao_ia`

- **Própria da F7,** pelo ADR D11.
- **Depende de:** `automacao_motor` e `automacao_fundacao`. Os destinos que falam com gente (`escrever` mensagem e
  `resumir` avisar) exigem também `automacao_mensagens`.
- **Bit:** é a Orquestração que dá.
- **Contas:** pela regra das fases, nasce ligada no piloto (1, 16 e 18). Isso só vale depois do OK do Rodrigo no
  protótipo e no eval.
- **Desligada:**
  - o seletor não oferece o grupo IA (`requer: automacao_ia`);
  - o salvar recusa com `passo_desligado`;
  - a execução que chega no passo fecha como parada, com `ia_desligada`, sem chamar a IA. É o rollback.

## Protótipo (próximo passo, depois do desenho)

O protótipo é feito em tela real, com o kit `bin/demo`, numa conta de demo com as flags de produção mais
`automacao_ia`. A jornada clicável:
1. **Seletor de passo:** o grupo novo "IA" com Decidir, Extrair, Escrever e Resumir.
2. **Decidir:** a pergunta, os caminhos com nome e descrição, e "Nenhum se aplica". Cada caminho abre a sua lista de
   passos no editor.
3. **Extrair:** a linha "o que procurar → onde gravar", com o seletor de atributo da conta, sem `<select>` nativo.
4. **Escrever e Resumir:** a instrução, o destino e "o que a IA lê".
5. **Cartão do passo:** "cerca de US$ X por vez".
6. **Ensaio:** cada passo de IA na frase "aqui a IA escolheria o caminho" (ou "escreveria o texto"), sem chamar o
   modelo.
7. **Histórico:** "Decidiu **sinistro** · por quê (na conversa) · US$ 0,0003", "Não achou: placa" e "Mandou a
   mensagem #…".

O exemplo do aceite fica montado na demo: "bati o carro ontem" → Decidir "sinistro" → Extrair placa e data → aviso ao
time com o resumo de 3 linhas. A criação do card espera a F6, e a demo mostra o ponto onde ela entra.

## Eval (F7.1), só com OK do Rodrigo

- **Amostra:** 20 conversas reais, anonimizadas antes de sair do banco. Só leitura, pelo caminho de produção de
  sempre: `psql` por SSM.
- **Rodadas:** 1 Decidir, mais 1 Extrair nas que tiverem dado, em 2 rodadas. O total fica em torno de 80 chamadas ao
  `gpt-6-luna`.
- **Estimativa:** menos de US$ 0,10.
- **Orçamento proposto:** teto de US$ 1,00. O script para quando passa do teto.
- **Critério:** pelo menos 18 de 20 no Decidir, com o "nenhum" certo, e zero campos inventados no Extrair.

## Arquivos que a F7 vai tocar (lista para a Automação ordenar)

**Arquivos novos, só da F7:**
- `app/services/autonomia/automacao/passo_de_ia.rb` (a chamada, a soma do custo e os tipos de resultado);
- `passo_de_decidir.rb`, `passo_de_extrair.rb`, `passo_de_escrever.rb` e `passo_de_resumir.rb`;
- os specs de cada um;
- as peças Vue `LivreCaminhos.vue`, `LivreCamposExtrair.vue` e `LivreLeituras.vue`;
- a seção F7 da Central.

**Arquivos compartilhados, só com blocos novos e pequenos:**
- `executor.rb`: a constante `IA` e uma linha no `case`, mais o método `passo_de_ia` e a entrada no caminho do
  `decidir`;
- `roteiro.rb`, para os ramos dinâmicos;
- `receita.rb` e `automacao-receita.schema.json`, para os 4 passos e as conferências;
- `motor.rb`, para o `FLAG_IA` e o `ia?`;
- `catalogo.rb`, para as peças `caminhos`, `campos_extrair`, `leituras` e `destino`;
- `automacao-passos.yml`, para o grupo `IA` e os 4 nativos com `requer: automacao_ia`;
- `automacao-passos.json`, que é gerado;
- `automacaoLivre.json`, em en e pt_BR;
- `LivreSeletorPasso.vue` e `LivreAlterar.vue`;
- `config/features.yml` e `spec/models/account_spec.rb`, para a flag;
- a declaração de como cada passo de IA se ensaia, no formato que a F2 (#2498) definir;
- `automacoes_controller.rb` e `config/routes.rb`, só se o Rodrigo escolher a opção A da D6.

**Não tocados:** `app/services/crm/ai/*` (só usados), `app/services/autonomia/decisores/*` (só o `Estado`, usado
como está) e as IAs do CRM.

## Decisões para o Rodrigo

| # | Pergunta | Opções | Recomendação |
|---|---|---|---|
| D1 | Com que IA o Decidir pensa? | **A)** Modelo da chave da conta, com a pergunta e os caminhos no próprio passo. **B)** Reaproveitar o Decisor salvo (#858), que usa o Jev, com custo nosso e teto de 5.000 por mês. | **A.** Cumpre o "usa a chave da conta" do aceite e devolve o motivo (F7.4); o Jev só devolve a escolha e a certeza. Também não tem o teto mensal, que fere a regra de 31/10, e não amarra o motor novo à tabela de decisões por mensagem das regras antigas. Custo perto de US$ 0,0002 por vez no `gpt-6-luna`. |
| D2 | Conta sem chave própria pode usar a chave da plataforma? | **A)** Sim, como as outras IAs da conta (o resolver cai na chave da instalação). **B)** Só com chave própria; sem ela, `ia_nao_configurada`. | **B.** O aceite diz "chave da própria conta", e com A o custo das automações de todos os clientes cai na nossa conta, sem freio. Se o Rodrigo preferir A, o custo continua aparecendo na tela igual. |
| D3 | Onde fica o "por quê" do Decidir? | **A)** Numa nota privada curta na conversa ("Automação decidiu *sinistro*: …"), e o histórico liga para ela. **B)** No registro, e o histórico só mostra a quem vê a conversa. | **A.** Mantém o contrato do registro, que não guarda texto da conversa, e quem não vê a conversa não vê o motivo. O custo é uma nota por decisão; com B, a nota some, mas o registro passa a guardar texto e o histórico tem de filtrar por acesso. |
| D4 | O Extrair grava e-mail e telefone do contato? | **A)** Não, na F7. **B)** Sim, com as regras do `Aplicador` (telefone no formato da conta, único na conta, e-mail nunca trocado). | **A.** E-mail identifica o contato no canal, e telefone tem regra de unicidade com caminho próprio. Podem ir para um atributo. Entra quando um caso pedir. |
| D5 | Aprovação humana antes de enviar (F7.3, proposta)? | **A)** O destino `sugestao` (nota privada que a pessoa revisa e manda). **B)** Um estado novo "esperando pessoa", com botão aprovar, que retoma a execução. | **A** na F7. B pede um estado novo na execução, tela e prazo, e fica para quando houver o caso. |
| D6 | A F7.3 pede ver o texto antes de ligar, mas o ensaio não chama a IA (regra da Automação de 03/11). Como quem monta vê um texto de verdade? | **A)** Um botão "Testar este passo", fora do ensaio, no cartão do Escrever e do Resumir. Chama a IA paga em até 3 conversas que quem monta vê, mostra o custo antes do clique e não manda nada. **B)** Nada além do ensaio. Para ver o texto de verdade, liga com destino `sugestao` (nota privada) e confere nas primeiras conversas. | **B** na F7. Respeita a regra do ensaio sem abrir uma segunda porta paga, e a `sugestao` já mostra o texto real sem mandar ao cliente. A opção A fica para quando o Rodrigo pedir. |
