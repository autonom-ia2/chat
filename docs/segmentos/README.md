# Palavras por segmento (pacotes de tradução por conta, #1550)

Cada conta pode falar a língua do seu negócio. Uma corretora vê "Seguro ativo"
onde o painel geral diz "Ganho"; uma corretora de planos de saúde vê "Implantado". O
catálogo geral não muda: o pacote da conta é composto por cima dele, só nas
chaves que o pacote traz.

Para pôr um tipo novo no ar, do vocabulário à conta de verdade, siga
[`novo-segmento.md`](novo-segmento.md).

## Camadas

A escolha vem do super admin (Contas → Segmento e nicho da conta), lida por
`Autonomia::Agents::Nicho`. Dela saem as camadas, da mais geral para a mais
específica:

| Escolha da conta | Camadas |
|---|---|
| geral | nenhuma (catálogo geral) |
| seguros → corretora | `seguros`, `seguros/corretora` |
| seguros → saúde e benefícios | `seguros`, `seguros/saude_beneficios` |

A busca é por chave: a camada mais específica que tiver a chave vence; sem
ela, a de cima; sem nenhuma, o catálogo geral. Pasta de tipo sem arquivo é
normal: o tipo herda tudo de `seguros`.

A insurtech sem canal informado vale "direto", na conta e no padrão da instalação.
O canal da insurtech (direto, corretores, parceiros) fica guardado, mas não
vira camada nesta fase.

## Quem ganha

1. **Nome dado pela conta** (por exemplo, o rótulo de desfecho que a conta
   gravou no funil, `metadata.outcome_labels`).
2. **Pacote do segmento.**
3. **Catálogo geral.**

O pacote só troca o que `t()` devolve; o nome dado pela conta é lido antes
de `t()`, no painel (`cardStatusLabel`) e na planilha do CRM
(`Crm::Cards::Outcome.custom_label`), então continua vencendo.

## Interruptor

`AUTONOMIA_PACOTES_ENABLED` (por stack, desligado por padrão). Desligado, toda
conta usa o catálogo geral, o payload da conta traz `autonomia_pacote: null` e
a escolha do super admin fica guardada, valendo quando o interruptor ligar.

## Onde ficam os arquivos

- Painel: `app/javascript/dashboard/i18n/pacotes/<camada>/<en|pt_BR>.json`,
  com a mesma estrutura aninhada do catálogo do painel (por exemplo,
  `CRM_KANBAN.CARD_STATUS.WON`, de `crm.json`).
- Servidor (e-mails, exportações, respostas da API):
  `config/pacotes/<camada>/<en|pt_BR>.yml`, com raiz `en:`/`pt_BR:` e o mesmo
  caminho de `config/locales` (por exemplo, `crm.export.statuses.won`).

Os pacotes não vão ao Crowdin e não entram no `load_path` do Rails: são
lidos por `Autonomia::Segmentos::Catalogo` dentro de `Pacotes.with(conta)`.

Fora do i18n, com as mesmas camadas (#1802, lote 6; detalhes em
`lote6-guia-central-agentes-f2.md`):

- Guia: `lib/operator_guide/pacotes/<camada>/porques.md`, só os campos de
  texto que mudam; o `pnpm guia:build` gera o `guia-produto.md` da camada.
- Central de Ajuda: `lib/central_de_ajuda_pacotes/<camada>/<cap>/<id>-<slug>.md`,
  só as seções que mudam; a troca é feita na leitura da conta.
- Agentes: `config/agentes_por_pacote/seguros/<tipo>/agentes.md`, o bloco de
  segmento (`Autonomia::Segmentos::Bloco`). Ao lado dele, `versoes.yml` (a data em
  que cada versão do texto entrou no ar: quem edita o `agentes.md` registra a
  versão nova com a data prevista do deploy) e `perguntas.yml` (as 3 perguntas,
  em `pt_BR` e `en`, do antes e depois de "Atualizar com a nova base", #1429 F3).
  Mudar o `agentes.md` muda a versão, e o spec do bloco falha até a versão nova
  ter data.

Essas camadas trocam o campo ou a seção inteira: mudança no texto geral de um
trecho que a camada sobrepõe precisa ser repetida nela.

## Como acrescentar uma chave

1. Achar a chave no catálogo geral (painel ou servidor). O pacote só pode
   trocar uma mensagem que já existe lá, como texto.
2. Escrever a troca em `en` **e** `pt_BR` da mesma camada, com as mesmas
   chaves e os mesmos parâmetros (`{x}` no painel, `%{x}` no servidor).
3. Rodar `pnpm i18n:fork:check` (o check `Fork translations` do CI faz o
   mesmo). Ele reprova chave que não existe no base, idioma faltando, chaves
   diferentes entre idiomas, parâmetro trocado, camada fora de `seguros` e
   `seguros/<tipo>`, raiz do yml diferente do nome do arquivo e mensagem vazia.
4. **Reiniciar o servidor** depois de editar um yml: o catálogo do servidor é
   carregado uma vez por processo. O painel pega o json novo no próximo build.

Tipo novo de segmento entra em três lugares juntos:
`Autonomia::Agents::Nicho::PERFIS`, `pacotes.segmentos` em
`config/fork_i18n.json` e os textos do super admin
(`config/locales/autonomia_agents_niche.*.yml`). A spec
`spec/config/pacotes_segmentos_spec.rb` reprova se o registro e o nicho
divergirem.

## Ganho e perdido nas contas de seguros

Conta de seguros não "ganha" nem "perde" negócio: o seguro fecha ou não fecha.
A camada `seguros` troca todo texto do resultado de venda; a camada
`seguros/saude_beneficios` troca o desfecho que deu certo por "Implantado" e
o que diz "seguro" por "plano" (vocabulário em `funis-saude.md`). O resto a
saúde herda, inclusive "Não fechou".

### Regras do texto

1. **Selo, aba, filtro, legenda de status e condição de automação:** "Seguro
   ativo" / "Não fechou" (en: "Active policy" / "Not closed"; saúde:
   "Implantado").
2. **Botão, histórico, evento e selo de evento enviado à Meta:** "Fechou o
   seguro" / "Não fechou" (en: "Policy closed" / "Not closed"; saúde:
   "Marcar como implantado", nunca "fechou o plano").
3. **Confirmação:** "Marcar: fechou o seguro" / "Marcar: não fechou". **Aviso:**
   "Marcado: fechou o seguro." / "Marcado: não fechou."
4. **Números do painel:** título do KPI "Seguros fechados" (saúde "Planos
   implantados") / "Não fecharam"; colunas e legendas "Fecharam" / "Não
   fecharam"; "Taxa de fechamento"; "Valor fechado" / "Valor que não fechou".
5. **"Fechar" quer dizer só que deu certo.** Texto que fala dos dois
   resultados, ou que também aparece no funil de atendimento, usa "terminou".
6. Nunca "perda" nem "perdido".
7. Texto de "não fechou" sem a palavra "seguro", para a saúde herdar.
8. **"Negócio" sai** do resultado (botão, diálogo, histórico, aviso, reabrir,
   erro): entra "seguro", "plano" ou "card". "Venda" fica onde o texto já fala
   de anúncio.
9. Nenhum texto diz "segurado".
10. Saem "qtd", "ponderada por receita", "throughput", "pacing", "vs" e "÷".
11. Nenhuma variável muda (`{stage}`, `{count}` com o plural `|`, `{won}`,
    `{label}`).

Chaves que nenhuma tela usa hoje (por exemplo `CRM_KANBAN.CARD_STATUS.*`,
`DRAWER.WIN_DEAL`, `GOOGLE_SYNC.EVENT_*`, `CALENDAR.EVENT.*`) também estão no
pacote, com texto que segue as regras: podem voltar por chave montada.

Ficam fora do pacote, porque o pacote não chega neles: as etapas "Fechado" já
gravadas nos funis (dado no banco), os prompts da IA, a conversão
`'Lead Perdido WhatsApp'` do Google Ads, o texto fixo de `card.rb`, o
`automation_rule_schema/acoes.rb` (formatos do Guia). O Guia e a Central de
Ajuda têm camadas próprias (veja abaixo).

### Trava de cobertura (CI)

`scripts/i18n-pacotes/cobertura.mjs`, chamado pelo `pnpm i18n:fork:check`,
percorre todo texto do catálogo base do painel (como `locale/<idioma>/index.js`
monta) e do servidor (`config/locales`), em en e pt_BR, e acha os que falam em
ganho/perda:

- pt_BR: o texto, em minúsculas, contém "ganh" ou "perd";
- en: tem a palavra inteira "won", "win", "lost", "lose", "loss" ou "winning"
  ("won't" não conta);
- nome de parâmetro (`{won}`, `%{x}`) não conta.

A trava não procura "fech", "venda" nem "close": essas palavras também
servem ao atendimento ("fechar a conversa"), e o próprio pacote usa "fechou".
Texto com elas passa sem decisão; ampliar a busca é decisão em aberto.

Cada chave achada precisa de uma decisão:

1. **Está na camada `seguros`** do pacote (painel ou servidor), com texto que
   segue as regras acima; ou
2. **Está em `scripts/i18n-pacotes/fora-do-pacote.json`**, com o motivo (ligação
   perdida, prazo de SLA, perder acesso, "ganha a marca"...).

O CI reprova chave nova com ganho/perda sem decisão e diz o que fazer. Também
reprova exceção sem motivo, exceção cuja chave não existe mais no catálogo base ou não
fala mais em ganho/perda, chave que está no pacote e nas exceções, e texto do
próprio pacote que ainda diz ganho/perda. Uma atualização do Crowdin que traga
texto novo com essas palavras também para no CI até alguém decidir.

### O interruptor espera o #1584

`AUTONOMIA_PACOTES_ENABLED` **não liga** antes de a IA, o Guia e a Central de
Ajuda falarem a mesma língua (#1584). Com o painel dizendo "Fechou o seguro" e a
IA ou a Central dizendo "Ganhou", a equipe vê dois nomes para a mesma coisa.

## Fora desta fase

Conteúdo por tipo além do mínimo, instrução do Guia por pacote, Central em
inglês por pacote, página pública e canal como camada.
