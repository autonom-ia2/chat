# Contrato de atributos e apresentação — #757

Três flags independentes, inicialmente falsas no catálogo por conta:
`relationships_attributes`, `relationships_company_media`, `relationships_navigation`.
A habilitação usa a administração existente de flags; o endpoint de apresentação
não permite habilitar módulos. Nenhum campo novo em auth/billing ou migração de banco.

## Configuração e definição

`GET /api/v1/accounts/:account_id/relationships/configuration` retorna configuration,
definitions e can_manage. Cada definição inclui a revisão ISO8601 com microssegundos.
`PATCH` recebe `{ configuration: { revision, surfaces?, definition?, display_on? } }`.
Só `attribute_manage` altera configuração/definição. Leituras seguem a policy de atributos.
Empresas desligado remove suas definições da resposta e impede novas ações.

A configuração usa version=1, revision inteiro e surfaces. Superfícies aceitas:
contact_sidebar, contact_details e company_details. Cada seleção contém mode
(legacy/custom) e ids de definições da própria conta e entidade. Array vazio em modo
custom significa zero campos. Ausência/legacy mantém a lateral antiga e não destaca
campos no centro. Restaurar padrão é explícito por superfície. IDs removidos são
ignorados/limpos na leitura; valores nunca são apagados pela apresentação.

Uma transação com lock de Account recarrega settings, confere revisão, salva definição,
valida layout e mescla apenas relationships. Erro reverte ambos. Nome duplicado dá erro;
chave duplicada mantém a validação única existente. Ao editar, a definição também é
bloqueada e sua revisão conferida. Chave, entidade e tipo não podem mudar neste fluxo.
A chave nova usa attributeKey: decomposição Unicode, caracteres ASCII explícitos e separadores, sem regex.
`job_title` permanece `job_title` ao renomear para Cargo; valores como CEO não são migrados.

Descrição é obrigatória ao criar pelo novo endpoint; legados sem descrição continuam
editáveis. Metadados históricos de validação e orientação são preservados sem interpretação.
O novo editor não cria nem altera padrões; renomear não reenviará opções inalteradas. Conversas continuam na Central,
sem nova política de apresentação de Conversa. Não há chamada de modelo/IA.

## Valores

`PATCH /relationships/:entity/:id/values`, entity contact/company, recebe
`{ field: { key, value, previous } }`. O servidor valida a definição da conta, aplica a
policy existente da entidade, bloqueia o registro, compara previous e modifica uma chave.
`null` limpa a chave. Zero e falso são valores; número vazio vira null somente no cliente.
Número em string enviado diretamente à API é inválido. Data exige YYYY-MM-DD válido e é
armazenada sem converter fuso. Links aceitam HTTP/HTTPS; lista exige opção existente;
atributos com validação histórica são rejeitados explicitamente, inclusive limpeza.
Para esses valores, o componente e endpoint legados continuam sendo usados. Não há matcher novo. Tipos legados currency/percent continuam
aceitando números, mas não são novos tipos disponíveis no editor de definição.

O cliente só anuncia Salvo após resposta; falha mantém rascunho. IDs de conta/registro
capturados e gerações de requisição impedem respostas antigas de alterar outro contexto.
A atualização local alimenta os stores atuais para refletir ficha/lateral/aba completa.
O botão compacto fica no conteúdo do accordion de contato; AccordionItem permanece intacto.
A ordem pessoal continua aplicada depois da seleção global. Ocultar não significa sigilo.

## Aditivo da retomada de 29/09

A regra sem regex prevalece sobre o plano inicial e sugestões de subprocesso Node.
Nenhuma definição nova aceita `regex_pattern`/`regex_cue` no endpoint novo. As chaves
existentes nunca mudam. Os campos de regras não aparecem no modal ou em suas traduções.
A compatibilidade com valores históricos reutiliza CustomAttribute e a rota legada;
ela não autoriza novas expressões, normalizadores, motores ou traduções Ruby/JavaScript.
`pnpm relationships:check` compara ASTs JS/Vue/TS e Prism Ruby contra a base aprovada,
incluindo testes e scripts novos. Nós históricos são permitidos apenas na quantidade e
forma existentes no mesmo arquivo; o gate não faz busca textual com regex.

Configurar campos e Criar atributo são ações diretas; o contexto preseleciona o local.
O aviso global significa esta conta. Ambos dependem do recurso base custom_attributes,
da extensão e da permissão de gestão; Empresas também exige companies.
Account settings e custom_attributes de Contato/Empresa no legado fazem leitura e merge
sob o mesmo lock do novo fluxo. Specs de requisições concorrentes aguardam a execução PostgreSQL.
No cliente, cada confirmação modifica somente sua chave no store vivo, incluindo remoção.
Datas mantêm o dia escrito, inclusive timestamps ISO históricos, em ficha, aba e lateral.
Cache é separado por sessão/store, usuário e conta; logout, contexto, saves e foco invalidam
leituras. As definições confirmadas alimentam o store legado com proteção contra GET atrasado.
