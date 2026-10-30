# Funis da corretora (F2, #1802), rascunho para o Multifunnel e o Rodrigo

Status: **implementado na worktree, esperando o Rodrigo aprovar a jornada no painel do M2**. Base `f5e9ef48c4`. Revisão do Multifunnel (18/10) incorporada abaixo.

## Regras do Rodrigo (18/10)

- O funil que já existe nas contas, em produção, **não muda**: não muda nome nem etapa. Pode melhorar só a **descrição** que a IA usa para mover o card, sempre com o Multifunnel.
- Os modelos de "Começar pronto" de hoje continuam iguais para todo mundo. A corretora **ganha modelos a mais**.
- Nome de etapa **curto**: no máximo 2 ou 3 palavras, como os de hoje (o maior é "Esperando o cliente").
- Cada modelo chega pronto, com nome, etapas, a descrição de cada etapa (para a IA que move o card) e a descrição do funil (para a IA de assunto saber qual conversa é deste funil).
- UI e UX premium, com jornada simples (QI 70).
- Conta com perfil geral vê o texto geral.
- Os critérios descrevem só o que **aparece na conversa**: a IA não vê o portal da seguradora. Os textos abaixo são os mesmos dos yml (`config/locales/crm_stage_criteria.pt_BR.yml` e `config/pacotes/seguros/corretora/pt_BR.yml`).

## O que existe hoje

| Onde | O que é |
|---|---|
| Funis antigos das contas (ex.: conta 18) | Novo · Em atendimento · Proposta · Fechamento · Perdido. A IA usa os critérios `crm.stage_criteria.legado.*`, achados pelo nome da etapa (`DefaultStageCriteria::NAME_KEYS`) |
| Modelo "Vendas" ao criar funil (main) | Novo contato · Em conversa · Proposta enviada · Negociação · Fechado (`vendas.e1..e5`) |
| Modelos de Atender | Suporte, Pós-venda, Cobrança, Agendamento |
| Descrição do funil | "Use o funil {nome} quando o cliente…", mais as ideias (`CRM_FUNIL.SOBRE.IDEIAS.*`) |

## Proposta

### 1. Funis que já existem (legado): só a descrição muda, no pacote da corretora

Os nomes das etapas ficam. Os critérios `legado.*` ganham versão de corretor em `config/pacotes/seguros/corretora/pt_BR.yml`:

| Etapa | Critério para a corretora |
|---|---|
| Novo | O cliente chegou agora: mandou a primeira mensagem ou pediu uma cotação. Ainda não disse o ramo nem mandou os dados do seguro. |
| Em atendimento | O cliente está mandando os dados para cotar (ramo, placa ou endereço, CEP de pernoite, condutor, seguradora atual), ou a equipe disse que está cotando. Ainda não mandou as opções. |
| Proposta | A equipe já mandou as opções da cotação e o cliente está comparando ou pensando. Ainda não disse qual vai fechar. |
| Fechamento | O cliente escolheu a opção e disse que quer fechar: pediu o link de pagamento, mandou os dados do cartão ou pediu para emitir. |
| Perdido | O cliente não vai fechar: achou caro, fechou com outra corretora, a seguradora não aceitou ou parou de responder. (O texto da F1 continua.) |

### 2. Modelos novos que só a corretora vê ao criar funil

| Tipo | Modelo | Etapas (curtas) | Fim |
|---|---|---|---|
| Vender | **Venda de seguro** (o "Vendas" com a fala do corretor) | Novo contato · Cotando · Opções enviadas · Negociação · Fechado | Seguro ativo / Não fechou |
| Vender | **Renovação** | A vencer · Cotando · Opções enviadas · Negociação · Renovado | Renovou / Não renovou |
| Atender | **Sinistro** | Aberto · Em análise · Falta documento · Encerrado | Encerrado |
| Atender | **Endosso** | Pedido · Na seguradora · Falta documento · Feito | Feito |
| Atender | Cobrança (igual hoje) | A vencer · Atrasado · Prometeu pagar · Pago | Pago |

Decidido (Multifunnel): a "Venda de seguro" **é o próprio modelo Vendas** (`VENDAS`), com nome, texto, etapas, ideias e critérios trocados no pacote `seguros/corretora`. Fica **no lugar** do "Vendas", sem modelo novo.

#### Venda de seguro

- **Descrição do funil:** "Use o funil Venda de seguro quando o cliente… quer fazer um seguro novo ou pede uma cotação."
  - Ideias: "pede uma cotação" · "quer saber quanto fica o seguro" · "quer fazer o seguro do carro, da casa ou da empresa"
- **Etapas:**
  - **Novo contato:** O cliente chegou agora e quer um seguro. Ainda não disse o ramo nem mandou os dados para cotar.
  - **Cotando:** O cliente está mandando os dados para cotar, ou a equipe disse que está cotando. Ainda não mandou as opções.
  - **Opções enviadas:** A equipe mandou as opções da cotação e o cliente está pensando ou comparando. Ainda não escolheu.
  - **Negociação:** O cliente quer fechar, mas está acertando detalhes: desconto, franquia, cobertura, forma de pagamento ou parcelas.
  - **Fechado:** O cliente escolheu a opção e disse sim: mandou os dados para pagar ou pediu para emitir.

#### Renovação

- **Descrição do funil:** "Use o funil Renovação quando o cliente… já tem seguro com a gente e ele está perto de vencer."
  - Ideias: "está com o seguro perto de vencer" · "quer renovar o seguro" · "recebeu o aviso de renovação" (a primeira já vem no "Quando usar")
- **Etapas:**
  - **A vencer:** Falamos com o cliente da renovação do seguro que vai vencer, mas ainda não começamos a cotar.
  - **Cotando:** A equipe disse ao cliente que está cotando a renovação. Ainda não mandou as opções.
  - **Opções enviadas:** A equipe mandou as opções da renovação e o cliente ainda não escolheu.
  - **Negociação:** O cliente quer renovar, mas está acertando detalhes: desconto, cobertura ou forma de pagamento.
  - **Renovado:** O cliente disse que aceita a renovação: escolheu a opção, mandou os dados para pagar ou pediu para emitir.
- **Fim:** Renovou / Não renovou, gravados em `metadata.outcome_labels` ao criar. O "Não renovou" usa os motivos rápidos da corretora (os mesmos da venda): "Achou caro", "Parou de responder", "Fechou com outra corretora", "A seguradora recusou".

#### Sinistro

- **Descrição do funil:** "Use o funil Sinistro quando o cliente… bateu o carro, teve um roubo, um dano na casa ou precisa acionar o seguro."
  - Ideias: "bateu o carro ou teve um dano" · "foi roubado" · "quer acionar o seguro" (três, como os outros modelos)
- **Etapas:**
  - **Aberto:** O cliente contou que teve um sinistro (batida, roubo ou dano) e a equipe ainda não disse que abriu o aviso.
  - **Em análise:** A equipe disse ao cliente que abriu o sinistro (deu protocolo ou número) e a seguradora está analisando. A vez é da seguradora.
  - **Falta documento:** A equipe pediu ao cliente um documento, foto ou boletim de ocorrência e ele ainda não mandou.
  - **Encerrado:** A equipe contou ao cliente a resposta da seguradora sobre o sinistro.
- **Categorias:** E3 é a espera do cliente (pausa o prazo). E2 é andamento, porque é a corretora quem cobra a seguradora.

#### Endosso

- **Descrição do funil:** "Use o funil Endosso quando o cliente… quer trocar o carro, mudar o endereço, incluir um motorista ou mudar algo no seguro."
  - Ideias: "trocou de carro" · "mudou de endereço" · "quer incluir um motorista" (segunda via não é endosso: saiu)
- **Etapas:**
  - **Pedido:** O cliente pediu uma mudança no seguro e a equipe ainda não disse que pediu à seguradora.
  - **Na seguradora:** A equipe avisou o cliente que pediu a mudança à seguradora e está esperando a resposta dela.
  - **Falta documento:** A equipe pediu ao cliente um documento ou um dado e ele ainda não mandou.
  - **Feito:** A equipe avisou o cliente que a mudança foi feita ou mandou a apólice nova.

## Revisão do Multifunnel (18/10) e como ficou

1. **Venda de seguro = VENDAS.** `CRM_FUNIL.MODELOS.VENDAS.*` e `CRM_FUNIL.SOBRE.IDEIAS.{PRECO,COMPRAR,COMO_FUNCIONA}` em `app/javascript/dashboard/i18n/pacotes/seguros/corretora/{pt_BR,en}.json`; `crm.stage_criteria.vendas.e1..e5` em `config/pacotes/seguros/corretora/{pt_BR,en}.yml`. As duas pastas não precisam de registro: o painel acha por `import.meta.glob('./pacotes/**/*.json')` e o servidor (`Autonomia::Segmentos::Catalogo`) usa a pasta como camada; `corretora` já estava em `config/fork_i18n.json`.
2. **Funis antigos:** `crm.stage_criteria.legado.{novo,em_atendimento,proposta,fechamento}` no pacote da corretora, com o texto da tabela acima. O `legado.perdido` **não** foi mexido: fica o da camada `seguros` (F1).
3. **Modelos novos** (`funil.js`): `RENOVACAO` (Vender, `venda: true`), `SINISTRO` e `ENDOSSO` (Atender), com `camadas: ['seguros/corretora']`. `modelosDoTipo(tipo, pacote)` filtra pela camada com `camadasDoPacote`; conta sem pacote (ou outro tipo de seguros) vê a lista de hoje. Sinistro e Endosso vêm **antes** dos modelos de todos no Atender, só na corretora: lá o primeiro já marcado é o Sinistro. Na conta geral a ordem e o modelo já marcado (Suporte) são os de hoje. Servidor: chaves novas em `Crm::Pipeline::TEMPLATES` e `RENOVACAO` em `DefaultStageCriteria::SELL_TEMPLATES`. `NAME_KEYS` não mudou: os nomes novos só acham critério por modelo e posição.
4. **Desfechos do modelo:** `sucesso` e `falha` no item do modelo (`MODELOS.<X>.SUCESSO`/`.FALHA`), em qualquer tipo. Renovação: "Renovou"/"Não renovou"; Sinistro: "Encerrado"; Endosso: "Feito". Só nos funis que nasceram de um modelo da corretora (`metadata.template` em RENOVACAO, SINISTRO ou ENDOSSO, lista `MODELOS_DE_CAMADA` em `funil.js`, ex-`MODELOS_DA_CORRETORA`), o diálogo de "não deu certo" e o aviso depois de marcar usam o nome próprio ("Não renovou: o que houve?", "Marcar: Não renovou", "Marcado: Renovou."). Todos os outros funis, inclusive a Cobrança e qualquer funil de conta geral com nome próprio, ficam com o texto de hoje. Com dois modelos de Vender, a pergunta acima deles é "Que tipo de venda?" (`CRM_FUNIL.TIPO.MODELO_VENDER`).
5. **Critérios dos modelos novos:** `crm.stage_criteria.{renovacao,sinistro,endosso}.e<n>` na base (`config/locales/crm_stage_criteria.{pt_BR,en}.yml`). Nomes, textos e ideias dos modelos novos também na base do `crm.json` (en + pt_BR).
6. **Motivos rápidos:** `CRM_CARD.DESFECHO.MOTIVO.{PRECO,SUMIU,OUTRO_LUGAR,NAO_ERA_HORA}` no pacote da corretora: "Achou caro", "Parou de responder", "Fechou com outra corretora", "A seguradora recusou".
7. **Categorias:** posicionais (Novo, Em andamento, Esperando o cliente, Resolvido), sem variante.
8. `Autonomia::Insurance::AutoRenewal` (Lia) não foi tocado.

## Proposta separada para o Rodrigo

Usar o nome próprio do desfecho (`metadata.outcome_labels`) em **toda** conta, não só nos modelos da corretora. Hoje o selo e os botões do card já usam esse nome em qualquer funil; o diálogo de "não deu certo" num funil de Vender e o aviso depois de marcar, não. Com a proposta, os quatro passariam a falar a mesma língua.

O que muda para a conta geral:

- **Cobrança** (nome "Pago"): o aviso ao marcar passa de "Card marcado como resolvido." para "Marcado: Pago.".
- **Funil de venda com nome próprio** (ex.: "Contratado" / "Desistiu"): o aviso passa de "Negócio marcado como ganho." / "Negócio marcado como perdido." para "Marcado: Contratado." / "Marcado: Desistiu."; o diálogo de "não deu certo" passa de "Este negócio não deu certo?" / "Marcar como perdido" para "Desistiu: o que houve?" / "Marcar: Desistiu".
- Funil sem nome próprio: nada muda.

Para ligar, basta `usaNomeDoDesfecho` (funil.js) valer para todo funil com `outcome_labels`. Fica fora deste PR até o OK do Rodrigo.
