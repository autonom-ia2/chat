# Palavras por segmento (pacotes de tradução por conta, #1550)

Cada conta pode falar a língua do seu negócio. Uma corretora vê "Seguro ativo"
onde o painel geral diz "Ganho"; uma operadora de saúde vê "Plano ativo". O
catálogo geral não muda: o pacote da conta é composto por cima dele, só nas
chaves que o pacote traz.

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

## Fora desta fase

Conteúdo por tipo além do mínimo, funis, Central de Ajuda e Guia por pacote,
página pública e canal como camada.
