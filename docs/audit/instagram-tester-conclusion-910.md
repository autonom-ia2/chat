# Instagram Tester — conclusão #910 / PR #913

## Estado da conclusão

Esta rodada implementa as correções de segurança e o mecanismo de gestão de sessão/proxy solicitados após a avaliação independente. Não instala serviços nem configura autenticação, segredos, Webshare, Redis ou produção. O PR permanece rascunho; a main dispara deploy automático nas duas stacks.

### Critérios adicionais

| Critério | Entrega em código | Limite operacional |
| --- | --- | --- |
| A36 — Sessão administrativa gerenciada | Payload cifrado, identidade fixa, App/Business/proxy vinculados, snapshot imutável, CAS e atualização sem redeploy; gestor observa somente uma consulta legítima do navegador dedicado | Runtime supervisionado, perfil dedicado e atualização real ainda não homologados; login/2FA exige operador |
| A37 — Proxy Static Residential | Direct IPv4 fixo, modo obrigatório de autorização por IP, mesmo endpoint no backend/gestor; nenhuma senha é enviada no CONNECT | Autorizar IPs de saída e conferir plano/endpoints no fornecedor exige aprovação; sem teste Webshare real |
| A38 — Falha segura | Sem saída direta ou retry automático; 407 controlado e timeout de convite permanece indeterminado | Auto-Replace/Auto-Refresh e monitoramento precisam de validação operacional |
| A39 — Não regressão e concorrência | Testes locais de expiração/revogação/CAS, desafio do navegador, proxy loopback, convite e OAuth/reautorização/#898 | Não equivale a jornada Meta/OAuth/webhook/DM nas duas stacks |
| Coordenação entre stacks | Conexão Redis TLS explícita para locks/resultados por App+perfil; cookies/OAuth ficam locais | Mesmo endpoint acessível e TLS/auth reais ainda não comprovados; IaC define caches distintos |

### Revisão independente e decisões

A revisão independente final de segurança não encontrou novo P1/P2 acionável no fluxo tester atual. Identificou bloqueadores corrigidos nesta rodada: credencial Basic enviada ao proxy por HTTP e métodos de escrita permitidos pelo gestor. Outra revisão adversarial identificou ausência de binding da instalação nos tokens tester, um P1 condicional se o OAuth App fosse compartilhado. Seleção e JWT novo agora incluem o namespace, validado antes do nonce; namespaces devem diferir entre stacks. O formato do JWT legado é preservado. Há um risco herdado condicional: se as duas stacks compartilham também o OAuth App/secret e IDs de conta coincidem, states legados sem audiência não provam origem. Confirmar Apps OAuth/segredos distintos por evidência sanitizada, ou resolver o binding legado em uma mudança própria antes da ativação conjunta; não declarar isolamento completo apenas pelo conserto do tester.

O contrato operacional agora rejeita Basic e credenciais de proxy; o gestor permite apenas GET/HEAD e a consulta GraphQL exata configurada, rejeitando os demais métodos. O scanner Gitleaks do diff staged passou com saída redigida. A documentação oficial confirma [Direct com IP Authorization sem credenciais](https://apidocs.webshare.io/proxy-connection). Nada foi alterado no console do fornecedor.

O contrato depende do `doc_id` e do formato observado do painel Meta: testes de fixtures não garantem que o painel ao vivo conserva esse contrato.

O backend invalida somente a versão rejeitada em HTTP 401/403, por decisão conservadora. Um 403 não comprova expiração: pode representar permissão ou bloqueio. HTML/esquema desconhecido falha fechado e não vira ausência de tester; o gestor para ao observar login/desafio. Não há recuperação automática com senha nem promessa de sessão permanente.

O publisher é um comando privilegiado no runtime Rails aprovado. Usa stdin, sem shell nem payload em argumentos; o operador deve fixar o comando e seu ambiente. As verificações de caminho/dono/permissões não provam que um perfil é dedicado: isso é gate obrigatório, sem reutilização do Chrome pessoal. Supervisão, lock após crash e alertas reais são responsabilidades operacionais descritas no runbook, ainda não instaladas ou demonstradas.

A revisão UI não encontrou regressão acionável: reautorização legada sem diff, erros amigáveis sem resposta upstream, foco/teclado preservados e username canônico. A galeria tem 60 imagens atuais com hashes verificados, 56 casos do wizard (52 com flag ligada e quatro com flag desligada), 11 fontes iguais antes/depois/checkout. Componentes e CSS são reais; APIs internas são sintéticas. Sidebar global, console Meta e OAuth externo não foram capturados. As quatro imagens anteriores ficaram arquivadas fora do índice.

### Veredito de publicação

**Não autorizar merge/deploy ou ativação nesta rodada.** Código validado localmente não prova infraestrutura ou integração real. Antes da publicação, concluir em ambiente aprovado: autorização por IP no fornecedor, endpoint Redis TLS comum, perfil/runtime dedicado, supervisor e alerta; então jornada controlada por stack com sessão renovada, convite/aceite, OAuth, reautorização #898, webhook e DM. Validar SHA e rollback das duas stacks e obter aprovação explícita de Rodrigo.

Não repetir a chamada Meta anteriormente bloqueada por outro proxy/host/ferramenta/agente. Esse bloqueio não prova falha técnica do produto. Nenhum cookie, senha ou HAR foi lido. Os testes locais usam dados sintéticos; a conferência real se limitou à UI da conta 18 indicada por Rodrigo, sem abrir conversas ou registrar dados das caixas existentes. O refresh OAuth preservado não renova cookies administrativos.

[Galeria atual](../assets/instagram-testers-910/index.html) · [Checklist da jornada](../instagram-tester-jornada-910.md) · [Runbook de operação/rollback](../runbooks/instagram-tester-onboarding.md).

## Testes finais locais

Snapshot verificado somente no M4:
`/Users/Shared/maccluster-workspaces/chat2you/20261003-182151-e685cb00-5c61b24643-ee41bdd8/src`.
SHA de conteúdo: `5c61b24643b6da51207e9a4d0b1fd2aa2a00e7f730fcbd0202a11d92ac65ef77`.
HEAD de origem `e685cb00189269aafe0d50d9f220abf0e4c0330a` com as alterações desta rodada; o SHA de conteúdo identifica o código testado, não o HEAD antigo sozinho. Snapshot local, sem sobrescrever checkouts ou forçar nó inelegível.

| Verificação | Resultado atual |
| --- | --- |
| RSpec Instagram, callbacks, autorização, reautorização, webhook/DM simulados, coordenação, proxy e sessão | **316 exemplos, 0 falhas, 0 pendentes** |
| RuboCop estrito do mesmo escopo Ruby do CI | **37 arquivos, 0 infrações** |
| Vitest focal de onboarding, cliente, abort e reautorização | **48/48 passou** |
| Node: fixtures, helpers, observer e manager | **32/32 passou** |
| Preparador Python offline | **25/25 passou** |
| Browser QA focal dos componentes | **33/33 passou, 67 capturas de execução** |
| Wizard/reauthorização real com APIs sintéticas | **56/56 passou, 60 imagens na galeria atual** |
| Integridade da galeria | **60 imagens e 11 fontes conferidas por SHA-256** |

RSpec job `m4-06236156ce4f4e88930e204a890a1cb5`: 30,68 s de exemplos após 7,91 s de carregamento. RuboCop job `m4-dd0e309f8ae743e7916476d31fcfd528`. Usados ambiente `env -i`, Ruby 3.4.4/bundle privado congelado, Rails/Rack/Node test, PostgreSQL de teste em 127.0.0.1:55432 e Redis de teste em 127.0.0.1:56379. Nenhuma ENV de produção herdada. Serviços isolados parados ao final.

O bundle privado é o já existente em `/Users/Shared/maccluster-workspaces/chat2you/20261003-165733-e685cb00-0d92e65ec9-36187b4a/bundle`. O wrapper compartilhado do piloto fixa Rails 7.1, enquanto este lock usa 7.2; por isso foi usado o runtime privado isolado, sem alterar o wrapper, runtimes ou infraestrutura.

As falhas anteriores foram reproduzidas, não omitidas. Foram corrigidos keywords do HTTParty, duração inválida de teste, fixture gerenciada e preparação de refresh: `Channel::Instagram#access_token` pode refrescar durante validação de `update!`. A spec agora prepara os atributos sem disparar esse getter, cadastra uma única resposta HTTP por cenário e verifica o token persistido diretamente. Os dois erros de refresh exigem uma única chamada HTTP simulada e log estático. O código de produção não foi alterado para mascarar essas falhas. Permanecem avisos de depreciação herdados de Rails/Rack, sem falhas nesta bateria.

O workflow dedicado tem quatro jobs obrigatórios: preparador Python, contratos Node/ESLint, Vitest e browser/RuboCop/sintaxe. Não usa `continue-on-error`; upload de evidência sem arquivos falha. Os checks gerais históricos de RuboCop e segurança são informativos e não substituem esse gate focal. Os 18 checks aprovados em e685cb0018 não cobrem estas correções; conferir o CI do commit novo antes de review de publicação.

## Alvo real autorizado

Rodrigo indicou **@placementseg, conta 18 do chat.hub2you.ai** para o teste real. A aba já aberta dessa conta foi conferida pelo produto: o wizard publicado ainda mostra apenas **Continuar com o Instagram**, sem busca/seleção/convite do tester. Isso é uma observação da UI atual, não prova da versão/flag do backend. Não houve convite, autorização, criação de caixa ou envio de DM nessa conferência. A homologação do código novo permanece pendente de publicação aprovada e configuração operacional. Não contornar a chamada Meta anteriormente bloqueada. Não foi lido cookie, senha ou HAR.
