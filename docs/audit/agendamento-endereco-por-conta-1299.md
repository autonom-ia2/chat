# Agendamento: endereço por conta `/a/<conta>/<página>` e campo recolhido (#1299)

## Contexto

O #1282 criou o link curto `/a/<página>`, com o nome da página único na instalação inteira. Decisão do Rodrigo (11/10/2026): o link passa a ser `/a/<conta>/<página>` (e `/a/<conta>/<página>/<pessoa>`), o nome da página fica único só dentro da conta, e o passo do assistente mostra o link pronto, com o campo recolhido atrás de "Mudar endereço". Páginas que já existiam ganham endereço sozinhas no deploy.

## Decisões

- **Endereço da conta em tabela própria.** `crm_booking_account_addresses` (`account_id` único, `name` único), sem coluna em `accounts`. A unicidade é do banco. Some com a conta (`ON DELETE CASCADE`).
- **Nasce sozinho, só em gravação.** `Crm::BookingV2::AccountAddress.ensure!` cria o endereço quando uma página nova da conta é gravada (criar, salvar, publicar: `after_commit` do modelo, fora da transação da página) e no preenchimento do deploy. Nenhuma leitura cria: lista, página, conferência de nome (que é `GET`) e as rotas públicas só leem, e conta sem endereço numa leitura segue com o link comprido `/book/<uuid>`. `ensure!` pode ser chamado quantas vezes for: relê, tenta gravar num savepoint e, se o índice único barrar, relê de novo (mesma conta) ou sugere o próximo número (outra conta com o mesmo nome). Vem do nome da conta, com as mesmas regras do nome da página (`ShortName`: 3 a 40 caracteres, minúsculas sem acento, números e hífen, sem os nomes do sistema) e número quando já tem dono. Não muda quando a conta troca de nome.
- **Nome da página único por conta.** O índice único global de `short_name` deu lugar a `(account_id, short_name)`. A conferência "está livre?" e a sugestão só olham as páginas da própria conta: a tela não revela mais nome de página de outra conta.
- **Resolução do link, nesta ordem** (`Crm::BookingV2::ShortLink.resolve`):
  1. o primeiro pedaço é endereço de conta: formato novo, e só páginas dessa conta entram. `/a/<conta>` sozinho abre a página da conta quando ela tem exatamente uma no ar; com mais de uma, a casca de "não encontrada", sem listar nada. Se o formato novo não acha, vale o formato antigo dentro da mesma conta (conta cujo endereço é igual ao nome de uma página dela);
  2. senão, o formato antigo (`/a/<página>`, `/a/<página>/<pessoa>`), que só abre enquanto existir exatamente uma página com aquele nome na instalação.
- **Sem marcador de legado.** Produção tinha uma única página com nome curto antes desta entrega. Não foi criada coluna nem tabela para marcar "nome antigo".
- **Travas contra abrir página de outra conta.** Um endereço de conta não nasce igual ao nome de página de outra conta (`AccountAddress.problem`), então não passa na frente do link antigo dela. Com endereço de conta no primeiro pedaço, nenhuma busca sai da conta. Com duas páginas de mesmo nome em contas diferentes, o link antigo responde "não encontrada" em vez de escolher uma.
- **Painel.** O passo mostra "O link fica assim: `<site>/a/<conta>/<página>`" e o botão "Mudar endereço" (botão de verdade, 44 px, `aria-expanded`). O campo abre só a parte da página, com a parte da conta fixa antes dele. Abre sozinho quando o servidor recusa o endereço, quando a conferência acha problema e quando não vem sugestão. Página que já tem endereço não muda quando o nome do atendimento muda.
- **`/book/<uuid>` continua funcionando**, e a API pública continua recebendo só o slug opaco.
- **Imagem de prévia não é redesenhada.** A versão dela (`PreviewImage::Content#version`) sai do desenho, da cor, dos textos e das imagens; o endereço não entra.

## Migrations

- `20261017100000_scope_booking_short_names_to_account` (esquema): cria a tabela, cria o índice `(account_id, short_name)` concorrente e só depois remove o índice global, também concorrente (`disable_ddl_transaction!`). Índice inválido de uma tentativa interrompida é apagado e recriado. `down` completo: recria o índice global, remove o por conta e apaga a tabela. O índice global só volta se nenhum nome se repetir entre contas.
- `20261017100100_backfill_booking_short_names` (dados): chama `Crm::BookingV2::ShortNameBackfill`.

## Preenchimento das páginas que já existiam

O que grava, por conta que tem página nova (page_version 2), numa transação por conta:

1. `crm_booking_account_addresses`: uma linha (`account_id`, `name`), se a conta ainda não tem. Vale também para a conta em que todas as páginas já têm nome (a página de teste que já existia em produção): o nome dela fica como está, e o link curto dela passa a ser `/a/<conta>/<nome>`.
2. `crm_agent_booking_profiles.short_name`: nas páginas novas em que está vazio, e só se continua vazio no momento de gravar (alguém que salvou um nome durante o deploy não é sobrescrito). Só esta coluna; `updated_at` não muda.
3. `crm_agent_booking_links.metadata['short_name']`: o apelido das pessoas dessas páginas que ainda não têm (o mesmo `PersonNames` do #1282).

Equivalente em SQL, para ler (o nome sai da regra em Ruby, não de SQL):

```sql
-- contas que ganham endereço (as que têm página nova e ainda não têm linha)
SELECT DISTINCT account_id FROM crm_agent_booking_profiles
WHERE page_version = 2 AND account_id NOT IN (SELECT account_id FROM crm_booking_account_addresses);
-- páginas que ganham nome
SELECT account_id, id FROM crm_agent_booking_profiles
WHERE page_version = 2 AND (short_name IS NULL OR short_name = '') ORDER BY account_id, id;

-- por conta, se ainda não houver linha
INSERT INTO crm_booking_account_addresses (account_id, name, created_at, updated_at) VALUES (:conta, :endereco, now(), now());
-- por página sem nome
UPDATE crm_agent_booking_profiles SET short_name = :nome WHERE id = :pagina;
-- por link de pessoa sem apelido, nas páginas acima
UPDATE crm_agent_booking_links SET metadata = metadata || jsonb_build_object('short_name', :apelido), updated_at = now() WHERE id = :link;
```

Regra do nome: endereço da conta a partir do nome da conta; nome da página a partir do título. Nos dois: sem acento, minúsculas, espaço e pontuação viram hífen, no máximo 40 caracteres sem hífen na ponta; texto vazio, com menos de 3 caracteres ou igual a um nome do sistema ganha `agenda` na frente. Colisão soma número (`-2`, `-3`…): a página dentro da conta, o endereço da conta entre todas as contas (e contra nomes de página de outras contas).

Idempotência: página que já tem nome não é selecionada; conta que já tem endereço não ganha outro. Rodar de novo não grava nada (`spec/services/crm/booking_v2/short_name_backfill_spec.rb`, "rodar de novo não muda nada", compara endereços, nomes, apelidos e `updated_at` antes e depois). Conta que falha é desfeita inteira, vai para o log e para o resumo da migration, e não para as outras.

Por que serviço, e não modelos dentro da migration: a regra do nome precisa ser a mesma da tela, e copiá-la para a migration criaria duas versões. A migration procura o serviço pelo nome; se ele sair do código no futuro, ela vira um aviso (banco novo não tem página para preencher).

### Como desfazer

O `down` da migration de dados não apaga nada, de propósito: depois do deploy os links já foram divulgados, e não há como separar o nome que a migration deu do nome que a pessoa escolheu. Para desfazer à mão logo depois do deploy, antes de alguém usar a tela, guarde antes as listas dos dois `SELECT` acima e rode, com os ids delas:

```sql
UPDATE crm_agent_booking_profiles SET short_name = NULL WHERE id IN (:paginas_da_lista);
DELETE FROM crm_booking_account_addresses WHERE account_id IN (:contas_da_lista);
```

Não é desfeito: os apelidos das pessoas (`metadata.short_name` dos links), que sem o nome da página não aparecem em link nenhum; e qualquer link curto que alguém já tenha copiado, que para de abrir (o `/book/<uuid>` segue abrindo).

## Riscos aceitos, para o Rodrigo decidir se quer mudar

- **Link antigo `/a/<página>` morre na primeira repetição.** Sem marcador de legado, ele abre enquanto o nome for de uma página só na instalação. Quando outra conta criar (ou o preenchimento der) uma página com o mesmo nome, o link antigo passa a responder "não encontrada". O link novo e o `/book/<uuid>` não são afetados.
- **Página nova também responde no formato antigo enquanto o nome for único.** É consequência de não marcar legado: `/a/<página>` abre a página de qualquer conta que seja a única com aquele nome. O painel nunca mostra esse endereço.
- **Nome antigo liberado pode ser reusado.** Se a dona de um link antigo renomear ou apagar a página, e outra conta criar uma página com o mesmo nome, o link antigo abre a página da outra conta. O #1282 já tinha esse comportamento (renomear liberava o nome para a instalação inteira).
- **Endereço de conta revela que o nome tem dono.** O número no endereço (`empresa-2`) diz que `empresa` já é endereço de outra conta ou nome de página de outra conta. É inerente a nome global.
- **Página de outra conta pode "reservar" um endereço.** Uma conta que crie uma página chamada como outra empresa, antes de essa empresa ganhar endereço, faz a empresa nascer com número. O endereço nasce quando a conta grava a primeira página, o que reduz a janela.
- **`/a/<conta>` conta páginas no ar.** Quem tem o endereço da conta descobre se ela tem exatamente uma página no ar (abre) ou não (não encontrada). Não lista nem cita página nenhuma.
- **Janela do deploy.** O índice global sai na migration; se o código antigo ainda estiver respondendo em alguma instância nesse intervalo, ele busca a página só pelo nome, sem a conta. Para isso dar errado, duas contas precisam gravar o mesmo nome de página nesses minutos.
- **Conta que falha no preenchimento não derruba o deploy.** Ela fica no log e no resumo da migration, as páginas seguem com o link comprido e ganham o endereço ao serem abertas em Editar. A alternativa é a migration falhar e travar o deploy até alguém olhar.

## Pendências

- **Trocar o endereço da conta** (só administrador, com aviso de que os links antigos param): ficou fora desta entrega. Não há tela nem endpoint; hoje o endereço só muda por suporte.

## Revisão independente

Revisor `caveman:cavecrew-reviewer`, com foco em link de uma conta abrindo página de outra, enumeração, migration e formato antigo. Não achou caminho em que um endereço abre página de conta errada. Corrigidos: `lock_timeout` na criação da tabela (a chave estrangeira trava `accounts` por um instante), modelos da migration de dados buscados pelo nome, `aria-controls` só com o campo aberto, parte fixa do campo escondida se a conta vier sem endereço, comentário sobre `updated_at`. Recusado: barrar nome de página igual ao endereço de outra conta (a página continua abrindo pelo endereço da própria conta, e barrar faria a tela revelar endereços alheios). Ficaram como risco aceito, acima: o link antigo que morre na primeira repetição, a janela do deploy e a conta que falha no preenchimento. A gravação dentro da leitura, apontada na primeira passada, saiu: a fila pediu e o endereço agora só nasce em gravação. Anotado, sem mudança: a recusa do servidor vale para o endereço que está no campo quando ela chega (se a pessoa digitar durante o salvamento, o aviso aparece no texto novo).

Segunda passada (depois do merge com o #1302 e da saída da escrita na leitura). Não achou perda do #1302 no merge, leitura que grave, nem link que abra página de outra conta. Corrigidos: o preenchimento não sobrescreve nome salvo durante o deploy (grava só se a página continua sem nome); falha ao criar o endereço da conta não derruba mais a gravação da página (vai para o log, a página fica com o link comprido e a próxima gravação tenta de novo); memória do endereço também para "sem endereço" (sem consulta repetida); `aria-describedby` só com o que está na tela; spec de concorrência prova que uma das duas tentativas perdeu e tentou de novo; spec de leitura pública confere status e slug de cada endereço. Recusado de novo, pelo mesmo motivo: barrar nome de página igual ao endereço de outra conta. O caso apontado (link antigo de uma página renomeada passando a abrir outra conta) é o risco "nome antigo liberado pode ser reusado", acima.

Terceira passada (sobre o ajuste da leitura e o merge do #1304). Não achou dado errado no preenchimento, perda do #1304 nem transação envenenada. Corrigidos: o endereço da conta passou a nascer depois do commit da página (`after_commit`), então a gravação da página não segura a linha do endereço e não trava com o preenchimento do deploy; qualquer erro de banco ao criar o endereço (não só a disputa do nome) vai para o log sem desfazer a página; o preenchimento tenta de novo, uma vez, a conta que bater em trava ou impasse; a memória do endereço é limpa no `reload` e a leitura usa só o `account_id`; o comentário do endereço da conta diz que a regra vale num sentido só, e por quê; specs mais estritos (a disputa perdida dentro da transação aparece nas tentativas; cada conta com o endereço certo; leitura conferida no banco). Ficaram: o link antigo `/a/<página>` que morre na primeira repetição de nome (decisão já registrada; antes do deploy, vale conferir se o nome da única página antiga em produção coincide com o título de alguma página sem nome de outra conta) e a lista de páginas com uma consulta de endereço por página (poucas páginas por conta).

## Validação local

- RSpec focado: nome por conta e índices, endereço da conta (inclusive duas conexões ao mesmo tempo e leitura que não grava), resolução (novo, antigo, ambíguo, outra conta, pessoa), preenchimento, casca pública e Open Graph, API do painel, limites, policy, modelo, formatos do Guia.
- `db:migrate`, `db:migrate:down` das duas versões e `db:migrate` de novo no banco de teste; `db/schema.rb` só com a tabela nova, o índice novo e a saída do índice global.
- Vitest de `settings/booking` e do cliente da API.
- RuboCop, ESLint, Prettier e o gate de proteção: sem bloqueio.
- `autonomia:guia:formatos` + `:check`, `guide-map/build` + `check`, `check-fork-i18n` e `central-de-ajuda/conferir`: em dia.
- Conferência visual do passo (recolhido, aberto livre, aberto indisponível, recusado pelo servidor, mudando endereço salvo) em Chrome headless, a 800 px e a 390 px.
- Não foi conferido em navegador real nem em produção.
