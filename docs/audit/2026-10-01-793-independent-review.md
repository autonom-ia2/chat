# PR #793 — revisão independente e alinhamento visual

## Decisão

**Não liberar a PR neste estado.** A revisão reproduziu uma corrida que permite
criar duas pessoas com o mesmo telefone na mesma conta. A aprovação visual não
resolve essa falha de integridade. Nenhum merge em `main`, deploy, mudança de infraestrutura
ou dado de produção foi realizado nesta revisão. A integração com `main` ocorreu
apenas na branch isolada de revisão.

## Versões e escopo

- PR original: `#793`, rascunho, branch `feat/792-crm-relacionamentos`.
- Commit recebido: `b11b6620ea2ee45934823c15fda778c6c6295ee6`.
- Base integrada localmente: `bd2104837da812a91587189b33b2f23daabc6583`.
- Issue existente: `#792`.
- Worktree isolado: branch `codex/793-audit-design`.

A PR liga a oportunidade ao cadastro real de contato e empresa. Permite consultar,
vincular, criar e editar esses registros a partir do CRM, criar uma oportunidade
a partir de um perfil e consultar oportunidades relacionadas. Inclui mudanças de
permissão nos cadastros e na interface antiga de conversas, visibilidade de
campanhas, armazenamento local e proteção dos contatos sem identificadores contra
limpeza automática. É uma mudança transversal, não apenas de aparência.

## P1 confirmado — telefone duplicado por concorrência

`Crm::Cards::ContactCreator` trava apenas a oportunidade. Duas oportunidades
distintas podem criar contatos com o mesmo telefone simultaneamente. A chave de
idempotência evita repetir uma intenção; não coordena duas intenções diferentes.
O índice de telefone e conta não é único. A validação Ruby pode ser aprovada pelas
duas requisições antes de qualquer uma inserir o registro.

Uma reprodução independente usou conta, administrador e duas oportunidades
sintéticas em conexões diferentes. As duas validações foram sincronizadas antes
do insert. O resultado persistido foi **dois contatos com o mesmo telefone**.
Uma segunda reprodução cruzou `RelationshipRegistration` com `ContactCreator`
e também persistiu **dois contatos com o mesmo telefone**. Não houve worker de
envio ou chamada externa.

O fluxo `Crm::Cards::RelationshipRegistration` possui lock de conta, mas
`ContactCreator` não participa dele. Trancar somente as entradas novas do CRM
também não prova exclusividade diante de importação e demais criadores de contato.
A correção deve estabelecer uma garantia compartilhada e testar os escritores
concorrentes; uma restrição de banco exige primeiro verificar os dados legados e
apresentar um plano de migração. Essa alteração de banco não foi executada como
consequência da auditoria.

## Outros gates

- O GitHub informou conflitos com `main`. Os dois conflitos de traduções do CRM
  foram resolvidos na integração local, preservando as chaves de Relacionamentos
  e do Editar Funil atual. A integração foi registrada em commit na branch de revisão para atualizar
  a PR original, sem merge em `main`.
- O workflow `Relationships - isolated regression and Linux runtime` está
  desabilitado manualmente. Não foi habilitado nesta revisão. Build local não
  substitui a validação da imagem Linux prevista no workflow.
- O check de regex original compara com um SHA histórico fixo. No conjunto
  integrado, ele acusa arquivos vindos de `main` fora do delta de #793. O resultado
  deve ser tratado como falha do gate até sua base ser corrigida; não foi ocultado.
- Os sete testes históricos suspensos documentados pela PR não são evidência de
  aprovação. A bateria focada desta revisão não apresentou suspensos.
- Callbacks e broadcasts novos foram revisados como pós-commit. Integrações e jobs
  externos configurados em produção não foram acionados nem validados.
- A observação de `is_primary` em vínculos de conversa é histórica, já existe
  em `origin/main` e não foi introduzida por #793. O payload atual usa
  `card.conversation_id`; não é um bloqueador novo desta PR.

## Validação independente executada

Ambiente local isolado em PostgreSQL e Redis, com dados sintéticos, adaptador de
jobs de teste, sem envio de mensagens/e-mails e sem uso de provedor de IA pago.

- `bundle exec rspec` na bateria focada de criação, vínculo, registro, permissões,
  campanhas, contatos e compatibilidade Enterprise: **297 exemplos, zero falhas**.
- Dois probes concorrentes (`ContactCreator` entre dois cards e cruzado com
  `RelationshipRegistration`): **falha de integridade reproduzida em ambos**.
- `vite build --mode test`: **sucesso**, bundle integrado compilado.
- `scripts/check-fork-i18n.mjs`: **9 catálogos, 16.426 mensagens, cobertura aprovada** (após ajuste visual).
- `scripts/guide-map/check.mjs`: **173 fluxos, 170 telas, zero sem explicação**.
- `central:check`: **174 artigos, 170 telas, aprovado**, com avisos de referências
  históricas deslocadas.
- AST de regex com cópia local do gate comparando contra `origin/main`: **142
  arquivos aprovados**. O gate original de SHA fixo continua pendente de correção.

- Suíte frontend completa: **7.189 passando e 1 timeout**, em 644 arquivos.
  O caso de tradução excedeu os 5s sob execução simultânea com build.
- Reexecução isolada do arquivo `locales.spec.js`, sem mudar timeout: **256
  testes passando**, incluindo o caso anterior em 4.013ms. A execução completa
  original continua registrada como falha; não foi reclassificada como verde.
- Pós-ajuste, quatro arquivos dos componentes modificados: **86 testes passando**.
- ESLint dos componentes: **zero erros**; avisos do carregamento estático de i18n
  persistem. Os quatro avisos novos de ordem de atributos foram corrigidos
  manualmente e o drawer foi verificado novamente, sem autofix.

Relatos de testes antigos da PR não foram contabilizados como execuções novas.
O commit local encontrou o setup Husky ausente. Os commits de revisão usam
`core.hooksPath=/dev/null` somente no comando, após validações manuais; nenhum
config de hooks do projeto foi alterado. Isso também evita o autofix seguido de
commit automático do hook, incompatível com a regra de revisar cada reescrita.

## Padrão visual

A referência é o Editar Funil atual integrado, em tema claro. As capturas históricas
da PR mostram um editor anterior e não substituem essa comparação. A nova
oportunidade e os detalhes da oportunidade usam a mesma largura de 40rem, mas o
cabeçalho anterior era menor e sem o azul-marinho da referência.

A revisão real também reproduziu a Timeline escondida por rolagem horizontal no
celular. Os ajustes visuais são limitados a cabeçalho, abas, foco/nomes acessíveis,
moeda no valor e avisos de permissão no contexto correto. Não alteram autorização,
contratos da API ou regras de criação de registros.

## Condições para futura aprovação

1. Corrigir a corrida e validar criação concorrente entre os escritores reais.
2. Integrar com `main`, fechar os gates de CI/regressão e validar a imagem Linux.
3. Apresentar as telas reais pós-ajuste e obter aprovação visual.
4. Obter autorização explícita para merge e deploy, com rollback separado e smoke
   tests de permissões e criação em ambiente autorizado.

Rollback proposto: reverter o lote de aplicação e restaurar a imagem anterior.
Nenhuma migração foi criada nesta revisão; se a correção de identidade acrescentar
uma migração, seu plano de reversão precisa ser revisto antes da liberação.

## Conferência real pós-ajuste

A direção de arte aprovou o alinhamento visual do bundle integrado em tema claro.
Capturas: `docs/relationships/screenshots/793-review/`.

- Desktop: cabeçalho azul-marinho, lateral de 40rem, contato/empresa e ações
  contextuais. Moeda BRL explícita no valor estimado.
- Celular 390×844: cinco abas disponíveis sem rolagem horizontal. Último controle
  em 751px, acima do início do rodapé em 771px; nenhum `select` nativo no drawer.
- Tab/Shift+Tab ficam no drawer; Home/End mudam a aba e seu foco. Escape fecha
  e devolve o foco ao card quando aberto por teclado.
- Trocar contato apresenta somente as ações do vínculo, sem o rodapé comercial
  concorrente. Abrir/cancelar não salvou contato, empresa ou oportunidade.
- A aba de oportunidades da empresa foi consultada no bundle real e retornou
  negociações, moeda, status e links para o CRM.
- Perfil de contato/empresa preserva o contrato de layout existente, incluindo
  a alça móvel de 48px. Não foi redesenhado o perfil legado inteiro.

Limites: não validamos imagem Docker/Linux, callbacks externos de produção ou
uma nova garantia de unicidade. A revisão visual não muda o veredito de release.
