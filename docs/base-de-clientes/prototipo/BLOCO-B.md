# Protótipo — Bloco B: Carteira e renovação (E4, E5, E6, E7, E8)

Especificação de tela para o protótipo de tela real do épico #1240 (Issue #2893, bloco B). Quem constrói segue este
documento; quem julga (banca) compara a tela com ele. Flag: `carteira_seguros` (posição 46 da `feature_flags_ext_2`),
sempre junto com `relacionamentos_novo`. Só aparece em conta do segmento Seguros. Dados do protótipo: adaptador falso,
com nomes fictícios e números que batem entre as telas.

**Regra de ouro:** UI-UX e design premium, com uma jornada tão simples que uma pessoa de QI 70, sem conhecimento de
tecnologia, consegue usar.

O bloco B mora em cima do bloco A (`feat/2894-relacionamentos-novo`, PR #2910). Onde este documento não fala de uma
peça, ela é igual ao bloco A.

## Regras para todas as telas

- Tudo do bloco A vale aqui: uma frase e uma ação principal por tela (o único botão preenchido); tela vazia = uma frase
  e um botão; carregando = esqueleto; erro = "Não consegui …. Tente de novo." + **Tentar de novo**; 390 px em uma
  coluna; alvo de toque de 44 px; teclado e leitor de tela; gaveta e diálogo prendem o foco e fecham com Esc; herói
  escuro `#0D2344`; cartões brancos de canto arredondado.
- Palavra do corretor. Usamos: "seguro", "apólice", "seguradora", "tipo de seguro", "começa", "termina", "vence",
  "valor do seguro", "renovação", "renovou", "não renovou", "endosso", "proposta", "cotar", "trazer". Nunca:
  "vigência", "ramo", "prêmio", "sincronizar", "importar", "campo", "coluna" (fora da planilha do próprio cliente),
  "API", "IA", "status", "registro".
- Soltar o cliente. Nenhum teto, prazo ou "no máximo". Botão que não pode agir abre e diz por quê e o que resolve. Só
  fica desligado o que não tem o que enviar (campo vazio, zero pessoas). Sem confirmação a mais. Custo de leitura por
  IA aparece em reais antes de começar, sem pedir licença.
- CPF e CNPJ à vista, com copiar, como qualquer informação. Nenhuma tela de "dado protegido".
- Se a corretora escolheu "sai sozinha", a tela só informa o que saiu. Nunca pede aprovação de novo.
- Mostrar antes de fazer e deixar desfazer, sem prazo.
- Sem `<select>` nativo: escolha única é `ChoiceSelect`; escolha grande é `CartoesDeEscolha` do bloco A. Telefone é
  `CampoDeTelefone`. Data é o campo de data da casa.
- Diálogo que age sobre pessoas diz quem entra pelo nome e quem fica de fora com o motivo.
- Seção vazia é só uma frase. Nome não é cortado; e-mail só quebra no "@".
- Textos no catálogo do fork, `pt_BR` e `en` juntos, num arquivo próprio de seguros
  (`relacionamentosCarteira.json`), usado só quando a conta é do segmento Seguros. Nenhuma palavra de seguro nos
  catálogos do bloco A.
- Seletores novos usam `data-carteira="…"`. Peças do bloco A reaproveitadas mantêm o `data-relacionamentos` delas.

## Dados da demonstração

Mesma conta fictícia do bloco A (280 pessoas, 120 clientes, 38 empresas; `demo/base.js`). O bloco B soma a carteira
dessa conta. Tudo é inventado e sempre igual; as datas são relativas a hoje, para os grupos não envelhecerem.

**Arquivos novos (só em desenvolvimento, como no bloco A):** `demo/carteira.js` (seguros, histórias, cards de
renovação, ajustes, resultados), `demo/trazerSeguros.js` (planilha, PDFs e Agger de exemplo), `fonte/carteiraFonte.js`,
`fonte/selosDoSeguro.js` (selo pela data de hoje, função pura usada pela tela e pela fonte),
`fonte/gruposDeSeguros.js`. Um teste da fonte confere cada número das tabelas abaixo.

**Estados da demo** (`fonte/modoDemo.js` ganha dois):

| `?demo=` | O que mostra |
|---|---|
| `cheio` | Conta de seguros com a carteira cheia (tabelas abaixo). Agger ligado, cotação ligada. |
| `sem-seguros` | Conta de seguros com as 280 pessoas e nenhum seguro. Agger não ligado. Ponto de partida das jornadas de trazer. |
| `vazio` | Conta de seguros sem ninguém e sem seguro. |
| `fora-do-segmento` | As 280 pessoas, flag ligada, conta de outro segmento: nada de seguro aparece. |
| `carregando` · `desligado` | Esqueleto · erro, como no bloco A. |

`?demo-carteira=carregando|erro` muda só a fonte da carteira: a ficha aparece inteira e só o bloco Seguros (ou a
gaveta, o card, o painel da conversa) fica no esqueleto ou no erro. Serve para fotografar o estado de cada peça.

### A carteira (`?demo=cheio`)

168 seguros de 120 pessoas (os 120 clientes do bloco A). 84 pessoas têm um seguro, 24 têm dois, 12 têm três.

| Selo | Quantos | Regra (pela data de hoje, no fuso da conta) |
|---|---|---|
| Ativo | 98 | Termina daqui a mais de 60 dias. |
| Em renovação | 22 | Termina em até 60 dias e tem card de renovação aberto. |
| Renovado | 4 | O card fechou em "Renovou" e falta a apólice nova (seguradora sem Agger). |
| Vencido | 41 | Terminou e não foi renovado. |
| Cancelado | 3 | Alguém marcou como cancelado. |

Por vencimento (entre os 120 Ativo + Em renovação): em até 7 dias **5**; em até 30 dias **17**; em até 60 dias **22**
(os mesmos 22 Em renovação); em até 90 dias **31**.

| Tipo de seguro | Seguros | | Seguradora (inventada) | Seguros | De onde veio |
|---|---|---|---|---|---|
| Auto | 74 | | Seguradora Atlântica | 64 | Agger |
| Residencial | 46 | | Horizonte Seguros | 52 | Agger |
| Vida | 30 | | Serra Azul Seguros | 40 | Agger |
| Empresarial | 18 | | Seguradora Aurora | 12 | planilha "Carteira 2026.xlsx" (falta a senha dela no Agger) |

Outros grupos: Sem telefone **4** seguros (3 pessoas: Tiago Dornelaz com dois, Otávio Albuquerino, Gabriela
Carvalhedo); Parcela atrasada **3** (Karina Brandolim, Paula Carvalhedo, Inês Lourenzatto); Só tem um seguro **84**
pessoas. Quem cuida dos cards: Bia Lunardelli e Caio Tavarone (equipe fictícia). O agente da conta se chama Lia.

### Seguros com nome (as jornadas passam por eles)

| id | Pessoa (id) | Seguro | Situação |
|---|---|---|---|
| 1 | Fábio Figueirão (23) | Auto · Seguradora Atlântica · nº AT-000451 · R$ 2.760,00 · carro hatch prata, placa FIC-0A23 | Em renovação, termina em 18 dias. Card em "Opções enviadas", cuida Bia Lunardelli. Proposta R$ 2.980,80 (subiu 8%), enviada por Bia há 5 dias. |
| 2 | Fábio Figueirão (23) | Residencial · Horizonte Seguros · nº HZ-002318 · R$ 640,00 · apartamento em São Paulo | Ativo, termina em 214 dias. Endosso há 6 dias (valor 610,00 → 640,00). |
| 3 | Fábio Figueirão (23) | Vida · Serra Azul Seguros · nº SA-118802 · R$ 1.150,00 | Ativo, termina em 331 dias. Começou na data de "Cliente desde" dele. |
| 107 | Nádia Guedelha (4) | Auto · Horizonte · nº HZ-004410 · R$ 1.980,00 | Em renovação, termina em 3 dias. Card em "Cotando", cotação em andamento. |
| 110 | Marina Dornelaz (117) | Vida · Serra Azul · nº SA-120077 · R$ 890,00 | Em renovação, termina em 2 dias. Faltou um dado para cotar; a Lia perguntou. |
| 111 | Inês Albuquerino (29) | Residencial · Atlântica · nº AT-000903 · R$ 520,00 | Em renovação, termina em 5 dias. |
| 112 | Paula Brandolim (24) | Auto · Atlântica · nº AT-001288 · R$ 3.410,00 | Em renovação, termina em 6 dias. Proposta pronta (resumo da cotação), esperando alguém enviar. |
| 113 | Bruno Nogueirão (105) | Auto · Horizonte · nº HZ-005160 · R$ 2.150,00 | Em renovação, termina em 7 dias. Proposta enviada sozinha há 2 dias. |
| 104 | Tiago Dornelaz (59) | Residencial · Serra Azul · nº SA-119340 · R$ 700,00 | Em renovação, termina em 25 dias, sem telefone. |
| 105 | Otávio Nogueirão (203) | Auto · Atlântica · nº AT-001502 · R$ 2.300,00 | Em renovação, termina em 40 dias. Pediu para não receber mensagens. |
| 102 | Tiago Imbirussu (38) | Auto · Seguradora Aurora · nº AU-77031 · R$ 2.050,00 | Renovado há 3 dias; falta a apólice nova. Veio da planilha. |
| 103 | Elisa Mendonzela (41) | Auto · Horizonte · nº HZ-003975 · R$ 1.760,00 | Vencido há 12 dias. Não renovou: achou caro. |
| 101 | Paula Ourivesco (72) | Residencial · Atlântica · nº AT-000777 · R$ 480,00 | Cancelado há 40 dias. |
| 106 | Escritório Lourenzatto (empresa 23) | Empresarial · Atlântica · nº AT-002044 · R$ 6.900,00 | Ativo, termina em 150 dias. Segurado é a empresa (CNPJ). |
| 108 | Karina Brandolim (13) | Auto · Horizonte · nº HZ-006021 · R$ 2.480,00 | Ativo, parcela de 10 dias atrás em aberto. |
| 109 | Hugo Dornelaz (48) | Auto · Atlântica · nº AT-002210 · R$ 2.190,00 | Ativo, apólice nova saiu há 3 dias (renovação). Texto em palavras simples esperando envio. |
| 120 | Nádia Carvalhedo (20, não é cliente) | Auto · "Outra Corretora" · Seguradora Aurora · termina em 101 dias | Em outra corretora, com lembrete. Não conta nos 168. |

### Resultados das renovações

| Período | Venceram | Renovou | Não renovou | Motivos (achou caro · foi para outra corretora · vendeu o bem · não respondeu) |
|---|---|---|---|---|
| Últimos 30 dias | 19 | 14 | 5 | 2 · 1 · 1 · 1 |
| Últimos 90 dias | 52 | 41 | 11 | 5 · 3 · 1 · 2 |
| Últimos 12 meses | 190 | 151 | 39 | 17 · 10 · 5 · 7 |

Recortes (renovou de venceram):

| | 30 dias | 90 dias | 12 meses |
|---|---|---|---|
| Auto | 7 de 9 | 19 de 24 | 70 de 88 |
| Residencial | 4 de 5 | 12 de 14 | 43 de 52 |
| Vida | 2 de 3 | 6 de 8 | 23 de 30 |
| Empresarial | 1 de 2 | 4 de 6 | 15 de 20 |
| Seguradora Atlântica | 6 de 8 | 16 de 20 | 58 de 72 |
| Horizonte Seguros | 5 de 6 | 13 de 16 | 46 de 58 |
| Serra Azul Seguros | 2 de 3 | 8 de 10 | 32 de 40 |
| Seguradora Aurora | 1 de 2 | 4 de 6 | 15 de 20 |
| Bia Lunardelli | 8 de 11 | 24 de 30 | 87 de 108 |
| Caio Tavarone | 6 de 8 | 17 de 22 | 64 de 82 |

Os 39 "não renovou" dos 12 meses mais 2 mais antigos são os 41 Vencido da carteira. Cotações nos últimos 30 dias: 14.

---

## Tela 1 — Relacionamentos › aba Seguros (E4)

**Para que serve:** ver os seguros da carteira e achar os que pedem atenção agora.
**Ação principal:** o botão do herói.

Rota: a lista do bloco A com `?aba=seguros`. A aba **Seguros** aparece depois de Pessoas e Empresas, só em conta de
seguros com a flag. De cima para baixo:

1. **Herói escuro.** Frase escolhida nesta ordem (fala só do grupo para onde o botão leva):
   - sem seguro → "Traga os seguros dos seus clientes." · apoio "Eles aparecem aqui e na ficha de cada pessoa." ·
     **Trazer meus seguros** (leva à Tela 8);
   - algum vence em até 7 dias → "5 seguros vencem nos próximos 7 dias." · apoio, se todos estão em renovação, "Todos
     já estão em renovação." · **Ver quais** (abre o grupo "Vence em até 7 dias");
   - algum em renovação → "22 seguros estão em renovação." · **Ver quais** (grupo "Em renovação");
   - senão → "Você tem 168 seguros. Nenhum vence nos próximos 90 dias." · **Ver todos**.
   No canto, botão discreto **Trazer seguros** (quando não é o principal).
2. **Abas:** Pessoas · Empresas · Seguros.
3. **Grupos** em pílulas (componente `PilulasDeGrupo`), com a linha de explicação embaixo:

   | Grupo | Número (cheio) | Linha de explicação |
   |---|---|---|
   | Todos | 168 | (sem linha, como no bloco A) |
   | Vence em até 7 dias | 5 | Seguros que terminam nesta semana. |
   | Vence em até 30 dias | 17 | Seguros que terminam no próximo mês. |
   | Vence em até 90 dias | 31 | Seguros que terminam nos próximos três meses. |
   | Em renovação | 22 | Já têm card de renovação andando. |
   | Vencido | 41 | Terminaram e não foram renovados. |
   | Sem telefone | 4 | A pessoa está sem telefone. A mensagem da renovação não chega. |
   | Parcela atrasada | 3 | Tem parcela em aberto. Avise antes de o seguro cair. (só com Agger ligado) |

4. **Busca** "Buscar por nome, documento, placa ou número da apólice". Ao lado: **Ordenar** (Vence primeiro · Nome ·
   Mais novos), **Mais filtros** (gaveta do bloco A com: Tipo de seguro · Seguradora · Quem cuida), e dois botões
   discretos: **Resultados** (Tela 14) e **Ajustar renovações** (Tela 13). Em 390 px os dois vão para o menu "⋯".
5. **Lista, um seguro por linha.** Caixa de marcar · iniciais da pessoa · nome da pessoa (inteiro) · selo do seguro.
   Segunda linha: "Auto · Seguradora Atlântica · vence em 18 dias (29/11)". Variações da segunda linha: "venceu há 12
   dias", "cancelado em 02/10", "renovou em 08/11 · falta a apólice nova", "Sem telefone" no lugar do vencimento quando
   for o caso de mostrar. Botão **Conversar** sempre visível em 1440 (como no bloco A). Clicar na linha abre a gaveta
   do seguro (Tela 4) por cima da lista.
6. **Mostrar mais** (mais 25), "Mostrando 25 de 168".
7. **Barra de ação em grupo** ao marcar: "3 marcados" · **Mandar mensagem** (principal) · link "Marcar todos os 17
   deste grupo". Mandar mensagem abre o diálogo do bloco A (`DialogoMandarMensagem`), por pessoa, sem repetir quem tem
   dois seguros marcados: "Marina Dornelaz e Nádia Guedelha vão receber." · "Tiago Dornelaz fica de fora: está sem
   telefone." · "Você escreve a mensagem no próximo passo." · **Continuar** (leva à criação da campanha com essas
   pessoas, como no bloco A).

**Selos** (`SeloDeEstado` do bloco A, cores dos tokens da casa): **Ativo** (verde) · **Em renovação** (azul) ·
**Renovado** (verde com ✓) · **Vencido** (vermelho) · **Cancelado** (cinza) · **Parcela atrasada** (âmbar, ao lado do
outro selo) · **Em outra corretora** (cinza azulado).

**Estados:**
- cheio: como acima;
- sem seguro (`sem-seguros`): só o herói "Traga os seguros dos seus clientes." com o botão; abaixo, nada;
- grupo vazio: "Nenhum seguro neste grupo agora.";
- busca sem resultado: "Não achei nenhum seguro com “…”." + **Limpar busca**;
- carregando: herói em esqueleto e `EsqueletoDeLista`;
- erro: "Não consegui mostrar os seguros. Tente de novo." + **Tentar de novo** (`ErroComTentarDeNovo`).

**Em 390 px:** herói, abas (rolam se não couberem), pílulas que rolam com degradê, busca em largura inteira, Ordenar e
Mais filtros lado a lado, "⋯" com Resultados e Ajustar renovações, lista em uma coluna, Conversar como ícone de 44 px
com rótulo para leitor de tela.

**Seletores:** `aba-seguros` (vem do bloco A: `data-relacionamentos="aba-seguros"`), `data-carteira="heroi"`,
`heroi-acao`, `grupos`, `busca`, `resultados`, `ajustar`, `linha` (com `data-apolice="<id>"`), `selo`,
`marcar`, `barra`, `mandar-mensagem`, `vazio`, `carregando`, `erro`.

**Reaproveita do bloco A:** `HeroiEscuro`, `AbasDaLista`, `PilulasDeGrupo`, `CampoDeBusca`, `BarraDeControles`,
`GavetaDeFiltros`, `ListaDeLinhas`, `MostrarMais`, `BarraDeAcaoEmGrupo`, `DialogoMandarMensagem`, `SeloDeEstado`,
`EsqueletoDeLista`, `ErroComTentarDeNovo`, `MenuMais`. Novo: `LinhaDeSeguro.vue`.

## Tela 2 — Relacionamentos › aba Pessoas, em conta de seguros (E4)

**Para que serve:** a mesma lista do bloco A, agora dizendo qual seguro de cada pessoa pede atenção.
**Ação principal:** a do bloco A (o herói não muda).

O que muda em relação ao bloco A:
1. Na linha da pessoa, depois do selo **Cliente**, o selo do seguro mais urgente dela, só quando não é Ativo nem
   Cancelado. Ordem de urgência: Vencido > Parcela atrasada > Em renovação > Renovado. Na segunda linha, depois da
   última conversa: "· Auto vence em 18 dias" (só quando o selo é Em renovação).
2. Um grupo novo, depois de "Clientes": **Só tem um seguro** · 84 · "Clientes com um seguro só. Boa hora para
   oferecer outro."
3. A busca aceita placa e número da apólice ("Buscar por nome, telefone, documento ou placa").
4. Na aba Empresas, a linha da empresa mostra o selo do seguro mais urgente das apólices em nome dela, pela mesma
   regra.

Estados, 390 px e seletores: os do bloco A. Novos: `data-carteira="selo-da-pessoa"`, grupo `so_um_seguro` nas pílulas.

## Tela 3 — Ficha da pessoa › Seguros (E4)

**Para que serve:** ver, na ficha, os seguros que a pessoa tem com você.
**Ação principal:** a da ficha do bloco A (**Conversar**). O bloco Seguros não tem botão cheio.

O bloco **Seguros** é o primeiro da coluna principal, antes de Conversas (é o "o que tem comigo"). Cartão
`CartaoDaSecao` com o título "Seguros (3)".

Cada seguro, uma linha: ícone do tipo · **Auto** · selo · "Seguradora Atlântica · nº AT-000451" · "Vence em 18 dias ·
29/11/2026" · botão **PDF** (abre o PDF numa aba nova; rótulo de leitor "Ver o PDF do seguro Auto"). Clicar na linha
abre a gaveta do seguro (Tela 4). Ordem: o mais urgente primeiro, depois por data de término.

Linhas especiais:
- Vencido: "Venceu há 12 dias".
- Renovado: "Renovou em 08/11 · falta a apólice nova".
- Cancelado: "Cancelado em 02/10", em cinza, no fim da lista.
- Sem PDF: no lugar do botão PDF, botão **Anexar PDF** (abre a Tela 6).
- Em outra corretora (Nádia Carvalhedo, quem ainda não é cliente): "Auto · Seguradora Aurora · está em outra
  corretora" · selo **Em outra corretora** · "Vamos lembrar você em 22/12, 60 dias antes de vencer."

No cabeçalho (bloco A), o selo vira "Cliente desde mar. de 2024", com a data do começo do seguro mais antigo.

**Ficha da empresa:** o mesmo bloco, com o título "Seguros da empresa (1)", logo depois de Pessoas. Mostra só os
seguros em que o segurado é a empresa (CNPJ).

**Estados:**
- com seguros: como acima (Fábio Figueirão, pessoa 23);
- sem seguro: "Nenhum seguro ainda." (só a frase);
- carregando (`?demo-carteira=carregando`): três linhas em esqueleto dentro do cartão;
- erro (`?demo-carteira=erro`): "Não consegui mostrar os seguros. Tente de novo." + **Tentar de novo**, dentro do
  cartão. O resto da ficha continua.

**Em 390 px:** cabeçalho, faixa (se houver), **Seguros**, Conversas, Cards, Informações, Notas, Arquivos, De onde veio.
O botão PDF fica na mesma linha, à direita, com 44 px.

**Seletores:** `data-carteira="seguros"`, `seguro` (com `data-apolice`), `seguro-pdf`, `seguro-anexar`,
`seguros-vazio`, `seguros-carregando`, `seguros-erro`, `seguros-da-empresa`.

**Reaproveita do bloco A:** `CartaoDaSecao`, `SeloDeEstado`, `ErroComTentarDeNovo`, a página da ficha inteira. Novo:
`SecaoSeguros.vue`, `LinhaDoSeguroNaFicha.vue`.

## Tela 4 — Gaveta do seguro (E4, E5, E7, E8)

**Para que serve:** ver tudo de um seguro e fazer o próximo passo dele.
**Ação principal:** muda com a situação (uma só por vez):

| Situação | Frase do topo | Botão principal |
|---|---|---|
| Em renovação | "Vence em 18 dias. A renovação está em “Opções enviadas”." | **Abrir a renovação** (Tela 11) |
| Ativo, com PDF | "Vale até 13/06/2027." | **Ver PDF** |
| Ativo, sem PDF | "Vale até 13/06/2027. Ainda não tem o PDF." | **Anexar PDF** (Tela 6) |
| Parcela atrasada | "A parcela de 01/11 está em aberto. Avise antes de o seguro cair." | **Avisar Karina** (abre a conversa) |
| Renovado | "Renovou em 08/11. Falta a apólice nova." | **Anexar a apólice nova** (Tela 6) |
| Vencido | "Venceu há 12 dias e não foi renovado. Motivo: achou caro." | **Conversar com Elisa** |
| Cancelado | "Cancelado em 02/10." | **Ver PDF** |

Gaveta à direita (`GavetaLateral` do bloco A, `sm:w-[32rem]`; tela cheia no celular). Abre por cima da lista ou da
ficha; o endereço ganha `?apolice=<id>`, para o link e o print. De cima para baixo:

1. Título "Auto · Seguradora Atlântica" e o selo.
2. A frase do topo e o botão principal da tabela.
3. **Dados do seguro** (lista "nome: valor", como Informações do bloco A):
   Tipo de seguro: Auto · Seguradora: Seguradora Atlântica · Número da apólice: AT-000451 (copiar) · Começa: 29/11/2025 ·
   Termina: 29/11/2026 · Valor do seguro: R$ 2.760,00 por ano · Segurado: Fábio Figueirão (leva à ficha) · CPF: (o CPF
   fictício, com copiar) · O que está segurado: Carro hatch prata, placa FIC-0A23 · Veio de: Agger, em 03/11.
   Valor que chegou com dúvida mostra, ao lado, "Confira" em âmbar; o que falta mostra "Não informado".
4. **Renovação** (só Em renovação e Renovado): "Funil Renovação · Opções enviadas · cuida: Bia Lunardelli" ·
   "Subiu 8% em relação ao ano passado." (quando há proposta) · link **Abrir a renovação** (se não for o principal).
   Quando ainda não há proposta e a conta cota sozinha: botão secundário **Cotar agora** com a linha "Usa uma consulta
   do seu Agger." Ao clicar, a seção mostra "Cotando… pode levar alguns minutos." (sem prometer tempo).
5. **Seu seguro em palavras simples** (só apólice nova, Tela 19).
6. **História** (Tela 15), com **Exportar**.
7. Rodapé: **Corrigir** (Tela 5) · "⋯" com **Anexar outro PDF** · **Marcar como cancelado** (ou **Voltar a ativo**,
   no cancelado).

**Marcar como cancelado:** sem diálogo. O selo vira Cancelado na hora; se havia card de renovação aberto, ele fecha como
"Não renovou", motivo "cancelou o seguro". Aviso vivo embaixo: "Seguro marcado como cancelado." + **Desfazer**. O
**Voltar a ativo** do rodapé desfaz a qualquer hora (reabre o card, se havia).

**Estados:** cheio (como acima, seguro 1); carregando (`?demo-carteira=carregando`): título e lista em esqueleto;
erro: "Não consegui abrir este seguro. Tente de novo." + **Tentar de novo**; seguro que não existe mais (apagado por um
desfazer): "Este seguro não está mais aqui." + **Voltar para a lista**.

**Em 390 px:** tela cheia, botão principal fixo no rodapé, "Fechar" no topo com 44 px.

**Seletores:** `data-carteira="gaveta-seguro"`, `gaveta-acao`, `dados-do-seguro`, `renovacao`, `cotar-agora`,
`historia`, `exportar`, `corrigir`, `mais-do-seguro`, `marcar-cancelado`, `voltar-a-ativo`, `aviso-vivo`.

**Reaproveita do bloco A:** `GavetaLateral`, `ListaDeInformacoes`, `BotaoCopiar`, `SeloDeEstado`, `MenuMais`,
`AvisoVivo`. Novo: `GavetaDoSeguro.vue`, `FraseDoSeguro.vue`.

## Tela 5 — Corrigir o seguro (E4)

**Para que serve:** acertar uma informação do seguro que chegou errada.
**Ação principal:** **Salvar**.

A mesma gaveta troca de conteúdo (título "Corrigir o seguro Auto"):
- Tipo de seguro (`ChoiceSelect`: Auto · Residencial · Vida · Empresarial · Outro);
- Seguradora (`ChoiceSelect` com as seguradoras da conta + "Outra", que abre um campo de texto);
- Número da apólice; Começa; Termina (campo de data); Valor do seguro (R$); O que está segurado.
- Linha de apoio embaixo: "O que você corrigir aqui fica assim, mesmo se este seguro chegar de novo."
- **Salvar** (desligado só enquanto nada mudou) · **Voltar** (sem salvar).

Mudar "Termina" muda o selo na hora, pela regra da data de hoje. Se a data nova põe o seguro dentro dos dias da
renovação, a gaveta diz depois de salvar: "Salvo. O card da renovação nasce amanhã cedo."

**Estados:** erro ao salvar: "Não consegui salvar. Tente de novo." acima do botão, com o que a pessoa digitou intacto.

**Seletores:** `data-carteira="corrigir-gaveta"`, `salvar-correcao`, `erro-correcao`.
**Reaproveita:** `CampoDeTexto`, `ChoiceSelect`, o padrão do formulário de Informações do bloco A.

## Tela 6 — Anexar PDF e "O que mudou" (E4, E6)

**Para que serve:** pôr o PDF num seguro e ver, lado a lado, o que o PDF diz de diferente.
**Ação principal:** **Usar o que está no PDF**.

1. **Anexar:** diálogo "Anexar o PDF do seguro Auto" · área `SoltarArquivo` do bloco A: "Arraste o PDF aqui ou clique
   para escolher" · apoio "Ler este PDF custa cerca de R$ 0,03." · enquanto lê: "Lendo o PDF…".
2. **O que mudou:** o diálogo mostra só o que é diferente, em duas colunas, **Antes** e **No PDF**:

   | | Antes | No PDF |
   |---|---|---|
   | Valor do seguro | R$ 1.990,00 | R$ 2.050,00 |
   | Termina | 14/11/2026 | 14/11/2027 |

   Linha que alguém corrigiu à mão: "Você corrigiu à mão. Fica o seu." e um link **Usar o do PDF** só nela.
   Nada diferente: "O PDF confere com o que já estava aqui." e o botão vira **Guardar o PDF**.
3. Botões: **Usar o que está no PDF** · **Manter como está** (guarda o PDF e não muda os dados).

No Renovado (Tiago Imbirussu, seguro 102), o título é "Anexar a apólice nova" e, ao confirmar, a apólice antiga fica na
história e a nova entra como Ativo, ligada à anterior. Aviso vivo: "Apólice nova guardada." + **Desfazer**.

**Estados:** "Este arquivo não é um PDF de apólice. Escolha outro." · "Não consegui ler este PDF. Tente de novo." ·
lendo.

**Seletores:** `data-carteira="anexar-pdf"`, `soltar-pdf`, `o-que-mudou`, `usar-pdf`, `manter`, `erro-pdf`.
**Reaproveita:** `SoltarArquivo`, `DialogoDaFicha`, `TituloDoDialogo`, `AvisoVivo`.

## Tela 7 — Seguros no painel da conversa (E4)

**Para que serve:** quem atende vê os seguros da pessoa sem sair do chat.
**Ação principal:** nenhuma nova; o painel é de leitura. Cada seguro abre a gaveta.

No painel lateral da conversa (`ContactPanel`), um bloco recolhível novo **Seguros**, logo abaixo dos dados do contato,
aberto por padrão. Cada seguro, uma linha compacta: **Auto** · selo · "vence em 18 dias" · botão **PDF** de 44 px.
Clicar na linha abre a gaveta do seguro (Tela 4) por cima da conversa. No fim: link **Ver na ficha** e o link
**Guardar seguro de outra corretora** (Tela 20).

**Estados:** sem seguro: "Nenhum seguro com você." e o link **Guardar seguro de outra corretora** · carregando: duas
linhas em esqueleto · erro: "Não consegui mostrar os seguros. Tente de novo." + **Tentar de novo**.

**Seletores:** `data-carteira="painel-seguros"`, `painel-seguro`, `painel-pdf`, `painel-ver-ficha`,
`painel-guardar-de-fora`.
**Reaproveita:** `LinhaDoSeguroNaFicha` (modo compacto), `SeloDeEstado`, `GavetaDoSeguro`.

## Tela 8 — Trazer › "Como você quer trazer?" (E4, E6, E7)

**Para que serve:** escolher de onde vêm os clientes e os seguros.
**Ação principal:** **Continuar**.

Só em conta de seguros. Fora do segmento, a Tela 3 do bloco A abre direto na planilha, como hoje.

Título "Como você quer trazer seus clientes e seguros?" · três cartões (`CartoesDeEscolha`):
- **Planilha** · "Excel ou CSV, com os seguros ou só as pessoas.";
- **PDFs das apólices** · "Arraste os PDFs. Eu leio cada um.";
- **Agger** · "Traga direto do seu Agger e mantenha em dia sozinho." (com Agger já ligado: "Sua conta já está ligada
  ao Agger.").

**Continuar** (desligado só enquanto nenhum cartão está escolhido; é o caso "não tem o que enviar"). Embaixo, a lista
"O que você já trouxe" (o histórico do bloco A, que passa a ter planilhas, PDFs e o Agger).

As etapas do topo (Enviar → Conferir → Pronto) aparecem a partir do passo seguinte. O endereço guarda a escolha
(`?como=planilha|pdfs|agger`).

**Estados:** carregando: três cartões em esqueleto; erro: "Não consegui abrir. Tente de novo." + **Tentar de novo**.
**Seletores:** `data-carteira="como-trazer"`, `cartao-planilha`, `cartao-pdfs`, `cartao-agger`, `continuar-como`.
**Reaproveita:** `CartoesDeEscolha`, `HistoricoDeListas`, a página `TrazerListaPage`.

## Tela 9 — Trazer por planilha, com seguros (E4)

**Para que serve:** trazer a carteira de uma planilha.
**Ação principal:** em cada passo, um botão (Continuar · Trazer 168 seguros · Ver os seguros).

É a jornada do bloco A, com o que muda abaixo.

1. **Enviar:** igual ao bloco A. Apoio em conta de seguros: "Excel ou CSV. Precisa ter nome e telefone ou e-mail. Se
   tiver os seguros, melhor."
2. **Pergunta nova** (uma por tela, só quando a planilha tem número de apólice): "Achei números de apólice nesta
   planilha. Ela tem os seguros dos seus clientes?" · **Sim, tem os seguros** · **Não, só as pessoas** · **Voltar**.
   Com "Sim", a pergunta "Essas pessoas já são suas clientes?" do bloco A não aparece: quem tem seguro vira cliente
   desde o começo do seguro mais antigo.
3. **Onde ficam as renovações?** (Tela 10), só na primeira vez que a conta traz seguros.
4. **Conferir.** Frase: "Achei 168 seguros de 120 pessoas." Contadores (como no bloco A): "164 prontos" · "4 precisam de
   você" · "120 pessoas já estavam aqui". Linha de efeito: "Amanhã cedo, 22 seguros que vencem em até 60 dias viram card
   de renovação."
   - **Como vão ficar:** três fichas de exemplo, agora com os seguros (Fábio Figueirão com três seguros; uma pessoa com
     um; Tiago Dornelaz sem telefone).
   - **Precisam de você (4)** · "Quem ficar sem resolver fica de fora.":
     - "Seguro de Hugo Dornelaz: falta quando termina" + campo de data + **Salvar** · **Deixar de fora**;
     - "Seguro de Karina Brandolim: não conheço a seguradora “Atl.”" + `ChoiceSelect` com as seguradoras + **Salvar** ·
       **Deixar de fora**;
     - "O seguro AT-001288 de Paula Brandolim aparece duas vezes. Qual fica?" + as duas linhas com a diferença
       ("Na planilha: R$ 3.410,00" · "Na planilha: R$ 3.140,00") + **Ficar com a linha 88** · **Ficar com a linha 131**;
     - "Seguro de Inês Lourenzatto: falta um número no telefone" + `CampoDeTelefone` + **Salvar** · **Deixar de fora**.
   - **O que vou guardar:** a lista do bloco A, com os destinos novos: Número da apólice · Tipo de seguro · Seguradora ·
     Começa · Termina · Valor do seguro · O que está segurado · CPF ou CNPJ. Tudo com **Mudar**.
   - "Você pode desfazer quando quiser."
   - Botão **Trazer 164 seguros**, que sobe a cada problema resolvido (com os 4: **Trazer 168 seguros**).
5. **Pronto:** "168 seguros chegaram, de 120 pessoas." · **Ver os seguros** (leva à aba Seguros) · **Trazer outra
   lista**. Apoio: "Você pode desfazer quando quiser, em “O que você já trouxe”."
6. **Desfazer** (no histórico; diálogo do bloco A com as linhas de seguro): título "Desfazer “Carteira 2026.xlsx”?" ·
   "Isto tira os 168 seguros que vieram nesta planilha, com os PDFs deles." · "As 120 pessoas continuam aqui, como eram
   antes." · "Os 22 cards de renovação que nasceram dela saem do funil." · "3 propostas já foram enviadas. O que foi
   enviado não volta." · **Desfazer** · **Cancelar**.

**Estados:** os do bloco A (lendo, erros da planilha, carregando). Erro novo: "Não consegui trazer os seguros. Tente de
novo."
**Seletores:** os do bloco A, mais `data-carteira="pergunta-seguros"`, `tem-seguros`, `so-pessoas`,
`efeito-renovacao`, `trazer-seguros`, `ver-os-seguros`.
**Reaproveita:** toda a pasta `components/trazer/` do bloco A.

## Tela 10 — "Onde ficam as renovações?" (E5, passo da primeira vez)

**Para que serve:** dizer em que funil o card de renovação nasce e quantos dias antes.
**Ação principal:** **Continuar** (no Trazer) ou **Salvar** (em Ajustar renovações, Tela 13).

Uma tela, três perguntas, no padrão das perguntas do bloco A:
1. "Onde ficam as renovações?" · `CartoesDeEscolha`:
   - **Criar o funil Renovação** · "Já vem com as etapas: A vencer, Cotando, Opções enviadas, Negociação, Renovado.";
   - **Usar um funil que já tenho** · ao escolher, aparecem dois `ChoiceSelect`: "Funil" (Vendas · Atendimento) e "Em
     qual etapa o card entra?" (as etapas do funil escolhido; a primeira já vem escolhida).
2. "Quantos dias antes do fim o card aparece?" · campo de número com − e + (alvos de 44 px), já com 60. Aceita qualquer
   número a partir de 1. Linha de efeito que muda com o número: "Com 60 dias, 22 seguros entram amanhã cedo." (com 30:
   "Com 30 dias, 17 seguros entram amanhã cedo.").
3. Apoio: "Quem cuida do card segue a regra do funil." (só quando a corretora escolhe um funil que já tem).

**Continuar** desligado só enquanto falta escolher o funil. Sem permissão para mexer em funis: os cartões aparecem e,
ao escolher, a tela diz "Quem cuida dos funis da sua conta precisa fazer esta escolha. Os seguros entram do mesmo jeito;
os cards nascem depois que a escolha for feita." e o botão vira **Seguir sem escolher**.

**Seletores:** `data-carteira="onde-renovacoes"`, `criar-funil`, `usar-funil`, `escolher-funil`, `escolher-etapa`,
`dias-antes`, `efeito-dias`, `continuar-renovacoes`.
**Reaproveita:** `PerguntaDaVez`, `CartoesDeEscolha`, `ChoiceSelect`.

## Tela 11 — Card da renovação (E5, E8)

**Para que serve:** tocar a renovação de um seguro até o fim.
**Ação principal:** **Enviar ao cliente** quando há proposta esperando alguém; senão, **Renovou**.

No protótipo, abre na gaveta do card do bloco A (`GavetaDoCard`), a partir da gaveta do seguro ou do bloco Cards da
ficha (`?renovacao=<id do seguro>`). Na entrega real, o mesmo bloco entra na gaveta do card do CRM (contrato com o
Multifunnel). De cima para baixo:

1. Título "Renovação do seguro Auto" · link "Fábio Figueirão".
2. "Funil Renovação · Opções enviadas · cuida: Bia Lunardelli".
3. **Seguro:** "Auto · Seguradora Atlântica · nº AT-000451" · "Vence em 18 dias (29/11)" · **Ver apólice** (PDF).
4. **Cotação** (E8), num estado de cada vez:

   | Estado (seguro da demo) | O que aparece |
   |---|---|
   | Cotando (107) | "Cotando… pode levar alguns minutos." |
   | Proposta pronta, alguém confere (112) | "Resumo da cotação pronto: Seguradora Atlântica, R$ 3.580,50 por ano." · "Subiu 5% em relação ao ano passado." · **Ver resumo** · **Enviar ao cliente** (principal) |
   | Enviada por alguém (1) | "Proposta enviada por Bia Lunardelli em 06/11." · "Subiu 8% em relação ao ano passado." · **Ver proposta** |
   | Enviada sozinha (113) | "Proposta enviada sozinha em 09/11, às 09:12." · "Baixou 3% em relação ao ano passado." · **Ver proposta** |
   | Faltou dado, com a Lia (110) | "Faltou um dado para cotar: a data de nascimento de Marina. A Lia já perguntou a ela." |
   | Faltou dado, sem agente | "Faltou um dado para cotar: a data de nascimento de Marina. Pergunte a ela e escreva aqui." + campo + **Cotar com este dado** |
   | Algumas seguradoras já responderam (108) | "3 seguradoras já deram preço. 2 ainda não responderam." · a lista: "Seguradora Atlântica · R$ 3.580,50" · "Seguradora Serra Azul · R$ 3.712,00" · "Seguradora Vale Verde · R$ 3.940,10" · "Seguradora Horizonte · ainda não respondeu" · "Seguradora Ponte Nova · ainda não respondeu" · **Ver resumo** |
   | Preço veio, o PDF não (109) | "O preço chegou: Seguradora Atlântica, R$ 3.580,50 por ano. O PDF do resumo não veio." + **Pedir o PDF de novo** |
   | Agger fora do ar | "Não consegui entrar no Agger. Sem ele não dá para cotar." + **Entrar no Agger de novo** (leva à Tela 17) |
   | Demorou demais | "A cotação demorou e parou. Tente de novo." + **Cotar de novo** |
   | Não deu para cotar | "Não consegui cotar. Tente de novo." + **Cotar de novo** |
   | Conta não cota sozinha | "Esta conta não cota sozinha. Faça a cotação e ponha a proposta aqui." + **Anexar proposta** |
   | Não quer mensagens (105) | "Otávio pediu para não receber mensagens. A proposta não sai sozinha. Envie na conversa." + **Conversar** |
   | Sem telefone (104) | "Tiago está sem telefone. A proposta não chega." + **Pôr o telefone** (abre Alterar do bloco A) |

   O rótulo é "Resumo da cotação" quando a seguradora não deu proposta oficial, e "Proposta" quando deu. A mesma
   cotação pode ter os dois: primeiro o resumo com todas as seguradoras; depois, a proposta da seguradora escolhida.
   Com o resumo pronto, cada seguradora da lista tem o botão **Pedir a proposta desta** (44 px); a proposta chega no
   mesmo bloco, abaixo do resumo, e é ela que o **Enviar ao cliente** manda. Seguradora sem PDF de proposta: "Esta
   seguradora não dá proposta em PDF. O que vai ao cliente é o resumo."

   Fatos do conector que este bloco respeita (conferidos com a Cotação em 11/11, no código da `origin/main`): a cotação
   de auto pede nome, CPF/CNPJ, nascimento, sexo, CEP e placa (ou FIPE, ou chassi); renovação sem a seguradora anterior,
   o número da apólice, a vigência e a classe de bônus é cotada como seguro novo. Por isso "faltou dado" é comum em
   seguro que veio de planilha ou PDF, e a apólice guarda esses dados quando a origem os traz. Hoje a cotação só nasce
   numa conversa da Lia; cotar a partir do card é construção da E8 (#2901), nossa, com revisão da Cotação.
5. **Desfecho:** **Renovou** · **Não renovou** (Tela 12). Com proposta esperando, **Renovou** é secundário.
6. Link **Abrir no CRM**.

**Enviar ao cliente** abre a prévia (é a conferência que a corretora escolheu): título "Enviar a proposta a Paula
Brandolim" · a mensagem como vai chegar no WhatsApp: "Oi, Paula! Aqui está a renovação do seu seguro Auto: Seguradora
Atlântica, R$ 3.580,50 por ano. O resumo vai junto, em PDF. Posso seguir?" · o PDF anexado · **Enviar** · **Voltar**.
Fora da janela de 24 horas, a prévia é a do modelo aprovado, com o mesmo texto. Depois: aviso vivo "Proposta enviada a
Paula Brandolim."

**Renovou:** sem diálogo. O card fecha ganho e a seção vira:
- seguro do Agger: "Renovou. A apólice nova chega sozinha na próxima busca do Agger.";
- outra origem: "Renovou. Falta a apólice nova." + **Anexar a apólice nova** (Tela 6).
Aviso vivo "Renovação marcada." + **Desfazer**.

**Estados:** carregando (`?demo-carteira=carregando`): esqueleto da gaveta; erro: "Não consegui abrir esta renovação.
Tente de novo." + **Tentar de novo**.

**Seletores:** `data-carteira="card-renovacao"`, `cotacao`, `enviar-ao-cliente`, `previa-envio`, `enviar`,
`ver-proposta`, `renovou`, `nao-renovou`, `anexar-proposta`, `cotar-com-dado`, `abrir-no-crm`.
**Reaproveita:** `GavetaDoCard`, `GavetaLateral`, `DialogoDaFicha`, `TituloDoDialogo`, `AvisoVivo`. Novo:
`BlocoDoSeguroNoCard.vue`, `BlocoDaCotacao.vue`, `PreviaDaProposta.vue`.

## Tela 12 — "Por que não renovou?" (E5)

**Para que serve:** guardar o motivo da perda em um toque.
**Ação principal:** o toque no motivo (fecha o card).

Diálogo pequeno, título "Por que não renovou?" · quatro botões grandes, um por linha, 44 px:
**Achou caro** · **Foi para outra corretora** · **Vendeu o bem** · **Não respondeu** · e o link **Outro motivo**, que
abre um campo de texto com **Salvar**. Um toque guarda e fecha. Aviso vivo: "Não renovou: achou caro." + **Desfazer**.
O seguro continua com o selo de agora e vira Vencido quando terminar. A pessoa continua cliente.

**Seletores:** `data-carteira="motivo"`, `motivo-caro`, `motivo-outra`, `motivo-vendeu`, `motivo-nao-respondeu`,
`motivo-outro`.
**Reaproveita:** `DialogoDaFicha`, `TituloDoDialogo`, `AvisoVivo`.

## Tela 13 — Ajustar renovações (E5, E6, E8)

**Para que serve:** escolher, uma vez, como as renovações andam na sua corretora.
**Ação principal:** **Salvar** (fixo no rodapé; desligado só enquanto nada mudou).

Rota `relacionamentos/seguros/renovacoes`. Título "Como as renovações andam". Linha de apoio logo abaixo: "Já está
funcionando assim. Mude só o que quiser." Todo cartão chega respondido com a escolha padrão; a corretora não precisa
responder nada para a renovação andar. Um cartão por pergunta, nesta ordem:

1. **Onde ficam** — a Tela 10 inteira (funil, etapa, dias antes).
2. **Mensagens antes de vencer** — `CartoesDeEscolha`: **Mandar sozinho aos 30, 15 e 7 dias** · **Não mandar**. Ao lado,
   a prévia das três mensagens (Fábio como exemplo):
   - 30 dias: "Oi, Fábio! Seu seguro Auto vence em 29/11. Já estamos cuidando da renovação. Qualquer dúvida, é só
     responder aqui."
   - 15 dias: "Oi, Fábio! Faltam 15 dias para o seu seguro Auto vencer, em 29/11. Quer que a gente siga com a
     renovação?"
   - 7 dias: "Oi, Fábio! Seu seguro Auto vence em 7 dias, em 29/11. Responda aqui para renovar a tempo."
   Apoio: "Quem pediu para não receber mensagens não recebe. Você muda os textos em Automações."
3. **Algo mudou?** — "Antes de cotar, perguntar ao cliente se algo mudou?" · **Perguntar** · **Não perguntar**. Prévia:
   "Oi, Fábio! Seu seguro Auto vence em 29/11. Antes de renovar: mudou alguma coisa?" com os botões do WhatsApp
   **Nada mudou** · **Mudou algo**. Abaixo, o que vem depois de "Mudou algo": "O que mudou?" · **Troquei de carro** ·
   **Mudei de endereço** · **Outra coisa**.
4. **Quem faz a cotação?** — **Robô de renovação** · "Cota no Agger e põe a proposta no card." · **Lia** · "A Lia cota
   e conversa com o cliente." · **Ninguém** · "A equipe cota e recebe o aviso quando o card nasce."
5. **Como a proposta chega ao cliente?** — **Uma pessoa confere e aperta Enviar** (já vem escolhida) · **Sai sozinha
   pelo WhatsApp**. Com "Sai sozinha", a linha: "Sai sem ninguém apertar nada. Você vê tudo o que saiu no card."
6. **Quem responde o cliente depois?** — **A Lia** · **A equipe**. Sem agente na conta, só "A equipe" e a linha "Quer
   que um agente responda sozinho? Veja em Agentes." (link).
7. **Seu seguro em palavras simples** — "Quando a apólice nova sair, mandar ao cliente o que o seguro cobre?" · **Eu
   confiro antes** · **Sai sozinho** · **Não mandar**.
8. **Consumo** — "Você fez 14 cotações nos últimos 30 dias." (só informa; na entrega real o número vem da medição que
   a Cotação já tem, `autonomia/insurance/measurement`, campo `quotes`).

Quando a conta não cota sozinha, os cartões 4 a 6 viram um só:
- sem Agger: "Para cotar sozinho, ligue sua conta ao Agger." + **Ligar ao Agger** (leva à Tela 17);
- com Agger e cotação não ligada: "A cotação automática ainda não está ligada na sua conta." + **Quero ligar**, que
  abre um diálogo: "A cotação automática é ligada pela equipe da [nome da instalação]. Fale com quem cuida da sua conta
  e ela liga." · **Entendi**.

Salvar: aviso vivo "Salvo." Erro: "Não consegui salvar. Tente de novo." acima do botão, com as escolhas intactas.
Sem permissão para mexer em funis: o cartão 1 mostra a escolha atual e a frase da Tela 10; os outros funcionam.

**Estados:** carregando: cartões em esqueleto; erro ao abrir: "Não consegui abrir os ajustes. Tente de novo." +
**Tentar de novo**.
**Seletores:** `data-carteira="ajustes"`, `ajuste-onde`, `ajuste-mensagens`, `ajuste-algo-mudou`, `ajuste-quem-cota`,
`ajuste-como-envia`, `ajuste-quem-responde`, `ajuste-palavras-simples`, `ajuste-consumo`, `quero-ligar`,
`ligar-agger`, `salvar-ajustes`.
**Reaproveita:** `CartaoDaSecao`, `CartoesDeEscolha`, `ChoiceSelect`, `TituloDoDialogo`, `AvisoVivo`.

## Tela 14 — Resultados das renovações (E5)

**Para que serve:** ver quantos seguros você renovou e por que perdeu os outros.
**Ação principal:** **Ver os 5 que não renovaram**.

Rota `relacionamentos/seguros/resultados`. De cima para baixo:
1. **Herói escuro:** "Nos últimos 30 dias, você renovou 14 de 19 seguros." · **Ver os 5 que não renovaram** (abre a aba
   Seguros com o grupo temporário "Não renovaram (últimos 30 dias)", 5 seguros). Canto: link **Voltar aos seguros**.
2. **Período** (`ChoiceSelect`): Últimos 30 dias · Últimos 90 dias · Últimos 12 meses. Tudo abaixo e o herói mudam
   juntos (tabela "Resultados das renovações").
3. **Por que não renovou:** quatro linhas com barra e número: "Achou caro · 2" · "Foi para outra corretora · 1" ·
   "Vendeu o bem · 1" · "Não respondeu · 1".
4. **Recorte** em pílulas: Tipo de seguro · Seguradora · Quem cuida. Cada linha: nome · barra · "7 de 9 renovaram".
5. Rodapé: "Vencem nos próximos 30 dias: 17." + link **Ver quais** (grupo "Vence em até 30 dias").

**Estados:** sem nenhum vencimento no período: "Nenhum seguro venceu neste período." (só a frase, com o seletor de
período visível) · carregando: herói e barras em esqueleto · erro: "Não consegui mostrar os resultados. Tente de
novo." + **Tentar de novo**.
**Em 390 px:** herói, período, motivos, pílulas que rolam, linhas com a barra embaixo do nome.
**Seletores:** `data-carteira="resultados"`, `resultados-heroi`, `ver-nao-renovaram`, `periodo`, `motivos`, `recorte`,
`resultados-vazio`.
**Reaproveita:** `HeroiEscuro`, `PilulasDeGrupo`, `ChoiceSelect`, `CartaoDaSecao`. Novo: `BarraDeResultado.vue`.

## Tela 15 — História do seguro (E5, E8)

**Para que serve:** ver tudo o que aconteceu com o seguro, em ordem.
**Ação principal:** nenhuma na seção; **Exportar** é secundário.

Seção da gaveta do seguro (Tela 4). Linha do tempo, do mais novo para o mais velho. Cada item: data e hora · o que
aconteceu · quem fez. Seguro 1 (Fábio):

- "09/11 · 14:20 · Fábio respondeu: “Vou ver com a minha esposa e te falo.”"
- "06/11 · 10:05 · Proposta enviada · Bia Lunardelli" (com **Ver proposta**)
- "05/11 · 09:40 · Proposta pronta: Seguradora Atlântica, R$ 2.980,80. Subiu 8%. · Robô de renovação"
- "05/11 · 09:02 · Fábio respondeu “Algo mudou?”: Nada mudou."
- "04/11 · 07:00 · Card de renovação nasceu no funil Renovação, em “A vencer”."
- "03/11 · 18:31 · Chegou do Agger."

Endosso e "o que mudou" aparecem na história com as duas colunas da Tela 6, recolhidas (seguro 2): "05/11 · Endosso ·
Valor do seguro: R$ 610,00 → R$ 640,00".

**Exportar** baixa um arquivo `historia-AT-000451.csv` com data, hora, o que aconteceu e quem fez. Aviso vivo: "Arquivo
baixado."

**Estados:** sem nada além da chegada: só o item "Chegou do Agger." · erro: "Não consegui mostrar a história. Tente de
novo." + **Tentar de novo**.
**Seletores:** `data-carteira="historia"`, `item-da-historia`, `exportar`.
**Reaproveita:** `AvisoVivo`. Novo: `HistoriaDoSeguro.vue`.

## Tela 16 — Trazer por PDFs (E6)

**Para que serve:** trazer seguros a partir dos PDFs das apólices.
**Ação principal:** em cada passo, um botão (Ler os PDFs · Trazer 37 seguros · Ver os seguros).

1. **Enviar:** "Arraste os PDFs das apólices aqui ou clique para escolher" (vários de uma vez) · apoio "De qualquer
   seguradora. Pode ser foto de celular." Depois de escolher: "40 PDFs escolhidos" · lista dos nomes (recolhida, com
   "Ver os 40") · "Ler os 40 PDFs custa cerca de R$ 1,20." · **Ler os PDFs**.
2. **Lendo:** "Lendo 12 de 40…" com barra igual ao número · "Pode fechar esta tela; eu aviso quando terminar."
3. **Onde ficam as renovações?** (Tela 10), se for a primeira vez.
4. **Conferir:** "Li 40 PDFs. Achei 39 seguros de 31 pessoas." Contadores: "37 prontos" · "2 precisam de você" ·
   "1 não é apólice". Linha de efeito: "Amanhã cedo, 6 seguros que vencem em até 60 dias viram card de renovação."
   - **Precisam de você (2)** · "Quem ficar sem resolver fica de fora.":
     - "Seguro de Gabriela Guedelha: não achei quando termina neste PDF" + campo de data + **Salvar** · **Deixar de
       fora**;
     - "Seguro de Lucas Jacobelli: não achei o telefone dele neste PDF" + `CampoDeTelefone` + **Salvar** · **Seguir sem
       telefone**.
   - **Não é apólice (1):** "“boleto-marco.pdf” não é uma apólice. Fica de fora."
   - **Como vão ficar:** três fichas de exemplo.
   - "Você pode desfazer quando quiser."
   - **Trazer 37 seguros** (sobe a cada problema resolvido; com os 2: **Trazer 39 seguros**).
5. **Pronto:** "39 seguros chegaram, de 31 pessoas." · **Ver os seguros** · **Trazer mais PDFs**.

**Estados:** "Nenhum destes arquivos é PDF. Escolha os PDFs das apólices." · "Não consegui ler os PDFs. Tente de novo." ·
foto escura ou torta que não deu para ler, na lista de problemas: "“apolice-ana.jpg” está escura demais. Tire outra
foto com mais luz." + **Trocar o arquivo** · **Deixar de fora**.
**Seletores:** `data-carteira="pdfs-soltar"`, `pdfs-custo`, `ler-pdfs`, `pdfs-lendo`, `pdfs-conferir`,
`pdfs-precisam`, `pdfs-nao-e-apolice`, `trazer-pdfs`, `pdfs-erro`.
**Reaproveita:** `SoltarArquivo`, `EtapasDoTopo`, `PrecisamDeVoce`, `ProblemaDaLinha`, `FichaDeExemplo`, `TelaPronto`.

## Tela 17 — Trazer pelo Agger (E7)

**Para que serve:** trazer a carteira do Agger e deixar que ela se mantenha em dia sozinha.
**Ação principal:** em cada passo, um botão (Entrar e trazer · Trazer 156 seguros · Ver os seguros).

1. **Ligar:**
   - já ligado (a mesma ligação que a Lia usa): "Sua conta já está ligada ao Agger." · **Trazer meus seguros do
     Agger**;
   - não ligado: título "Entre com o seu login do Agger" · "Usuário do Agger" · "Senha do Agger" (com mostrar) ·
     **Entrar e trazer** (desligado só com campo vazio). Apoio: "É o mesmo login que você usa no Agger."
2. **Onde ficam as renovações?** (Tela 10), se for a primeira vez.
3. **Buscando:** "Buscando seus seguros no Agger." · apoio "Isso pode demorar. Pode fechar esta tela; eu aviso quando
   chegar." Uma linha por seguradora:
   - "Seguradora Atlântica · 64 seguros" ✓;
   - "Horizonte Seguros · 52 seguros" ✓;
   - "Serra Azul Seguros · buscando…";
   - "Seguradora Aurora · falta a senha desta seguradora no seu Agger" + **Como resolver**.
   **Como resolver** abre: "Entre no seu Agger, guarde a senha da Seguradora Aurora e volte aqui. Eu busco de novo
   sozinho amanhã cedo." · **Buscar de novo agora** · **Entendi**.
4. **Conferir:** "Achei 156 seguros de 112 pessoas." Contadores: "153 prontos" · "3 sem telefone" · "112 pessoas já
   estavam aqui". "Sem telefone" não trava: "Essas pessoas entram sem telefone. A mensagem da renovação não chega até
   você pôr o telefone." Linha de efeito: "Amanhã cedo, 20 seguros que vencem em até 60 dias viram card de renovação."
   Botão **Trazer 156 seguros**.
5. **Pronto:** "156 seguros chegaram, de 112 pessoas." · apoio "Daqui para a frente, eu busco no Agger todo dia." ·
   **Ver os seguros**.
6. **No histórico** "O que você já trouxe": "Agger · busca todo dia · última hoje, 06:10 · 2 seguros novos" ·
   **Desfazer** (tira os seguros que vieram do Agger, com o mesmo diálogo da Tela 9) · "⋯" **Parar de buscar todo
   dia** (o que já veio fica).

**Estados:** "Usuário ou senha não conferem. Confira e tente de novo." (campos intactos) · "O Agger não respondeu
agora. Eu tento de novo sozinho; o que já chegou fica guardado." + **Tentar agora** · "Sua conta no Agger não tem a
parte de apólices. Peça ao Agger para ligar e volte aqui." + **Entendi**.
**Seletores:** `data-carteira="agger-ligado"`, `agger-usuario`, `agger-senha`, `agger-entrar`, `agger-buscando`,
`agger-seguradora`, `agger-como-resolver`, `agger-conferir`, `trazer-agger`, `agger-erro`, `agger-historico`.
**Reaproveita:** `EtapasDoTopo`, `CampoDeTexto`, `TelaPronto`, `HistoricoDeListas`, `DialogoDesfazer`,
`TituloDoDialogo`.

## Tela 18 — Parcela atrasada (E7, segundo PR)

**Para que serve:** avisar o cliente antes de o seguro cair por parcela em aberto.
**Ação principal:** **Avisar <nome>** (na gaveta).

Não é tela própria: é o grupo "Parcela atrasada" da Tela 1 (3 seguros), o selo âmbar **Parcela atrasada** na linha e a
situação da gaveta (Tela 4): "A parcela de 01/11 está em aberto. Avise antes de o seguro cair." · **Avisar Karina**
abre a conversa com o texto já escrito na caixa de mensagem: "Oi, Karina! A parcela de 01/11 do seu seguro Auto está em
aberto. Quer que eu te mande o boleto de novo?" A pessoa edita e envia; nada sai sozinho. Parcela paga some na busca
seguinte do Agger. Grupo só existe com Agger ligado.

**Seletores:** grupo `parcela_atrasada`, `data-carteira="selo-parcela"`, `avisar-parcela`.

## Tela 19 — Seu seguro em palavras simples (E6, terceiro PR)

**Para que serve:** mandar ao cliente, depois que a apólice sai, o que o seguro cobre e o que fazer se precisar.
**Ação principal:** **Enviar ao cliente** (quando a corretora escolheu "Eu confiro antes").

Seção da gaveta do seguro, só em apólice nova (seguro 109, Hugo Dornelaz). Título "Seu seguro em palavras simples".
Texto de exemplo (fictício):

> Oi, Hugo! Seu seguro Auto com a Seguradora Atlântica começou em 08/11.
> O que ele cobre: batida, roubo e furto, vidros e guincho.
> Se acontecer alguma coisa: me chame aqui no WhatsApp. Eu te digo o que fazer.
> Vale o que está escrito na sua apólice.

Botões: **Enviar ao cliente** · **Alterar o texto** (abre o texto em caixa editável, com **Salvar**). Com "Sai sozinho":
"Enviado sozinho em 08/11, às 10:30." e **Ver o que foi enviado**. Com "Não mandar": a seção não aparece. A última
frase ("Vale o que está escrito na sua apólice.") vem sempre e não sai com Alterar.

**Estados:** "Lendo a apólice para escrever…" · "Não consegui escrever o texto. Tente de novo." + **Tentar de novo**.
**Seletores:** `data-carteira="palavras-simples"`, `enviar-palavras`, `alterar-palavras`.

## Tela 20 — Guardar seguro de outra corretora (E6, segundo PR)

**Para que serve:** guardar o vencimento do seguro que a pessoa tem em outra corretora, para chamar na hora certa.
**Ação principal:** **Guardar lembrete**.

Abre do painel da conversa (Tela 7) ou do bloco Seguros da ficha, numa gaveta. Título "Seguro de outra corretora". Exemplo:
Nádia Carvalhedo.

1. "Qual arquivo é o seguro?" · miniaturas dos arquivos que vieram na conversa (`SecaoArquivos` do bloco A) e a área
   "Ou arraste o arquivo aqui" · apoio "Ler este arquivo custa cerca de R$ 0,03."
2. "Lendo…".
3. O que li: Tipo de seguro: Auto · Seguradora: Seguradora Aurora · Termina: 20/02/2027. Cada um editável; o que não
   achei aparece vazio com "Não achei. Escreva aqui."
4. "A Nádia quer que você lembre antes de vencer?" · **Sim, ela quer** · **Ainda não perguntei**. Com "Ainda não
   perguntei", aparece **Perguntar na conversa**, que põe na caixa de mensagem: "Quer que eu te lembre antes do seu
   seguro vencer? Assim você compara com calma." e fecha a gaveta.
5. **Guardar lembrete** (aparece com "Sim, ela quer"). Depois: aviso vivo "Lembrete guardado. Vamos chamar a Nádia em
   22/12." A pessoa não vira cliente; na ficha aparece com o selo **Em outra corretora** (Tela 3) e o card nasce nos
   mesmos dias antes da renovação.

**Estados:** "Este arquivo não parece um seguro. Escolha outro." · "Não consegui ler. Tente de novo." · foto escura:
"A foto está escura demais. Peça outra com mais luz."
**Seletores:** `data-carteira="de-fora"`, `de-fora-arquivo`, `de-fora-lido`, `de-fora-quer`, `de-fora-perguntar`,
`guardar-lembrete`.
**Reaproveita:** `GavetaLateral`, `SecaoArquivos`, `SoltarArquivo`, `CampoDeTexto`, `AvisoVivo`.

---

## Jornadas de prints

Arquivo `docs/2897-prototipo/jornadas.json`, no mesmo formato de `docs/2894-prototipo/jornadas.json` (pasta
`docs/2897-prototipo/prints`, conta 1, larguras 1440 e 390, tema claro, etapa `login` no começo de cada jornada).
**Regra: fotografar cada tela antes de responder, marcar ou abrir qualquer coisa.** Quando uma etapa precisa de
clique, o print é do resultado do clique, nunca de uma tela com escolha já feita pelo roteiro. Abaixo, `{c}` é a conta
e o seletor `x` quer dizer `[data-carteira="x"]`.

**4-seguros (E4)**

| Etapa | URL ou passos | Espera |
|---|---|---|
| lista-seguros | `/app/accounts/{c}/relationships?aba=seguros&demo=cheio` | `linha` |
| grupo-7-dias | clicar `heroi-acao` | `linha` |
| grupo-30-dias | clicar a pílula `vence_30_dias` | `linha` |
| marcados | clicar `marcar` nas linhas `[data-apolice="110"]`, `[data-apolice="107"]`, `[data-apolice="104"]` | `barra` |
| mandar-mensagem | clicar `mandar-mensagem` | `[data-relacionamentos="dialogo-mensagem"]` |
| busca-sem-resultado | URL da lista-seguros; preencher `busca` com "zzzz" | `vazio` |
| pessoas-com-selo | `/app/accounts/{c}/relationships?demo=cheio` | `selo-da-pessoa` |
| so-um-seguro | clicar a pílula `so_um_seguro` | `[data-relacionamentos="linha"]` |
| sem-seguros | `/app/accounts/{c}/relationships?aba=seguros&demo=sem-seguros` | `heroi` |
| fora-do-segmento | `/app/accounts/{c}/relationships?demo=fora-do-segmento` | `[data-relacionamentos="linha"]` (e nenhuma `aba-seguros`) |
| carregando | `…?aba=seguros&demo=carregando` | `carregando` |
| erro | `…?aba=seguros&demo=desligado` | `erro` |

**5-ficha-e-seguro (E4)**

| Etapa | URL ou passos | Espera |
|---|---|---|
| ficha-com-seguros | `/app/accounts/{c}/relacionamentos/pessoas/23?demo=cheio` | `seguros` |
| gaveta-em-renovacao | `…/pessoas/23?demo=cheio&apolice=1` | `gaveta-seguro` |
| historia | rolar até `historia` | `item-da-historia` |
| corrigir | clicar `corrigir` | `corrigir-gaveta` |
| gaveta-ativo-com-endosso | `…/pessoas/23?demo=cheio&apolice=2` | `gaveta-seguro` |
| renovado-falta-apolice | `…/pessoas/38?demo=cheio&apolice=102` | `gaveta-seguro` |
| anexar-apolice-nova | clicar `gaveta-acao` | `soltar-pdf` |
| o-que-mudou | soltar o PDF de exemplo (`usar-exemplo`) | `o-que-mudou` |
| vencido | `…/pessoas/41?demo=cheio&apolice=103` | `gaveta-seguro` |
| cancelado | `…/pessoas/72?demo=cheio&apolice=101` | `gaveta-seguro` |
| marcar-cancelado | `…/pessoas/23?demo=cheio&apolice=2`; abrir `mais-do-seguro`; clicar `marcar-cancelado` | `aviso-vivo` |
| empresa | `/app/accounts/{c}/relacionamentos/empresas/23?demo=cheio` | `seguros-da-empresa` |
| em-outra-corretora | `…/pessoas/20?demo=cheio` | `seguros` |
| sem-seguro | `…/pessoas/27?demo=cheio` | `seguros-vazio` |
| seguros-carregando | `…/pessoas/23?demo=cheio&demo-carteira=carregando` | `seguros-carregando` |
| seguros-erro | `…/pessoas/23?demo=cheio&demo-carteira=erro` | `seguros-erro` |
| gaveta-erro | `…/pessoas/23?demo=cheio&demo-carteira=erro&apolice=1` | `[data-relacionamentos="erro"]` dentro de `gaveta-seguro` |
| painel-da-conversa | `/app/accounts/{c}/conversations/<id da conversa de demo>?demo=cheio` | `painel-seguros` |
| painel-sem-seguro | mesma conversa com `&demo-carteira=vazio` | `painel-guardar-de-fora` |

**6-renovacao (E5)**

| Etapa | URL ou passos | Espera |
|---|---|---|
| card-enviada | `…/pessoas/23?demo=cheio&renovacao=1` | `card-renovacao` |
| nao-renovou | clicar `nao-renovou` | `motivo` |
| motivo-escolhido | clicar `motivo-caro` | `aviso-vivo` |
| renovou-falta-apolice | `…/pessoas/38?demo=cheio&renovacao=102` | `card-renovacao` |
| ajustes | `/app/accounts/{c}/relacionamentos/seguros/renovacoes?demo=cheio` | `ajustes` |
| ajustes-mais-abaixo | rolar até `ajuste-quem-cota` | `ajuste-como-envia` |
| ajustes-sem-agger | `…/seguros/renovacoes?demo=sem-seguros` | `ligar-agger` |
| resultados | `/app/accounts/{c}/relacionamentos/seguros/resultados?demo=cheio` | `resultados-heroi` |
| resultados-12-meses | escolher "Últimos 12 meses" em `periodo` | `motivos` |
| nao-renovaram | clicar `ver-nao-renovaram` | `linha` |
| resultados-vazio | `…/seguros/resultados?demo=sem-seguros` | `resultados-vazio` |
| ajustes-carregando · resultados-erro | `…&demo=carregando` · `…&demo=desligado` | `carregando` · `erro` |

**7-trazer-planilha (E4)**

| Etapa | URL ou passos | Espera |
|---|---|---|
| como-trazer | `/app/accounts/{c}/relacionamentos/trazer?demo=sem-seguros` | `como-trazer` |
| escolheu-planilha | clicar `cartao-planilha` | `continuar-como` |
| enviar | clicar `continuar-como` | `[data-relacionamentos="soltar-arquivo"]` |
| pergunta-seguros | clicar `[data-relacionamentos="usar-exemplo"]` | `pergunta-seguros` |
| onde-renovacoes | clicar `tem-seguros` | `onde-renovacoes` |
| usar-funil | clicar `usar-funil` | `escolher-etapa` |
| conferir | clicar `criar-funil`; clicar `continuar-renovacoes` | `[data-relacionamentos="conferir"]` |
| precisam-de-voce | rolar até `[data-relacionamentos="precisam-de-voce"]` | `[data-relacionamentos="precisam-titulo"]` |
| o-que-vou-guardar | abrir `[data-relacionamentos="o-que-vou-guardar"]` | `[data-relacionamentos="trocar-coluna"]` |
| andamento | resolver os 4; clicar `trazer-seguros` | `[data-relacionamentos="andamento"]` |
| pronto | esperar o fim | `ver-os-seguros` |
| desfazer | clicar `[data-relacionamentos="desfazer"]` no histórico | `[data-relacionamentos="dialogo-desfazer"]` |
| fora-do-segmento | `…/trazer?demo=fora-do-segmento` | `[data-relacionamentos="soltar-arquivo"]` (sem `como-trazer`) |
| carregando | `…/trazer?demo=carregando` | `carregando` |

**8-trazer-pdfs (E6)**

| Etapa | URL ou passos | Espera |
|---|---|---|
| enviar-pdfs | `…/trazer?como=pdfs&demo=sem-seguros` | `pdfs-soltar` |
| custo | soltar os 40 PDFs de exemplo | `pdfs-custo` |
| lendo | clicar `ler-pdfs` | `pdfs-lendo` |
| conferir-pdfs | esperar; passar por `onde-renovacoes` com `criar-funil` | `pdfs-conferir` |
| precisam-e-nao-e-apolice | rolar até `pdfs-precisam` | `pdfs-nao-e-apolice` |
| pronto | resolver os 2; clicar `trazer-pdfs` | `ver-os-seguros` |
| erro | soltar arquivo que não é PDF | `pdfs-erro` |

**9-trazer-agger (E7)**

| Etapa | URL ou passos | Espera |
|---|---|---|
| agger-login | `…/trazer?como=agger&demo=sem-seguros` | `agger-usuario` |
| agger-ja-ligado | `…/trazer?como=agger&demo=cheio` | `agger-ligado` |
| buscando | na URL do login, preencher usuário e senha de exemplo; clicar `agger-entrar`; passar por `onde-renovacoes` | `agger-buscando` |
| como-resolver | clicar `agger-como-resolver` | `[data-relacionamentos="titulo-do-dialogo"]` |
| conferir-agger | esperar | `agger-conferir` |
| pronto | clicar `trazer-agger` | `ver-os-seguros` |
| historico-agger | voltar a `…/trazer?demo=cheio` | `agger-historico` |
| senha-errada | login com a senha de exemplo "errada" | `agger-erro` |
| parcela-atrasada | `/app/accounts/{c}/relationships?aba=seguros&demo=cheio`; clicar a pílula `parcela_atrasada` | `selo-parcela` |
| gaveta-parcela | `…/pessoas/13?demo=cheio&apolice=108` | `avisar-parcela` |

**10-cotacao-e-depois (E8, E6)**

| Etapa | URL ou passos | Espera |
|---|---|---|
| cotando | `…/pessoas/4?demo=cheio&renovacao=107` | `cotacao` |
| proposta-pronta | `…/pessoas/24?demo=cheio&renovacao=112` | `enviar-ao-cliente` |
| previa-do-envio | clicar `enviar-ao-cliente` | `previa-envio` |
| enviada-sozinha | `…/pessoas/105?demo=cheio&renovacao=113` | `ver-proposta` |
| faltou-dado-lia | `…/pessoas/117?demo=cheio&renovacao=110` | `cotacao` |
| nao-quer-mensagens | `…/pessoas/203?demo=cheio&renovacao=105` | `cotacao` |
| sem-telefone | `…/pessoas/59?demo=cheio&renovacao=104` | `cotacao` |
| quero-ligar | `…/seguros/renovacoes?demo=cheio&cotacao=desligada`; clicar `quero-ligar` | `[data-relacionamentos="titulo-do-dialogo"]` |
| palavras-simples | `…/pessoas/48?demo=cheio&apolice=109` | `palavras-simples` |
| de-fora | conversa de demo `?demo=cheio&demo-carteira=vazio`; clicar `painel-guardar-de-fora` | `de-fora-arquivo` |
| de-fora-lido | clicar a primeira miniatura | `de-fora-quer` |
| card-erro | `…/pessoas/23?demo=cheio&demo-carteira=erro&renovacao=1` | `[data-relacionamentos="erro"]` |

Cada etapa sai em 1440 e 390. Depois de cada rodada, olhar os prints um a um, como no bloco A (registro em
`docs/audit/2026-11-11-1240-execucao.md`).

## O que fica fora do protótipo, e por quê

- **Rotina diária que cria o card, busca diária do Agger e leitura real de PDF.** São trabalho de fundo; o protótipo
  mostra o resultado com dado fictício. O aceite deles é teste de backend (E5, E6, E7).
- **A gaveta do card dentro do CRM.** O protótipo mostra o bloco do seguro e da cotação na gaveta do card do bloco A.
  Na entrega, o mesmo componente entra no CRM, com o Multifunnel (contrato de 11/11).
- **Aviso no sino.** É peça da casa. Os textos ficam definidos aqui e entram na E5: "O seguro Residencial de Tiago
  Dornelaz vence em 25 dias. Esta conta não cota sozinha: faça a cotação." e "O seguro Residencial de Tiago Dornelaz
  vence em 25 dias. Ele está sem telefone."
- **Guia e agente enxergando a carteira.** Não há tela nova: o Guia responde no lugar de sempre, e o agente, na
  conversa. O aceite é a lista de 20 perguntas da E5, contra o banco da demo.
- **A receita "Renovação de seguro" dentro de Automações.** O protótipo mostra a escolha em Ajustar renovações (Tela 13).
  A receita é da Automação, que revisa o PR.
- **A chave "Cotação de renovação" no Super Admin.** É tela de administração da casa, sem jornada de cliente. O
  protótipo simula a chave desligada com `&cotacao=desligada`.
- **Mensagens no WhatsApp do cliente.** O protótipo mostra a prévia de cada uma; o envio real depende de modelo
  aprovado (Modelos WhatsApp, E8).
- **Saúde e benefícios.** Fora do épico agora (decisão 3).

## Decisões que tomei

1. **Seletores `data-carteira`.** Separa o bloco B do A no roteiro; peça do A reaproveitada mantém o seletor dela.
2. **Grupos de vencimento acumulam** ("em até 30 dias" inclui os de 7). É como o corretor pergunta: "quem vence este
   mês?" inclui quem vence amanhã.
3. **"Próximos 30 dias", não "este mês".** O número não muda com o dia do mês e bate com o grupo "Vence em até 30
   dias".
4. **Em renovação = termina em até N dias e tem card aberto.** Com o padrão de 60 dias, os grupos e o selo contam os
   mesmos 22.
5. **Renovado fica visível só enquanto falta a apólice nova.** Depois, a antiga entra na história da nova; a lista não
   dobra.
6. **Vencido fica para sempre na carteira.** A pessoa continua cliente (decisão 9 do Rodrigo), e o seguro perdido é
   lista de quem chamar.
7. **Pessoas mostra selo de seguro só quando não é Ativo nem Cancelado.** "Cliente" já diz que tem seguro; repetir
   "Ativo" em 98 linhas é ruído.
8. **O herói da aba Pessoas não muda.** Cada aba fala do próprio grupo, e o botão nunca troca de aba sem a pessoa ver.
9. **Seguros é o primeiro bloco da ficha.** Responde "o que tem comigo" antes da conversa.
10. **"Valor do seguro", "começa", "termina", "tipo de seguro".** Todo corretor entende, e quem atende também; "prêmio",
    "vigência" e "ramo" ficam fora da tela.
11. **Botão principal da gaveta muda com a situação.** Continua um só por vez, e é o próximo passo daquele seguro.
12. **Marcar como cancelado não pede confirmação.** O aviso tem Desfazer e o rodapé tem "Voltar a ativo" sem prazo.
13. **Cancelar fecha o card aberto como "Não renovou", motivo "cancelou o seguro".** Não fica card órfão no funil, e o
    motivo entra nos resultados.
14. **Desfazer uma lista de seguros tira os cards que nasceram dela do funil.** Card de seguro que não existe mais
    engana o funil; a proposta já enviada é dita na prévia.
15. **"Tem seguros?" dispensa a pergunta "são clientes?".** O cliente vem da apólice (decisão 6 do Rodrigo).
16. **Dias antes: campo de número sem teto, padrão 60, com a linha de efeito.** Mostra antes de fazer e não põe freio.
17. **Sem permissão de funil, os seguros entram e os cards esperam a escolha.** Não trava quem trouxe a carteira.
18. **Cotação automática depende da conta ter o Agger ligado e a chave ligada, não da origem do seguro.** É como leio
    a decisão 15 do Rodrigo; seguro que veio de planilha numa conta com Agger também cota.
19. **"Quem envia" e "uma pessoa confere ou sai sozinha" viram uma pergunta só.** São a mesma escolha, e as seis
    combinações do aceite da E8 continuam (3 de quem cota × 2 de como envia).
20. **Proposta para quem não quer mensagens não sai sozinha; a pessoa da equipe envia na conversa.** Segue a regra da
    recusa de hoje: tira de envio automático, não de conversa.
21. **Consumo de cotação aparece em número de cotações, não em reais.** O preço por consulta é do contrato da corretora
    com o Agger, que não temos.
22. **Custo de leitura de PDF em reais, com número de demo (R$ 0,03 por PDF).** O número real sai da bateria com
    orçamento aprovado; a frase e o lugar ficam.
23. **Chave desligada: botão "Quero ligar" abre e diz quem liga.** Sem botão desligado e sem inventar um pedido que o
    sistema não faz.
24. **Resultados ganham rota própria, com link na aba Seguros.** O painel não disputa espaço com a lista.
25. **Seguro de fora pede a resposta da pessoa com dois botões, e "Ainda não perguntei" oferece a pergunta pronta.**
    Registra o consentimento (aceite da E6) sem caixa obrigatória.
26. **Painel da conversa só lê.** Corrigir e cancelar ficam na gaveta, que abre dali mesmo.
27. **No protótipo, o painel da conversa usa a carteira fictícia em qualquer conversa da conta de demo.** A conversa
    real não tem os ids da base fictícia, e o print precisa da tela real.
28. **Estados `sem-seguros` e `fora-do-segmento` e o parâmetro `demo-carteira`.** Sem eles, não há print de primeira
    vez, de conta de outro segmento, nem do carregando e erro de cada peça.
29. **Pasta `docs/2897-prototipo/` e branch nova a partir da do bloco A.** O bloco B reaproveita as peças do A e julga
    separado.
30. **Textos de seguro num catálogo próprio, só para o segmento.** O texto geral fica sem palavra de seguro, como o plano
    manda.
