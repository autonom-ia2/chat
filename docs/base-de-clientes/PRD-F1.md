# Base de clientes — PRD da F1

Épico: #1240. Continua o [PRD](PRD.md) (problema, o que já existe e as fases) com o que a F0, a pesquisa e os dados de produção mostraram. Escrito em 11/10/2026.

**Base deste documento**
- **F0 (bateria):** 62 planilhas com gabarito, 0 erro silencioso, 95% perfeitas ([BATERIA-F0.md](BATERIA-F0.md), PRs #1249 e #1257, em produção).
- **Pesquisa de código, mercado e UX:** [PESQUISA-RELACIONAMENTOS.md](PESQUISA-RELACIONAMENTOS.md) e [PESQUISA-FONTES.md](PESQUISA-FONTES.md).
- **Dados de produção das duas instalações:** [DADOS-DE-PRODUCAO.md](DADOS-DE-PRODUCAO.md).
- **Mockup navegável** com as peças reais do produto, 7 caminhos e 35 etapas, cada uma com "Hoje" e "Proposto": https://claude.ai/artifact/JrgNghcp2mTjKEsswKa5GL (privado; o Rodrigo compartilha).

---

## 1. O que já está decidido

| # | Decisão | Origem |
|---|---|---|
| 1 | Telas nossas dentro de Relacionamentos/Contatos; a "Dados" do Chatwoot fica escondida | PRD D1 |
| 2 | Evoluir a importação da #1006, sem motor novo | PRD D3 |
| 3 | Quem interpreta a planilha é o modelo (Jev), nunca lista de palavras ou regex | PRD D4 |
| 4 | Flag por conta `customer_base`, ligada só na conta 16 até o piloto passar | #1249, Rodrigo 10/10 |
| 5 | O país da coluna de telefone é decidido pelo Jev; a máscara mostra o DDD | #1257 |
| 6 | **Termos.** A lista é **Contatos** (todo mundo). **Cliente** é o estado de quem comprou (`contact_type = customer`, selo, "Cliente desde"). Quem não comprou aparece como "Ainda não compraram". "Interessado" não entra no produto. Na tela, o verbo é "Trazer minha lista"; "Base de clientes" fica como nome do épico | Rodrigo e Multifunil, 11/10 |
| 7 | **Ganho marca cliente**, em todo funil de venda (#1144). Os 36 ganhos anteriores ao #1144 foram marcados pelo backfill de 11/10 | Rodrigo, 09/10 e 11/10 |
| 8 | Campo criado pela importação nasce com **nome e "Para que serve?"**, porque é a descrição que a IA do CRM lê para preencher pela conversa | Rodrigo, 10/10 |

---

## 2. O que os dados de produção mudaram

- **O telefone é a chave.** 98% dos contatos têm telefone e 1% tem e-mail. 23% dos telefones salvos têm 12 dígitos (fixo ou celular sem o nono dígito).
  - A #1006 já reconhece o contato com ou sem o 9.
  - A F1 precisa **provar** isso contra números salvos no formato do WhatsApp, porque é o maior risco de duplicar a base.
- **"Cliente" quase não existia** (4 contatos em 13.870 antes do backfill). A pergunta "Essas pessoas já são suas clientes?" é a primeira fonte real desse estado.
- **Empresas não têm dado para backfill.** Menos de 1% dos contatos tem e-mail corporativo ou nome de empresa. A empresa vai nascer da coluna da planilha (o que a #1006 já faz), da Prospecção e da IA.
  - A aba Empresas começa vazia na maioria das contas, e a jornada não pode depender dela.
- **A aba Informações está vazia.** Fora as chaves técnicas da integração WAHA, quase nenhum campo foi criado por gente. A importação vai ser a principal fonte de campos, e por isso o nome e o "Para que serve?" são obrigatórios.
- **55% dos contatos nunca conversaram** (agenda da Coexistência, bases de fora). A importação aumenta esse grupo; a lista precisa separá-lo (fase de Relacionamentos, §5).
- **`last_activity_at` falha nas contas da Coexistência** (issue #1306). Os grupos prontos dependem dessa correção.

---

## 3. Escopo da F1 (Base de clientes)

A jornada é a da pesquisa §6.2, em 4 passos visíveis: **Enviar → Conferir → Ver como fica → Pronto**. Uma ação por tela.

1. **Entrada.** "Trazer minha lista" em Relacionamentos, atrás da flag `customer_base`. Hoje a entrada fica no menu ⋮ e passa a ser botão visível.
2. **Colunas.** O Jev resolve o que tem certeza; só o que ficou em dúvida chega aberto à pessoa. Para cada coluna extra, a pergunta é **"Esta coluna fala de quem?"**, com as opções "A pessoa", "A empresa" e "Não usar".
   - "O negócio" fica para depois (§4).
   - "A empresa" só aparece com a flag `companies`.
3. **Informação nova.** O nome vem sugerido do título da coluna. O **"Para que serve?"** vem escrito a partir do formato dos valores, nunca dos valores em si, e a pessoa pode alterar. O tipo é deduzido. Grava pelo `DefinitionWriter` com descrição obrigatória.
4. **"Essas pessoas já são suas clientes?"** Todas, nenhuma, ou "Tem uma coluna que diz".
   - Cliente passa por `ContactCustomer#become_customer!(since:)`, a extensão combinada com o Multifunil:
     - a data da planilha entra quando houver;
     - vale a mais antiga entre a que já existe e a informada;
     - também atualiza quem já é cliente;
     - mantém o lock e o `save!(validate: false)`;
     - 3 specs: data informada, data existente mais antiga e cliente já existente com data mais nova.
   - Cliente nunca volta a lead pela importação.
5. **Quem já está aqui.** "340 já estão aqui": completar só o que falta é o padrão (como hoje). "Atualizar com a planilha" só entra com o valor antigo guardado (D4).
6. **De onde vieram** (D5): uma pergunta por lista, com 3 cartões. "Peguei de outro lugar" importa para atendimento e bloqueia campanha para essa lista.
7. **Consentimento.** A coluna de opt-out grava `opted_out_at` com uma origem nova em `ContactOptOut::OPT_OUT_SOURCES`, no lugar certo da precedência da `ContactMergeAction`. A importação nunca remove um opt-out que já existe.
8. **Ver como fica.** Números grandes ("Vamos criar 1.240, completar 340, deixar 12 de fora"), 3 fichas de exemplo com os dados mascarados e problemas em frase com a ação ao lado.
9. **Pronto e desfazer.** O progresso é real e roda em segundo plano. O resumo mostra os números e o link "Baixar os que ficaram de fora". O botão **"Desfazer esta importação"** fica disponível por 7 dias, para quem importou ou tem `contact_manage` (D6).
   - O lote guarda, por linha, o que fez: contato criado ou completado, com os campos e os valores anteriores; empresa criada ou ligada; cliente marcado. Tudo na tabela do fork, nada em `contacts`.
   - Desfazer não apaga contato que já recebeu conversa nem empresa ligada a outro contato.
   - Só volta a lead quem **o lote marcou e não tem card ganho**: quem ganhou depois é cliente pelo ganho (combinado com o Multifunil).
10. **Proteções da carga.** Eventos de contato silenciados (já é assim) e nenhuma automação disparada.

**Pronto quando:**
- a bateria da F0 continua com 0 erro silencioso;
- o teste de casamento de telefone passa contra números de 12 dígitos salvos pelo WhatsApp;
- desfazer devolve a conta ao estado anterior, conferido por contagem;
- o Rodrigo aceita o piloto na conta 16 com uma planilha real;
- a consulta de produção, repetida depois do piloto, mostra o uso.

---

## 4. Fora da F1

- **Criar negócio na importação** (D2 b). A v1 marca cliente sem card. O card opcional, com funil e etapa, vem depois das proteções da pesquisa §6.2: webhook `crm.card.created` silenciado, cards fora do `StaleCardsJob`/`Evaluator` até ter conversa, `inbox_id` preenchido.
- **Preencher pela conversa antiga** (D7). A promessa é só para conversa nova, com texto honesto na tela.
- **Grupo virar público de campanha** (D11).
- **Conectores e histórico do WhatsApp** (F3) e **exportação/LGPD** (F4), incluindo o prazo de guarda do `extra_values` sem máscara.

---

## 5. Fase seguinte: remontagem de Relacionamentos

Está no mockup, mas é entrega própria, depois da F1:
- lista com busca tolerante, pílulas com números reais ("820 clientes · 1.400 ainda não compraram · 32 não querem mensagens") e grupos prontos ("Falou com você há pouco", "Sumiu há…", "Nunca conversou", "Clientes", "Não quer mensagens");
- ficha com cabeçalho, até 6 destaques, conversas e negócios no centro, e "Informações" como lugar único, com todos os campos da conta e "Não informado" (D12). As chaves técnicas (`waha_*`) ficam escondidas.

Depende de:
- **#1306** (`last_activity_at` da Coexistência), para os grupos por tempo;
- filtros de `contact_type` e `opted_out_at` em `filter_keys.yml` e `contactProvider.js`;
- a decisão do menu (§6).

---

## 6. Decisões em aberto para o Rodrigo

| # | Decisão | Recomendação |
|---|---|---|
| M1 | **Nome do menu.** Hoje existem "Relacionamentos" e "Contatos" lado a lado. (i) Um item só, "Contatos", com as abas Pessoas e Empresas. (ii) Manter "Relacionamentos", com as abas Contatos e Empresas | (i): acaba com o item duplicado e é concreto. Não bloqueia a F1; bloqueia a remontagem |
| D4 | Atualizar quem já existe | Completar como padrão; "Atualizar" só com valor antigo guardado |
| D5 | Origem e permissão da lista | Uma pergunta por lista; "Peguei de outro lugar" bloqueia campanha |
| D6 | Prazo do desfazer e quem pode | 7 dias; quem importou ou `contact_manage` |

---

## 7. Riscos

- **Duplicar a base pelo nono dígito.** Mitigação: o teste do item "Pronto quando", com números reais do formato WhatsApp, antes do piloto.
- **Desfazer incompleto.** Mitigação: guardar o valor anterior por linha antes de gravar e conferir o desfazer por contagem no piloto.
- **Campo criado com nome de pessoa** (cabeçalho lido errado). Mitigação: a F0 já detecta planilha sem cabeçalho (`HeaderLocator`). A tela mostra o nome sugerido para a pessoa confirmar antes de criar.
- **Expectativa de Empresas cheias.** Mitigação: a jornada funciona sem empresa, e a tela não empurra para a aba Empresas.
