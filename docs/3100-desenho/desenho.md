# F4 · Fidelidade (carimbos/pontos) e cupom único — desenho

Issue #3100, épico #3095. Onda 1: desenho e telas de verdade, sem backend. Os
componentes recebem tudo por props; nada chama a API, nada entrou em rota,
menu, ficha ou catálogo da automação ainda.

## 1. O que já existe e esta fase toca

Lido antes de desenhar (caminhos relativos à raiz do repositório).

**Compra (F1, #3097, no ar).** É o card ganho num funil de Vender.

- `app/services/relacionamentos/compras/recalcular.rb`: refaz o resumo de compras
  (`Relacionamentos::Compra`) quando um card é ganho ou desfeito, com trava da
  conta (`pg_advisory_xact_lock`) e disparo do gatilho
  `contato.entrou_no_grupo_de_compra` depois do commit. Só soma em BRL (`REAL`).
- `Crm::Card.com_desfecho`, `Events::Types::CRM_CARD_WON`, gatilho `card.ganho`
  (`app/services/autonomia/automacao/gatilhos.rb`).
- Ficha: `relacionamentos/components/ficha/SecaoCompras.vue`, encaixada no slot
  `#antes` de `CorpoDaFichaDaPessoa.vue` por `pages/FichaDaPessoaPage.vue`
  (linhas 664–684). Dados: `fonte/fichaFonte.js` → `RelacionamentosAPI.comprasDaPessoa`
  → `GET .../relacionamentos/pessoas/:id/compras` (`config/routes.rb:1205`).
- Formatos: `relacionamentos/ficha/compras.js` (`formatarDinheiro`),
  `ficha/formatos.js` (`formatarDiaMes`), `ficha/idioma.js`.

**Peças da ficha reaproveitadas.** `CartaoDaSecao`, `FalhaDaParte`,
`DialogoDaFicha` (+ `TituloDoDialogo`), `comum/SeloDeEstado`, `comum/HeroiEscuro`,
`comum/ponto.js`, `trazer/larguraDaBarra.js`, e o desenho das abas de
`lista/AbasDaLista.vue`.

**Automação livre.**

- `automacoes/livre/catalogo.js`: catálogo que vem do servidor
  (`GET automacoes/passos`, gerado de `lib/operator_guide/automacao-passos.yml`),
  com gatilhos, passos e `valores` (o "Pôr um dado").
- `automacoes/livre/passosNovos/passosNovos.js` + `LivrePassoNovo.vue`: o padrão
  dos 6 passos novos (#2931–#2936): entrada no catálogo, peça do "Alterar",
  `novoPassoNovo`, `passoNovoPronto`.
- `automacoes/livre/components/LivreTexto.vue` + `texto.js`: a caixa de texto com
  "Pôr um dado" (`{$valor: caminho}`), reaproveitada no "Mandar cupom".
- Servidor: `app/services/autonomia/automacao/` (`catalogo.rb`,
  `catalogo_de_valores.rb`, `gatilhos.rb`, `passo_de_pesquisa.rb` como modelo de
  passo novo).

**Menu e permissões.**

- `components-next/sidebar/Sidebar.vue` (lista de sempre) e
  `components-next/sidebar/forkSidebarMenu.js` (menu novo, #1617, grupos ATENDER,
  ACOMPANHAR, CRESCER, AUTOMATICO, RESULTADOS).
- `enterprise/app/models/custom_role.rb` (`PERMISSIONS`),
  `settings/customRoles/permissionMatrix.js` (grupo MARKETING com CAMPAIGNS,
  WHATSAPP_TEMPLATES, META_ADS, POSTS), `constants/permissions.js`
  (`SALES_VALUE_VIEW_PERMISSION`).

**i18n.** Catálogo novo do fork `fidelidade.json` (en + pt_BR), registrado em
`config/fork_i18n.json`, no `ignore` do `crowdin.yml` e nos dois `index.js`.
`node scripts/check-fork-i18n.mjs` passa. Os textos evitam "ganho/ganhar"
porque a trava de pacotes de segmento (`scripts/i18n-pacotes/cobertura.mjs`)
reserva essas palavras para o resultado da venda.

## 2. A jornada, como a pessoa leiga vive

Exemplo: dona de um lava-jato.

1. **Menu > Crescer > Fidelidade.** Ela lê "Faça o cliente voltar com um cartão
   fidelidade." e vê um botão só: **Criar meu cartão fidelidade**. (cena 01)
2. **Monta o cartão numa tela só.** Escolhe Carimbos (o cartãozinho de papel) ou
   Pontos, diz "a cada R$ 50", "ganha 1 carimbo", "10 carimbos", "uma lavagem
   grátis" e até quando valem. Ao lado, o "Exemplo de cartão de um cliente"
   (o cliente nunca vê esse cartão: ele recebe texto no WhatsApp), com
   bolinhas carimbadas e o presente na última, e uma frase de exemplo: "Uma
   compra de R$ 120 dá 2 carimbos. O que sobra não passa para a próxima." A
   compra de exemplo nunca fica abaixo de R$ 100 (em pontos, "a cada R$ 1" dá
   "R$ 100 dá 100 pontos"). No celular o exemplo vem compacto, para o
   formulário aparecer logo. Botão: **Criar e ligar o cartão**. Se faltou algo,
   o campo diz o quê, a faixa vermelha "Faltam as regras do cartão." aparece
   acima dos botões e o foco vai ao primeiro campo errado (no celular a tela
   rola até ele); o botão nunca fica apagado. O mesmo vale no Criar cupom.
   (cenas 02–04, 03b)
3. **Pronto.** "Pronto! O cartão está valendo." Embaixo, dois avisos prontos pelo
   WhatsApp, cada um com a mensagem de exemplo montada pelo programa criado
   (carimbos ou pontos, a meta): **Usar o aviso de saldo** (botão forte) e
   **Usar o aviso de cartão completo**. Tocar abre a automação já montada e
   desligada, como as receitas de hoje. Ela confere e liga. Há também "Agora
   não, ver meu cartão". (cenas 05, 05b)
4. **Dia a dia, nada a fazer.** O atendente marca o card como ganho, como já faz.
   O cliente recebe carimbos sozinho e, se ela ligou o aviso, recebe "Você
   recebeu 1 carimbo e já tem 7 de 10".
5. **Painel.** De volta a Fidelidade: o cartão da conta ("Cartão de 10
   carimbos", sem saldo de ninguém), a validade, três números dos últimos 30
   dias (clientes no cartão, perto do prêmio, prêmios dados) e a ação: **Ver
   quem está perto do prêmio** (a lista de Relacionamentos já filtrada). No
   celular os números vêm antes do cartão. Ao lado de "Mudar as regras",
   **Pausar o cartão**, que pergunta antes ("As compras param de dar carimbos
   até você ligar de novo."). Pausado, a faixa âmbar traz **Ligar o cartão de
   novo**; quem não pode mudar lê "Peça a quem administra a conta para ligar
   de novo." (cenas 06–08, 08b, 08c)
6. **Cliente chega para o prêmio.** O atendente abre a ficha. No bloco
   Fidelidade, logo depois de Compras, vê o cartão compacto, o que vence logo,
   os últimos movimentos e os cupons da pessoa. Completo, o cartão diz
   "Cartão completo!" e a faixa verde diz "Pode dar o prêmio." (e "Ficam 2
   carimbos para o próximo cartão." quando sobra), com **Dar o prêmio**.
   (cenas 09–12)
7. **Confirma.** "Dar o prêmio para Maria? Prêmio: uma lavagem grátis. Saem 10
   carimbos do cartão. Fica anotado que você deu. Ficam 2 para o próximo
   cartão." Botão **Dar o prêmio**. No histórico: "Ana deu o prêmio".
   (cena 13)
8. **Cupom.** Aba Cupons > **Criar cupom**: nome (só ela vê), o que dá (desconto
   em %, em dinheiro ou um presente), começo do código ("VOLTA") e quanto tempo
   vale. Ao lado, a mensagem como chega, com o código "VOLTA-7KD2". (cenas 14–15)
9. **Manda o cupom pela automação.** No relatório, o cupom ainda não mandado
   traz **Mandar este cupom**, que abre a automação pronta e desligada (como o
   "Usar o aviso" do passo 3). Lá, o passo **Mandar cupom** já tem o cupom e a
   mensagem escrita com o código, o que dá e até quando vale (o mesmo texto da
   prévia do Criar cupom). Cada cupom tem **Pausar** / **Ligar de novo** no
   topo; pausado, não oferece mandar. (cenas 16, 24–25)
10. **Cliente usa.** No balcão ou na conversa, o atendente digita o código em
    "O cliente mostrou um cupom?" e toca **Conferir**. Vê "Vale! 10% de
    desconto. De Maria Souza. Vale até 01/12." e toca **Marcar como usado**
    (marca o código como gasto; o desconto ela dá no caixa). A frase vira
    "Pronto, cupom marcado como usado. Dê 10% de desconto ao cliente." Ou marca
    pela ficha da pessoa, que pergunta antes ("Marcar o cupom VOLTA-7KD2 como
    usado? Depois disso ele não vale mais."). Já usado, vencido ou
    inexistente, a frase diz o que aconteceu e o que fazer. (cenas 18–21, 10b)
11. **Relatório.** Cada cupom mostra quantos foram mandados, quantos usaram (com a
    %) e quanto venderam. Quem não vê valores de venda vê um traço e "em
    vendas (você não vê valores)". (cenas 16–17)
12. **Presente pela automação.** O passo **Dar carimbos ou pontos** dá carimbos
    de presente (aniversário, indicação). A faixa azul lembra que a compra já dá
    carimbos sozinha, para ninguém dar em dobro. (cenas 22–23)

## 3. Telas (componentes desta onda)

| Cena | Componente | O que mostra |
|---|---|---|
| 01, 01b | `fidelidade/components/FidelidadeTela.vue` (aba cartão, sem programa) | herói com uma ação; sem poder |
| 02–04 | `fidelidade/components/MontarPrograma.vue` | form + cartão ao vivo; faltando; pontos |
| 05, 05b | `fidelidade/components/ProgramaPronto.vue` | pronto + 2 avisos prontos (carimbos; pontos) |
| 06–08, 08b–c | `FidelidadeTela` + `PainelDoCartao.vue` | painel; carregando; pausado; pausado sem poder; confirmar pausa |
| 09–12, 10b | `relacionamentos/components/ficha/SecaoFidelidade.vue` | vazio; meio; perto; completo; confirmar cupom usado |
| 13 | `relacionamentos/components/ficha/DialogoDarPremio.vue` | confirmar prêmio |
| 14, 16–17 | `FidelidadeTela` (aba Cupons) + `cupons/ListaDeCupons.vue` + `cupons/LinhaDoCupom.vue` | vazio; relatório; sem valores |
| 15, 03b | `cupons/MontarCupom.vue` | form + mensagem como chega; faltando |
| 18–21 | `cupons/ConferirCupom.vue` | vale; usado agora; vencido; não existe |
| 22–23 | `automacoes/livre/passosNovos/LivreDarCarimbos.vue` | passo; sem cartão |
| 24–25 | `automacoes/livre/passosNovos/LivreMandarCupom.vue` | passo; sem cupom |

Peças de apoio: `CartaoDeCarimbos.vue` (o cartão desenhado, também na ficha),
`EscolhaEmCartoes.vue` (rádio em cartões, input nativo),
`AbasDaFidelidade.vue`, `regras.js` (contas puras), `historico.js`,
`useTextosDaFidelidade.js`, `abas.js`, `passosNovos/fidelidadeNaAutomacao.js`.

Sem `<select>` nativo: escolhas por `ChoiceSelect` ou `EscolhaEmCartoes`. Toque
mínimo de 44 px (`min-h-11`). Só Tailwind, sem CSS próprio nem `style`.

## 4. Onde fica no menu

**Item novo "Fidelidade" no grupo CRESCER do menu novo
(`forkSidebarMenu.js`), logo depois de Campanhas; ícone `i-lucide-gift`; rota
`fidelidade_index` (`/accounts/:id/fidelidade?aba=cartao|cupons`).**

Por quê: CRESCER já reúne o que faz o cliente comprar de novo (Seus posts,
Campanhas). Fidelidade e cupom são isso, e o cupom anda junto com a campanha. As
outras opções perdem:

- Configurações (cartão em `settings_inicio`): o painel tem números e uma ação
  de todo dia ("quem está perto do prêmio"), não é ajuste de uma vez só.
- Dentro de Relacionamentos (aba): Relacionamentos é sobre pessoas. O programa
  é da conta, e a aba Cupons não tem a ver com a lista de pessoas.
- O que é da pessoa (saldo, prêmio, cupom dela) mora na ficha, em
  Relacionamentos.

No `Sidebar.vue`: entrada `{ name: 'Fidelidade', label: t('FIDELIDADE.TITULO'),
icon: 'i-lucide-gift', to: accountScopedRoute('fidelidade_index'), activeOn:
['fidelidade_index', 'fidelidade_montar', 'fidelidade_cupom_novo'] }`, com o gate
da flag e de `fidelidade_view`. Em `forkSidebarMenu.js`: `{ pega: 'Fidelidade' }`
em CRESCER (o `forkSidebarMenu.spec.js` acende se faltar). Menu antigo: o item
fica depois de Campanhas.

## 5. O que o backend vai precisar

### 5.1 PR 1: Fidelidade (cartão, ficha, prêmio, automação de carimbos)

**Migration (sozinha na fila).**

`fidelidade_programas`: um por conta.

- `account_id` (FK, índice único)
- `tipo` (string: `carimbos`|`pontos`)
- `a_cada_centavos` (bigint, > 0), `moeda` (string, `BRL`)
- `ganha` (integer, > 0)
- `meta` (integer, de 2 a 20 em carimbos, até 100.000 em pontos)
- `premio` (string(80), not null)
- `validade_meses` (integer, nulo = não vencem)
- `ligado` (boolean), `ligado_em`, `created_by_id`, `updated_by_id`, timestamps

`fidelidade_movimentos`: o histórico, só se acrescenta.

- `account_id`, `contact_id`, `programa_id` (FK)
- `tipo` (string: `compra`|`presente`|`ajuste`|`premio`|`venceu`|`estorno`)
- `quantos` (integer com sinal)
- `origem_type`/`origem_id`: o `Crm::Card` da compra, ou a execução da automação
- `user_id`: quem deu o prêmio ou fez o ajuste
- `valor_centavos`, `moeda`: a compra que gerou o movimento
- `motivo` (string(60))
- `vence_em` (nos de entrada, pela validade)
- `restante` (integer): quanto da entrada ainda não saiu, para vencer por ordem
  de chegada
- `created_at`

Índices em `(account_id, contact_id, created_at desc)` e um único parcial em
`(programa_id, origem_type, origem_id, tipo) where tipo in ('compra','estorno')`,
para o mesmo card não dar carimbo duas vezes.

`fidelidade_saldos`: o saldo pronto, para a ficha, o painel e o filtro.

- `account_id`, `contact_id`, `programa_id`, `saldo` (integer), `atualizado_em`
- índice único `(programa_id, contact_id)` e índice `(programa_id, saldo)`

Saldo e movimento mudam na mesma transação, com `lock` na linha do saldo. Assim
dois "Dar o prêmio" ao mesmo tempo não tiram 20 carimbos.

**Onde a compra vira carimbo.** Um serviço `Fidelidade::DarPelaCompra`, chamado
logo depois de `Relacionamentos::Compras::Recalcular` para os `contact_ids` da
venda. Mesmo evento e mesma trava; não é um caminho novo de "card ganho".

- Calcula `floor(valor / a_cada) * ganha`, sem guardar troco (a mesma conta de
  `regras.js#carimbosDaCompra`).
- Só para cards fechados depois de `ligado_em` (ver decisão D2).
- Só na moeda do programa.
- Card desfeito (reaberto, apagado, levado para outra pessoa) gera `estorno`. O
  saldo nunca fica negativo.
- Cruzou a meta: dispara o gatilho `contato.completou_cartao_fidelidade` depois
  do commit, uma vez por cartão completado.

**Jobs.**

- `Fidelidade::VencerJob`, diário (cron, junto da rotina diária de compras):
  vence as entradas com `vence_em < agora` e `restante > 0`, gerando `venceu`.
- `Fidelidade::RecalcularResumoJob`, ou cálculo direto com cache curto: os
  números do painel.
- Não enfileirar job de classe nova dentro da migration (lição do blue/green).

**Endpoints** (`/api/v1/accounts/:account_id/...`):

- `GET  fidelidade/programa`: o programa ou `null`
- `PUT  fidelidade/programa`: cria ou muda (`fidelidade_manage`). Mudar não mexe
  em quem já tem carimbos.
- `PATCH fidelidade/programa {ligado}`: pausa e liga de novo (`fidelidade_manage`);
  o painel tem "Pausar o cartão" (com confirmação) e "Ligar o cartão de novo".
- `GET  fidelidade/resumo`: `{ com_saldo, perto, premios_30d }` (`fidelidade_view`)
- `GET  relacionamentos/pessoas/:id/fidelidade`:
  `{ tem, vencem: {quantos, em}, historico: [5], historico_total, cupons }`.
  Mesmo acesso da ficha. `historico` paginado em `.../fidelidade/movimentos`.
- `POST relacionamentos/pessoas/:id/fidelidade/premios`: resgata. Confere
  `saldo >= meta` com lock e aceita chave de idempotência. Permissão: quem pode
  mexer no contato (ver D1).
- `POST relacionamentos/pessoas/:id/fidelidade/ajustes`: dar ou tirar à mão,
  só `fidelidade_manage`. Fica para depois se D1 recusar.
- Filtro da lista de Relacionamentos: `fidelidade=perto|completo`, para o "Ver
  quem está perto do prêmio".

**Automação.** No catálogo (`automacao-passos.yml` → `catalogo.rb`):

- Passo `dar_carimbos` (`quantos`, `motivo`), executor
  `Autonomia::Automacao::PassoDeDarCarimbos`, que grava movimento `presente`.
- Gatilho `contato.completou_cartao_fidelidade` (alvo Contato). Frase
  `FIDELIDADE.AUTOMACAO.GATILHO.NOME`.
- Valores em `catalogo_de_valores.rb`: `fidelidade.saldo`, `fidelidade.faltam`,
  `fidelidade.premio`, com as frases `FIDELIDADE.VALORES.*`, já no catálogo do
  painel.
- Duas receitas prontas: "Avisar o saldo depois de cada compra" (gatilho
  `card.ganho` + mensagem com o saldo) e "Avisar quando completar o cartão".
  O `ProgramaPronto` abre essas receitas.
- No painel: entrada em `PASSOS_NOVOS` com `requer: 'fidelidade'` e peça
  `LivreDarCarimbos` em `LivrePassoNovo.vue`.
- Ensaio e histórico do passo, no padrão de `passo_de_pesquisa.rb`.

**Permissões** (checklist da seção "Funções personalizadas" do CLAUDE.md):

- `fidelidade_view` e `fidelidade_manage` em `CustomRole::PERMISSIONS`; `_manage`
  implica `_view`. Sem função, só o administrador (OSS: `administrator?`).
- Policy/controller com `AccountUser#permission_granted?`.
- Módulo `LOYALTY` no grupo MARKETING de `permissionMatrix.js`, ícone
  `i-lucide-gift`, `levels: { view: 'fidelidade_view', manage: 'fidelidade_manage' }`.
- i18n `CUSTOM_ROLE.MATRIX` (en + pt_BR), `meta.permissions` da rota, entrada do
  menu, `useCanManage('fidelidade_manage')` em Criar, Mudar as regras e Novo
  cupom.
- Parecer da Funções antes do merge.
- Valor de venda no relatório do cupom: `sales_value_view` (já existe), não uma
  chave nova.

**Flag:** `fidelidade`, nasce ligada em todas as contas (regra do épico).

**Rotas do painel:** `fidelidade_index`, `fidelidade_montar` (novo e mudar) e,
no PR 2, `fidelidade_cupom_novo`. Na ficha: `SecaoFidelidade` no slot `#antes`
de `FichaDaPessoaPage.vue`, depois de `SecaoCompras`, com
`fichaFonte.fidelidade(id)` e a parte nova em `falhas`.

### 5.2 PR 2: Cupom

**Migration (sozinha na fila).**

`cupons`:

- `account_id`, `nome` (string(60))
- `oferta_tipo` (`porcentagem`|`valor`|`presente`), `oferta_valor` (integer: %
  ou centavos), `oferta_texto` (string(60)), `moeda`
- `prefixo` (string(8), A–Z0–9)
- `validade_dias` (7|15|30|60), `limite_por_cliente` (integer, default 1)
- `ligado`, `created_by_id`, timestamps

`cupom_codigos`: um por pessoa por cupom.

- `account_id`, `cupom_id`, `contact_id`
- `codigo`, índice único `(account_id, codigo)`
- `enviado_em`, `vale_ate`, `usos` (integer)
- `usado_em`, `usado_por_id`
- `automacao_execucao_id`
- índice único `(cupom_id, contact_id)`: mandar de novo reaproveita o código

**Código.** `PREFIXO-XXXX`, com 4 a 6 caracteres de um alfabeto sem
0/O/1/I/L, sorteados com `SecureRandom`. Tenta de novo quando o índice único
recusa. Sem regex: o mesmo jeito de `regras.js#prefixoLimpo`.

**Endpoints:**

- `GET/POST/PATCH fidelidade/cupons`: listar, criar, pausar
  (`fidelidade_manage`). A lista traz `mandados`, `usados` e `vendas` (por
  moeda; `null` sem `sales_value_view`).
- `POST fidelidade/cupons/conferir {codigo}`: devolve
  `{ estado: valido|usado|vencido|nao_existe, oferta, moeda, cliente, vale_ate, usado_em }`.
  Tem limite de tentativas por usuário (rack-attack), para ninguém adivinhar
  código. O nome do cliente só vai para quem pode ver o contato.
- `POST fidelidade/cupom_codigos/:id/usar`: idempotente, com lock. Grava
  `usado_em` e `usado_por_id`.

**Quanto vendeu.** A régua da F2: soma dos cards ganhos da pessoa entre o uso e
7 dias depois (ver D4). A frase está na tela ("Venda do cupom: compras de quem
usou, até 7 dias depois do uso").

**Automação:**

- Passo `mandar_cupom` (`cupom_id`, `texto`): gera ou reaproveita o código e
  manda a mensagem, com o modelo aprovado se a janela de 24 h estiver fechada,
  como a Pesquisa.
- Valores `cupom.codigo`, `cupom.oferta`, `cupom.vale_ate`.
- O painel recusa salvar sem o código no texto (`mandarCupomPronto`). O servidor
  recusa também.
- Receita pronta "Mandar este cupom": a automação com o passo `mandar_cupom`
  já com o `cupom_id` e o texto padrão, desligada (o relatório emite
  `mandarCupom` com o cupom; quem usa abre a receita, como o `ProgramaPronto`).
- O título do passo no "Alterar" é `FIDELIDADE.AUTOMACAO.DAR.TITULO` com a
  unidade do programa ("Dar carimbos" / "Dar pontos"); `NOME` fica para a lista
  de passos.

### 5.3 Guia e formatos

- `bundle exec rails autonomia:guia:formatos` (controllers novos) e
  `pnpm guia:build` (rotas novas) nos dois PRs.
- `pnpm i18n:fork:check` passa hoje com o catálogo novo.

## 6. Quantos PRs

**Dois.** Cada um com a sua migration, e cada um entra sozinho na fila.

1. **Fidelidade:** programa, painel, ficha (saldo, histórico, Dar o prêmio),
   passo "Dar carimbos", gatilho "completou o cartão", valores do saldo, receitas
   de aviso, permissão nova e menu. Fecha o primeiro "pronto quando" do #3100.
2. **Cupom:** cupons, códigos, conferir/usar, relatório, passo "Mandar cupom",
   valores do cupom e cupons na ficha. Fecha o segundo "pronto quando".

Por quê: as tabelas são independentes. A permissão e o menu nascem no PR 1. Um
PR só passaria de mil linhas com duas migrations, contra a regra "uma fase = um
PR revisável".

## 7. O que o Guia (`lib/operator_guide/porques.md`) vai explicar

Um bloco por fluxo (`onde_fica`, `intent`, `passos`, `gotchas`):

- `criar_cartao_fidelidade` (rota `fidelidade_montar`): carimbos x pontos; a
  compra é o card ganho; troco não passa; vale de hoje em diante; mudar a regra
  não mexe em quem já tem.
- `ver_painel_da_fidelidade` (rota `fidelidade_index`): o que cada número conta;
  "perto do prêmio" = falta até 20% da meta.
- `dar_premio_pela_ficha` (rota `relacionamentos_pessoa`): só com o cartão
  completo; sobra fica para o próximo; quem pode; fica anotado quem deu.
- `avisar_saldo_pelo_whatsapp`: as duas receitas; janela de 24 h e modelo
  aprovado.
- `criar_cupom` (rota `fidelidade_cupom_novo`): código por cliente; mandar de
  novo reaproveita; validade conta do recebimento.
- `conferir_e_usar_cupom` (rota `fidelidade_index`, aba Cupons, e ficha): os
  quatro resultados.
- `ver_quanto_o_cupom_vendeu`: régua de 7 dias; `sales_value_view`.
- `automacao_dar_carimbos_e_mandar_cupom` (rota `automacoes_livre_editar`):
  presente x compra (não dar em dobro); o gatilho "completou o cartão"; os
  dados novos do "Pôr um dado".

## 8. Decisões para o Rodrigo (só as que mudam o resultado)

**D1. Quem pode tocar em "Dar o prêmio" e "Usar cupom".**

- Contexto: o atendente está no balcão ou na conversa. O programa é coisa do
  dono.
- Opções:
  - (a) quem pode mexer no contato (agente comum incluso);
  - (b) só quem tem `fidelidade_manage`;
  - (c) quem pode mexer no contato, com o "dar/tirar à mão" só para
    `fidelidade_manage`.
- Trade-off: (b) trava o dia a dia. (a) deixa ajuste manual solto.
- **Recomendo (c).** O prêmio só sai com cartão completo e fica anotado quem deu.

**D2. Compras de antes de ligar o cartão contam?**

- Opções:
  - (a) não, vale de hoje em diante;
  - (b) sim, os últimos 90 dias entram ao ligar;
  - (c) a pessoa escolhe ao criar.
- Trade-off: (b) faz clientes antigos já "perto do prêmio" no primeiro dia, mas
  pode completar cartões de surpresa e um aviso automático disparar para
  muitos de uma vez. (c) põe uma pergunta a mais na tela.
- **Recomendo (a):** simples de explicar ("vale de hoje em diante", já escrito
  na tela). Sem aviso em massa.

**D3. Troco da compra passa para a próxima?**

- Opções:
  - (a) não: R$ 120 com "a cada R$ 50" dá 2 e os R$ 20 somem;
  - (b) sim: o resto acumula.
- Trade-off: (b) é mais justo, mas o cliente não entende por que uma compra de
  R$ 30 deu carimbo, e a conta fica escondida.
- **Recomendo (a)**, já escrito na tela ("O resto não passa para a próxima").

**D4. Como o cupom conta venda.**

- Opções:
  - (a) cards ganhos da pessoa até 7 dias depois do uso (régua da F2);
  - (b) o atendente digita o valor da compra ao usar;
  - (c) só conta usos, sem valor.
- Trade-off: (b) é exato, mas é mais um campo e dado duplicado com o card. (a)
  depende de o card ser marcado.
- **Recomendo (a)**, com a régua escrita no relatório.

**D5. Lugar no menu.**

- Opções:
  - (a) item próprio em CRESCER, depois de Campanhas;
  - (b) cartão em Configurações;
  - (c) aba de Relacionamentos.
- **Recomendo (a)** (seção 4).

## 9. Riscos

- **Aviso de saldo fora da janela de 24 h.** A compra no balcão quase nunca tem
  conversa aberta. No WhatsApp Oficial, o aviso precisa de modelo aprovado com
  variável (o saldo). Sem modelo, a mensagem não sai. A receita deve vir com o
  passo de modelo, como a Pesquisa.
- **Carimbo em dobro.** O card ganho dá carimbo sozinho. Uma automação de
  "card ganho → dar carimbos" dobraria. A faixa do passo avisa, e o ensaio deve
  avisar também.
- **Concorrência.** Dois resgates ou dois usos ao mesmo tempo: o lock na linha
  do saldo e do código, mais a idempotência, cobrem.
- **Adivinhar código.** Limite de tentativas no `conferir` e alfabeto de 30+
  símbolos com 4–6 caracteres.
- **Moeda.** O programa conta só a moeda dele. Card em outra moeda não dá
  carimbo e o Guia diz isso.
- **Repo público.** Os dados falsos das cenas usam nomes inventados (Maria
  Souza, Ana). Não há id de conta.

## 10. O que esta onda NÃO fez (de propósito)

- Nenhuma rota, menu, migration, model, controller ou entrada de catálogo.
- `SecaoFidelidade` não está encaixada na `FichaDaPessoaPage` (falta a fonte).
- Os passos não estão em `PASSOS_NOVOS` (apareceriam no editor sem motor).
- O harness `tmp-prints/` não vai para o PR.
- Sem "Desfazer" depois de marcar o cupom como usado nem de dar o prêmio: pede
  rota de desfazer no servidor. A ficha pergunta antes; o Conferir diz em
  palavras o que o botão faz ("Marcar como usado").
- "Criar cartão fidelidade" / "Criar cupom" dentro do passo da automação só
  emitem `criarPrograma` / `criarCupom`: quem encaixar o passo no editor
  precisa abrir em outra aba (ou guardar rascunho) para não perder a automação
  em montagem.

## 11. Servidor, etapa 1 (o que mudou do desenho)

Decisões do Rodrigo de 23/11 aplicadas como recomendado (D1 a D5). Onde o código
saiu diferente da seção 5, e por quê:

- **Uma migration só** (`20261123211000_create_fidelidade`, vaga dada pela
  Orquestração) com as cinco tabelas, inclusive as do cupom. As do cupom levam o
  prefixo do módulo: `fidelidade_cupons` e `fidelidade_cupom_codigos` (modelos
  `Fidelidade::Cupom` e `Fidelidade::CupomCodigo`), para não disputar nome com o
  upstream. Os endpoints do cupom ficam para a etapa do cupom.
- **`vez` no movimento.** O índice único é
  `(programa_id, contact_id, origem_type, origem_id, tipo, vez)` só para compra e
  estorno. Sem a `vez`, o card reaberto e ganho de novo, ou levado para outra
  pessoa, nunca mais dava carimbo. Com ela, o mesmo card não dá carimbo duas
  vezes na mesma vez, e a vez seguinte vale.
- **Valor do card mudou depois do ganho:** estorna e dá de novo pelo valor novo,
  se o card ainda conta. Com o cartão pausado, o valor novo não dá de novo.
- **Sem coluna de chave.** "Dar o prêmio" usa a idempotência que o fork já tem
  (`Crm::IdempotentRequests`, tabela `idempotency_keys`, cabeçalho
  `Idempotency-Key`), com o espaço `fidelidade_premio`.
- **Sem flag.** O cartão só existe quando a conta cria, e nasce ligado; pausar é
  do próprio cartão. A F1 (compras) também entrou sem flag. Uma flag pediria
  posição de bit e uma migration de ligar em todas, fora da vaga desta fase.
- **Pausar e ligar de novo:** ligar de novo põe `ligado_em` em agora; as compras
  da pausa não contam. O estorno acontece mesmo com o cartão pausado.
- **Ajuste para menos** maior que o saldo é recusado (422 `saldo_insuficiente`);
  o estorno da compra, não: ele tira o que houver e fecha com o resto em zero.
- **Resumo** traz também `completos` (quem já pode receber o prêmio).
- **Ficha:** `GET relacionamentos/pessoas/:id/fidelidade` traz o cartão da conta
  (`programa`) junto, porque o atendente sem `fidelidade_view` também precisa
  dele para desenhar o bloco. Sem cartão na conta, `null`.
- **Gatilho** `contato.completou_cartao_fidelidade` já está no catálogo da
  Automação (grupo Contato, sem parâmetro) e no Ensaio (quem está com o cartão
  completo). Dispara pela compra e pelo ajuste à mão.

Endpoints (`/api/v1/accounts/:account_id/...`):

| Verbo e caminho | Quem |
|---|---|
| `GET fidelidade/programa` | `fidelidade_view` |
| `PUT fidelidade/programa {programa: {tipo, a_cada, ganha, meta, premio, validade_meses}}` | `fidelidade_manage` |
| `PATCH fidelidade/programa {ligado}` | `fidelidade_manage` |
| `GET fidelidade/resumo` → `{com_saldo, perto, completos, premios_30d}` | `fidelidade_view` |
| `GET relacionamentos/pessoas/:id/fidelidade` | quem vê o contato |
| `GET relacionamentos/pessoas/:id/fidelidade/movimentos?pagina=N` (20 por página) | quem vê o contato |
| `POST relacionamentos/pessoas/:id/fidelidade/premios` (Idempotency-Key) | quem mexe no contato (D1) |
| `POST relacionamentos/pessoas/:id/fidelidade/ajustes {quantos, motivo}` | `fidelidade_manage` |
| `GET relacionamentos/pessoas?filtros[fidelidade]=perto\|completo` | quem vê a lista |

Rotina: `Fidelidade::VencerJob`, todo dia às 12h30 UTC (`config/schedule.yml`).
A compra vira carimbo dentro do `Relacionamentos::Compras::RecalcularJob`, logo
depois da `Recalcular`, com a mesma trava da conta (venda e rotina diária).

Fica para as próximas etapas: a matriz de funções no painel
(`permissionMatrix.js`, Funções da equipe, `CUSTOM_ROLE.MATRIX`), rotas, menu e
ligação das telas, os blocos do Guia (`porques.md`), o passo "Dar carimbos", os
valores do "Pôr um dado", as receitas prontas e todo o cupom (endpoints, código,
conferir, usar, relatório, passo "Mandar cupom").
