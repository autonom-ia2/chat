# B1 — causas da validação executável

Issue #1120. Implementação local na worktree indicada pelo Rodrigo. Não houve revisão independente de código, commit, push, merge, fila ou deploy. Este registro precede a correção das falhas abaixo; não declara o B1 aprovado.

## Evidência

Snapshot `20261007-124906-532a5b7b-e562ece0a6-bfab7635`, SHA-256 `e562ece0a629ee55ad504f2222bf837c49397f28219b6376295f9d4b17b6b2f9`, verificado nos dois nós. RSpec real no M2, ticket `m4-59c6b94dbd5c43b5a9452ec3b1ee7c7d`, job `m2-396f4dfb197b4e2abf9cafabf9d6b3dd`:162 exemplos,20 falhas,0 pendentes,0 erros fora de exemplos,25,928s. Relatório local `/tmp/chat2you-agentes-b1-full-m2.json`, SHA-256 `e16c4bf3e30bd0493ef00cb0442130c8811fa1499ae720f57c816dd2d7b2f666`.

Os27 casos de configuração pública passaram. Também passaram permissões, reaper, janela de600s, códigos, canais, Waha e throttles. As20 falhas estão concentradas na operação SuperAdmin(19) e filtro da auditoria(1). Não extrapolar esse verde parcial para o B1 inteiro.

Vitest real no M4:36 testes em2 arquivos passaram, ticket `m4-1927023728ae4ef999144105302403fc`, job `m4-b346f9e426544a299b4bd07dd781027e`. O aviso do Browserslist é preexistente; nenhuma atualização de dependência foi feita.

## B1-COD-01 — origem do corpo antes do wrapper

As requisições operacionais válidas retornam422 com `config_key_not_allowed`, key `account`. O guard lê `request.request_parameters` depois de `ActionController::ParamsWrapper`. `config/initializers/wrap_parameters.rb` habilita o wrapper JSON global: o campo automático não é um irmão enviado pelo cliente. A validação não rastreou a transformação do framework antes de classificar o corpo como inválido.

Correção deve ficar restrita à nova action e distinguir corpo original de parâmetros derivados, preservando o contrato que rejeita irmãos realmente enviados. Não ignorar simplesmente `account`, nem desligar o wrapper global e alterar outros caminhos. Acrescentar casos de corpo válido e irmão `account` explícito, além dos arrays/null já previstos. Confirmar por request real.

## B1-COD-02 — autenticação inferida sem execução

O caso JSON de usuário comum retornou401; o desenho/spec esperava redirect302. A rota ainda não existia no baseline, portanto um404 anterior não provava o comportamento da autenticação dessa action. Preservar o mecanismo existente e corrigir a expectativa/documentação com evidência para HTML e JSON, sem mudar autenticação para satisfazer o teste.

## B1-COD-03 — sessão de teste após resposta404

No mesmo exemplo, o agente de sistema recebe404 e a tentativa seguinte para Lia recebe401. O helper de integração `sign_in` usa `Warden.on_next_request`; a primeira resposta404 não estabelece a sessão usada pela segunda chamada. Os dois alvos devem ter casos independentes, cada um com sua própria autenticação. Não alterar a autenticação da aplicação para acomodar o estado da fixture. A próxima execução deve provar as recusas404 e422 separadamente.

## B1-COD-04 — tipo de filtro e transporte da fixture

O GET da auditoria retornou lista vazia em vez da linha esperada. O parser usa `Integer(value, 10)`, que recusa argumento já inteiro. A fixture usa GET `as: :json`: o helper de integração transforma a chamada em POST com `X-Http-Method-Override: GET`, enviando JSON e `agent_id` inteiro. O cliente Axios oficial envia query string, recebida como String. Corrigir a fixture para GET com query e `Accept: application/json`; não ampliar o contrato para um transporte que o cliente oficial não usa. Provar filtros válidos, inválidos e isolamento por esse caminho.

## Método para a próxima passagem

Rastrear cliente → corpo/query original → transformação Rails → contrato → permit → lock → escrita/leitor → audit persistido → query/serializer. Lint e sintaxe não substituem execução desse caminho. Resolver as causas em um bloco, ler o diff e executar os casos correspondentes antes da revisão independente. A revisão segue o limite do Rodrigo: achado na checagem exige causa antes da correção; erro na revisão final exige parada e retorno.

## Resultado do bloco corretivo — ainda não aprovado

Snapshot `20261007-130717-532a5b7b-1026ab361d-c0f6fdb0`, SHA-256 `1026ab361de83cab984bf0102001482eb253cdfa095368d5d3378d6bf3ccb291`, duas réplicas verificadas. Ticket `m4-edc5e96544294e2f931560cc2a30ccc5`, job `m2-4fa67fb92914452da180d21574771306`: 178 exemplos, 1 falha, zero pendentes e zero erros fora dos exemplos, 29,868s. Relatório `/tmp/chat2you-agentes-b1-corrected-m2.json`, SHA-256 `ff4f386195c4f8f76efe825fdc56811482c2b729ea46369133f37ef818209c1c`.

Os 177 casos passaram, incluindo as 12 chaves por operação (set/replace/clear), as recusas da API pública para SuperAdmin membro da conta, autenticação HTML/JSON e filtros reais por query. Falhou somente a fixture de rollback da auditoria: esperava exceção `ActiveRecord::StatementInvalid`, mas nenhuma foi propagada ao teste. Diagnosticar stub, caminho de escrita e tratamento HTTP do framework; a ausência de exceção sozinha não prova nem descarta rollback. Não alterar expectativa sem conferir persistência e resposta.

### B1-COD-05 — exceção de persistência convertida em HTTP500

Diagnóstico antes da correção: `config/environments/test.rb:32` habilita `config.action_dispatch.show_exceptions = true`. `DebugExceptions`/`ShowExceptions` convertem a exceção SQL em HTTP500; o request não a relança para `raise_error`. `Audited.audit_class` é a mesma classe configurada no initializer e usada pelo serviço; `with_lock` mantém update e auditoria na mesma transação. A validação anterior leu o tratamento no controller, mas não completou o caminho pelo middleware de teste.

Correção autorizada somente na fixture: observar HTTP500, confirmar que `create!` foi chamado uma vez, reler o config e contar as auditorias para provar que ambos permaneceram intactos. Não alterar o tratamento global de exceções nem substituir a garantia transacional por sucesso silencioso. A prova executável desses quatro resultados ainda está pendente.

### B1-COD-06 — filtro recebe pessoas e a linha não mostra a mudança

Passe do principal controle → leitor → efeito, antes de revisão independente de código:

- `auditlogs/Index.vue:46,183` passa `agents/getAgents` ao filtro de agente de IA. Esse é o catálogo de pessoas. O catálogo de IA é `autonomiaAgents/getRecords`. IDs e nomes de pessoas não são IDs e nomes de `Autonomia::Agents::Agent`.
- `generateTranslationPayload` só trata `operation_key` singular. O escritor aceita várias chaves na mesma transação e o serializer devolve `operation_keys`, com singular nulo nesse caso; o texto exige `{operationKey}` sem preencher esse cenário.
- A tabela exibe somente a frase da atividade, data e localização. Os valores antigos/novos sanitizados do BE-31 não são apresentados, apesar do requisito de registro legível da mudança.

Causa: os testes de helper/filtro recebem arrays de agentes artificiais e verificam a forma parcial da frase, sem montar a página com os dois catálogos distintos nem conferir os valores da mudança. A validação do caminho terminou no JSON e não chegou à página. Correção restrita ao Registro: manter o catálogo humano para atores existentes, usar o catálogo de IA para o filtro, apresentar uma ou várias chaves e seus valores já sanitizados, sem despejar JSON bruto. Provar a página com IDs distintos de pessoa/IA e uma alteração de várias chaves. Não alterar o contrato de auditoria nem os outros tipos de registro.

## Bateria ampliada — diagnóstico antes das correções finais de validação

Snapshot `20261007-130717-532a5b7b-1026ab361d-c0f6fdb0`, ticket `m4-32b65b17d3d9444481f1cde2067d6ac2`, job `m2-c4af066527c34946875ac5c4de8fb47b`: 412 arquivos, 4.804 exemplos, 5 falhas, 74 pendentes, zero erros fora dos exemplos, 509,905s. Relatório `/tmp/chat2you-agentes-b1-broad-m2.json`, SHA-256 `b8cc9ad8222f7d68ee077788830bda4b07ce736d70a53bef6cb7bd1c943907ad`. Não é aprovação: pendências e falhas precisam permanecer explícitas.

### B1-COD-07 — fixtures antigas contradizem o contrato fechado aprovado

`external_agent_lifecycle_spec.rb:174,197` ainda espera sucesso ao enviar `with_knowledge`, `topic_map`, `temperature` ou `agente_de_cotacao` ao PATCH genérico. O PRD §10.1 BE-19 determina atualizar exatamente esses dois exemplos para recusa 422; a lista pública de oito chaves não contém esses campos. O diff não quebrou um cliente oficial que grava esses campos: o traçado anterior dos painéis mostrou payloads fechados com as chaves públicas. A spec antiga ficou fora da seleção inicial de contratos.

Correção restrita à fixture: afirmar 422, `config_key_not_allowed`, a chave protegida e nenhuma alteração persistida; retirar `temperature` dos payloads para não misturar recusas. Acrescentar caso permitido de `response_window` que preserve as chaves calculadas. Não afrouxar o contrato para tornar a spec antiga verde.

### B1-COD-08 — disputa de token usa o limite antigo do processamento

`builder_spec.rb:48` usa `travel_to(10.minutes.from_now)` para reassumir a geração. BE-15 mudou `STALE_PROCESSING_AFTER` de cinco para dez minutos, derivados do orçamento real de timeout/retries; o predicado usa `updated_at < limite.ago`. Exatamente no novo limite, o token anterior ainda é válido. É uma fixture incompatível com a mudança da branch, não uma falha preexistente comprovada.

Correção restrita à fixture: viajar `STALE_PROCESSING_AFTER + 1.second`, como o caso correspondente de `build_thread_spec.rb`. Preservar a semântica do predicado e comprovar que a geração substituída não persiste a resposta.

### B1-COD-09 — mapa gerado do Guia ficou fora de dia

`formatos_spec.rb:12` detectou origem/linhas e parâmetros dos controllers alterados diferentes dos JSON versionados. A mudança de strong params exige regeneração, prevista no AGENTS.md. A validação JS do mapa de rotas não cobre o mapa de formatos Rails. Executar o gerador oficial `autonomia:guia:formatos` em ambiente test com credenciais herdadas removidas e serviços descartáveis locais, conferir o diff gerado e executar `formatos:check` e o spec. Não editar JSON à mão.

A quinta falha é B1-COD-05, já diagnosticada e corrigida na worktree depois deste snapshot; ainda requer execução da fixture corrigida. Nenhuma destas passagens constitui a revisão independente normal do código B1.

## Consolidação de lint, frontend e geração — sem aprovação final

O lint de todos os 35 arquivos Ruby/Jbuilder, no snapshot `20261007-133024-532a5b7b-3a9e99ccaf-398a57d6`, encontrou 27 pontos (ticket `m4-fa1d9f45576345258fcabf73ab8d9caa`, job `m2-70a2563893f0433795f0589a03dacc31`). Causa da cobertura parcial anterior: cada owner validou somente sua seleção inicial, sem consolidar o diff final. Corrigidos localmente complexidade de scopes/rotas, precedência, alinhamento e constantes vazando do grupo RSpec. O lint seguinte no snapshot `20261007-134028-532a5b7b-def287b3f1-0a3a761a` deixou cinco pontos de alinhamento/nome (ticket `m4-a08daf9d439140b9bc5d609fa21eab4f`, job `m2-0a92ab60e3e948e2931d537903bf22ea`), corrigidos sem alterar número de linhas ou contrato. Prova final de zero pontos ainda pendente. Não desabilitados cops.

Vitest real no snapshot de frontend acima: três arquivos/41 testes aprovados, incluindo montagem de Index com pessoas ID7/IA ID42, mudança plural e produto desligado. Ticket `m4-00f7c4f79c2c4218bfc49fd9deeab50c`, job `m2-83f1b8856b3043ce8efe9d5e4891db52`. ESLint nesse snapshot deixou somente uma quebra de linha no novo Index.spec, já corrigida na worktree; job `m2-a8dc32e927e5422dab3ea5d792738881`.

Build real `bundle exec vite build --mode test` no mesmo snapshot/M2: código zero, 6.833 módulos transformados, 54,77s de build (ticket `m4-fd87b2b2e5164434a6f6b8346e268438`, job `m2-12a97d89369f45ee991b201642cf5b4a`). Avisos observados: enums keyword depreciados, caniuse-lite, import dinâmico/estático de FirstSteps e chunks maiores que 500kB. Não alteradas dependências para ocultar avisos. A única mudança frontend após esse build é formatação da spec, não do produto. Não há aceite visual de tela real neste resultado.

O gerador oficial `autonomia:guia:formatos` executou no M4 em test com env-i/serviços locais (ticket `m4-729ec2851b904c109396bde1746884dc`, job `m4-73a45227760d470cb38d3122c6888a64`), 534 ações. Após refatorar o controller, o scheduler recusou M4 por thermal Heavy. Para preservar o snapshot imutável, executado `Autonomia::Guide::Formatos.gerados` no snapshot final de código/M2, gravando somente em `/tmp/chat2you-agentes-b1-formatos-final` (ticket `m4-e421ea98684c4b37b9a3643b7f50554e`, job `m2-fb3f66c44a384a1c84a04b12d12fc0a4`). Os três arquivos foram copiados para a worktree a partir desses bytes; somente o JSON das ações mudou novamente. Nenhum JSON foi editado à mão. `formatos:check` e spec final ainda pendentes.

Uma tentativa de snapshot foi recusada por mudança da fonte durante leitura inicial: dois relatórios/desenhos de owners terminaram na mesma janela. Cópia oficial seguinte capturou conteúdo estável e verificou as duas réplicas, hash `def287b3f1720dc13a772f62b04e7cf4c130349707465a17c7c857117cb1a4d0`. Não se forçou captura nem se editou cópia imutável.

## Snapshot final de validação local

Snapshot `20261007-135029-532a5b7b-0640a6976a-cc8c6a24`, conteúdo SHA-256 `0640a6976a3dc706c804284fa225dc28ab4d454fc14e9a2ee0ea9b2e6f55bb80`: 14.693 arquivos, 342.607.828 bytes e duas réplicas verificadas, capturado com os owners sem escrever. O código do produto continua sem commit/push.

- Ruby/Jbuilder: 35 arquivos, zero pontos de lint. Ticket `m4-7949cb533d0041d3ae892c07ce7a58e1`, job `m2-673689490a03414da7615a3955792638`, código zero.
- Dependências Node preparadas por cache offline no M4, sem downloads nem mudança de lockfile: ticket `m4-1832f1a3ff4040c9b6160f834b09daf5`, job `m4-2f44f834e0874363a17cc8ed6fedadaf`, código zero. O prepare do Husky informa ausência de `.git` no snapshot; não foi contornado hook na worktree.
- ESLint dos seis arquivos JS/Vue alterados e check do catálogo fork: código zero; 13 catálogos e 19.954 mensagens compiladas, cobertura en/pt_BR. Ticket `m4-45b5261493b34551bda637c757fcd6f8`, job `m4-59c7103fe2cd4d26a93c697e3f6ed871`.
- Suíte ampla final de 413 arquivos iniciada pelo wrapper oficial no snapshot/M4: ticket `m4-079e64ceba364ffbaa00fe4a4a5619fe`, job `m4-3d107acf29d44963950fb9ecfe2e1bb7`, relatório `/tmp/chat2you-agentes-b1-final-m4.json`. Resultado ainda pendente neste registro.

O scheduler recusou preparação Node no M2 por telemetria térmica desconhecida; o M4 estava Nominal e elegível na consulta seguinte. Não se forçou nó excluído nem se alterou política térmica. Não há aprovação de tela, revisão independente de código, merge, fila, deploy ou produção derivada destes checks.

Encerrada a prévia local antiga do snapshot RED1, job próprio `m2-30bfd439114242cebb6928cf76175665`, pelo cancelamento oficial após conferir comando e ownership. O wrapper possui cleanup com validação de identidade/PID. Após o cancelamento, `lsof` não encontra listeners nas portas próprias 59720–59723; PostgreSQL/Redis de teste em 55432/56379 permanecem ativos. Nenhuma porta de produção ou serviço de outro owner foi encerrado. A prévia antiga não serve como evidência do código atual.

Iniciada a única revisão independente normal de código B1 em duas lentes cruzadas, sem revisar os arquivos escritos pelo próprio reviewer. Fingerprint de 47 arquivos de código/specs/contratos gerados: `7aaa8c39a9a8a0980fed0c838f9492964664e1192b8ce546efd8d1962c71e119`; inventário local `/tmp/chat2you-agentes-b1-review-files.json`. A bateria ampla final ainda está em execução. O produto permanece sem aceite no navegador.

### Resultado da bateria antes das correções da revisão normal

Job `m4-3d107acf29d44963950fb9ecfe2e1bb7`: código zero, 4.805 exemplos, zero falhas, 74 pendentes, zero erros fora dos exemplos, 444,592s. Os pendentes são 71 avaliações pagas desativadas e três exemplos rotulados como quarentena de provisionamento no próprio harness; esses rótulos não são uma comparação independente com main. Não tratados como aprovados.

O `autonomia:guia:formatos:check` também passou no mesmo snapshot/M2: `[guia:formatos] em dia`, ticket `m4-501d40492d7f459c943874c1ce278105`, job `m2-0862f928fb1b411ea443df81705c421e`, código zero. Houve apenas avisos dos enums existentes. Verificação posterior do snapshot confirmou as duas réplicas com o mesmo hash, apesar da preparação Node e outputs ignorados.

A revisão normal acrescentou três lacunas que essa bateria ainda não cobria: `handoff_target_type` ausente no GET apesar de aceito na escrita; resposta operacional oferecendo `native_tool_slugs` à Lia; PATCH público fazendo read-modify-write do config sem participar do lock da porta operacional. O último permite perder uma alteração já auditada. As causas e provas estão em `revisoes/B1-codigo-contratos-auditoria.md`; corrigir os dois leitores e o trecho comum de merge/save, com caso de instância lida antes da alteração operacional e releitura dentro do lock. O achado do filtro ativo sem catálogo está em `revisoes/B1-codigo-frontend-produto.md`. Nenhuma dessas correções é considerada aplicada/aprovada neste registro.

## Bloco consolidado da revisão normal — diagnóstico antes da implementação

As três lentes encerraram a revisão normal: três achados de contrato/auditoria, três de runtime/permissões e um de frontend. A correção permanece um bloco, seguido da checagem limitada prevista pelo Rodrigo. Novos casos de regressão estão sendo escritos primeiro; nenhum resultado RED é presumido.

- **Leitores:** o allowlist de escrita não foi comparado ao slice GET (`handoff_target_type`) e à exceção da Lia na saída operacional (`native_tool_slugs`). Corrigir somente esses slices, com round-trip e preservação do valor mantido pelo deploy.
- **Merge de config:** o lock foi tratado como garantia do serviço novo, sem verificar o outro escritor do mesmo blob. O PATCH público precisa reler/mesclar/salvar sob o mesmo lock do agente. O teste intercala a leitura pública com uma operação já auditada e afirma que ambas sobrevivem.
- **Limpeza concorrente:** o reaper e o append de usuário não compartilham domínio de lock. Fixar Agent antes de Thread para os caminhos reais; append de usuário não pode confirmar uma mensagem em agente que ganhou arquivamento antes. Thread ainda sem agente mantém o caminho existente. O rastreio adicional encontrou inversão concreta: `Agent#apply_builder_config!` trava Thread e então chama `apply_builder_attributes!`, que trava Agent. Essa ordem precisa ser alinhada no mesmo bloco para não introduzir deadlock com o novo append. Preservar token/supersede e histórico, sem guards especulativos em outros jobs.
- **Erros:** enum inválido, métrica desconhecida e recusas de FAQ ficaram fora da migração dos chamadores. Códigos escolhidos para fechar esses caminhos: `invalid_enum`, `unknown_metric`, `not_pending`, `embedding_failed`, `faq_invalid`, com en/pt_BR e locale da conta. Preservar `error` e a restrição existente que só captura ArgumentError de enum; não ecoar o valor ou a frase bruta do model.
- **Prazo:** o parser/default era privado do reaper. Centralizar a mesma regra existente em `Config.draft_reap_hours` e expor `draft_retention_hours` no payload do agente. O `state.retention_hours` planejado pelo B2 deve usar essa mesma função; não copiar parser nem inventar prazo no frontend.
- **Filtro:** a existência do nome foi usada como estado de seleção. O ID ativo governa o filtro; ausência no catálogo recebe rótulo localizado por ID, sem novo endpoint ou permissão.

Os testes escritos pelo root primeiro cobrem leitor de handoff, saída da Lia e instância pública defasada por operação auditada. Os owners preparam os casos restantes sem executar em banco/produção ou editar produto antes da prova RED consolidada.

### Preparação e execução do RED da revisão normal

Antes da execução, a inspeção do novo teste concorrente identificou um defeito de fixture: exigia `BuildThread#with_lock` sem necessidade do contrato e chamava `begin_build!` enquanto outro worker segurava a thread, podendo bloquear antes do release. Corrigido somente o teste: token obtido antes dos workers; coordenação no lock real de Agent, antes do UPDATE atômico de Thread. Duas conexões, filas e timeout; sem sleeps ou banco de produção. Nenhuma correção do produto aplicada nessa preparação.

Snapshot `20261007-141657-532a5b7b-e5183f0e6b-0a77f58d`, SHA-256 `e5183f0e6b7cea0b854e914bccfc9ef4d8252eb87d7f3dea684527647ea8b7df`: 14.702 arquivos, 342.721.124 bytes, duas réplicas verificadas. Owners pausados durante captura. Oito arquivos RSpec do RED em execução no M2 pelo wrapper de teste oficial, ticket `m4-bc3a4d6533104e378dd5ff7aed0a51db`, job `m2-b09c5d6718c34ffa823e98ea5c872820`; relatório `/tmp/chat2you-agentes-b1-review-red.json`, resultado pendente. Instalação Node offline/cache no M4 concluída, ticket `m4-3bdebc70d4904f518ac8044861a3e647`, job `m4-832b7d6b6ad44c9788b8e00c2c4fa8c5`, código zero, sem mudança do lockfile.

O JSON da bateria anterior de 4.805 exemplos tem SHA-256 `d7fbca7a4eea92e929c2144822d7d43b9b710436dc0b1ff5b56e9d82cfd0e102`. Esse resultado precede os sete achados da revisão e não aprova suas correções.

RED concluído: 127 exemplos Ruby, 16 falhas, zero pendentes e zero erros fora dos exemplos, 39,537s. Faltam handoff_target_type e retenção (quatro casos), oito traduções dos erros estáveis, dois checkpoints de lock do append (Timeout esperado por ausência do lock), uma preservação de alteração operacional auditada e uma exclusão do native_tool_slugs da resposta Lia. Os casos de erro param na ausência da tradução esperada; o fechamento deve comprovar também o código e a mensagem HTTP após a correção. Não há falha de boot/harness nesta execução.

RED frontend: 14 testes, 13 aprovados e uma falha esperada, rótulo Todos os agentes no lugar do ID ativo sem catálogo. Ticket `m4-7c43741971144c29b4beac920ffa8b7b`, job `m4-d3595872947d415f86a9fd423714079f`, código 1. Nenhum código de produto foi corrigido antes destas provas.

Relatório Ruby RED SHA-256 `9a8fc33c2644a7b5264365c9a981f1db02ccfb431375ecfc94f6c6a79e6b7b36`; snapshot verificado novamente com as duas réplicas consistentes após os jobs. Antes de iniciar o bloco corretivo B1, a revisão técnica final do desenho F0 deixou F0-FINAL-01. Execução parada e retorno ao Rodrigo conforme o limite autorizado. Não houve correção de produto B1 após o RED, nem nova checagem ou aprovação de código.

## Retomada após decisão de produto — bloco corretivo B1

Rodrigo retirou a conexão interna WhatsApp de Agentes e confirmou continuar com aceite de telas reais uma a uma antes de subir. A decisão que originava F0-FINAL-01 foi substituída; parecer histórico preservado, sem PASS retroativo. Owners retomaram somente as sete correções já diagnosticadas/provadas no RED.

Snapshot `20261007-154913-532a5b7b-2f4fd4b0ca-db8ab4a3`, SHA-256 `2f4fd4b0ca28d77c94c459346cc80b5dd3071dd42c58b3e056bd23a82e1a18dc`, duas réplicas verificadas, 14.705 arquivos/342.741.526 bytes. Correções: leitura de handoff; saída Lia sem native_tool_slugs, mantendo armazenamento; PATCH público com leitura/merge/save dentro de Agent.with_lock; user append e reaper no mesmo Agent.lock, Builder também Agent→Thread; erros estáveis en/pt_BR; prazo único exposto; ID ativo do filtro preservado sem catálogo.

Validação focada: 11 arquivos/180 exemplos Ruby/zero falhas/zero pendentes/zero erros fora dos exemplos, 31,110s, ticket `m4-5c0ea14e28a043429b0dc4c4f8d543c0`, job `m2-dbd4cb51f8864dd0adf64c4107f533d3`. Relatório `/tmp/chat2you-agentes-b1-review-green.json`, SHA-256 `0f1e7035a0b990d2d82b1de741ab433f50c64f8254046112b61a8f8036e69a14`. Inclui os casos novos e Agent/BuildThread/Builder. Os envelopes agora comprovam código e tradução HTTP, não apenas ausência da chave de catálogo.

Frontend: três arquivos/43 testes aprovados, com TZ=UTC, ticket `m4-96954ab0b9934cf494434e1c00c7a7e9`, job `m2-2bab6572f98d4c4b9108ff52d8249ac2`. Node preparado offline/cache no M2, sem downloads/lockfile alterado, ticket `m4-566475fb3a2d49f3814e675c35ca34ec`, job `m2-a01bc2dab1654e28837f4d0797d5d8ac`.

Lint consolidado de 41 arquivos encontrou 14 pontos: complexidade de Analytics/FAQ/Config; sintaxe de hashes; nome/indentação do novo spec concorrente; AnyInstance na fixture pública. Job `m2-9b2b3969c4314c0888316665711ebff7`, ticket `m4-fd41b02214c64dc18e0e1c7a4d86bde4`. Corrigidos sem desabilitar cops: parser de prazo e limites com responsabilidade própria, interfaces Config preservadas; helper de erro FAQ compartilhado; validação de métrica separada; fixture pública intercepta somente a instância real usada pelo request; spec concorrente renomeado para reap_stale_drafts_job_concurrency_spec.rb. O owner conferiu sete arquivos sem pontos; lint consolidado de 43 e teste da revisão final dessas refatorações ainda pendentes. ESLint seis arquivos deixou apenas duas quebras de linha, corrigidas manualmente; job `m2-7d04dc5edacc4d479caa28dbc296119c`, ticket `m4-303a97356325496e99fd00eb34aaccf3`.

Build, catálogos, geração oficial dos formatos, bateria ampla atualizada e checagem limitada das correções continuam pendentes. Nenhum resultado destas validações aprova tela real ou release. Nenhum push, merge, fila, deploy ou produção.

### Checagem limitada e resíduo de estilo — pausa antes de nova correção

As três lentes limitadas encerraram sem residual concreto nos sete achados da revisão normal. Relatórios: B1-codigo-checagem-contratos-auditoria.md, B1-codigo-checagem-runtime-permissoes.md e B1-codigo-checagem-frontend-produto.md. Isso não substitui execução atualizada, aceite de tela ou aprovação de release.

O lint consolidado do snapshot `20261007-160057-532a5b7b-e8a3a7247b-05379dc8`, job `m2-01c90922291d4ace87a2cfe2485bd028`, ticket `m4-89483c28b49f4f74bd53a4c94541c901`, terminou com código 1: 43 arquivos, seis pontos Style/HashSyntax no BuildThread, linhas 194, 196 e 212. As três chamadas ainda usam abreviações `image_signed_ids:` e `client_message_id:`, enquanto a configuração exige valores explícitos. A conferência parcial do owner não comprovava zero pontos no conteúdo consolidado. Causa registrada antes da correção: validação de uma seleção/conteúdo diferente foi tratada como fechamento de estilo, sem comparar o arquivo final ao resultado consolidado. Nenhuma alteração de comportamento é indicada pelo relatório. Pausa do avanço B1/B2/F1 até correção restrita dessas chamadas e verificação final; erro nessa verificação exige retorno ao Rodrigo, sem nova rodada.

Uma tentativa anterior de lint no M4 terminou com código 127 por ausência do executável RuboCop no runtime compartilhado, job `m4-084682a536a54d0fa32b4680614b57a8`. Não se instalou runtime nem se contornou a política do scheduler; o M2 executou o lint existente.

O gerador oficial de formatos rodou em test/M4, job `m4-eccb6980f2af44b88ee021c1ebca2a15`, código zero, gravando em diretório temporário; seus bytes foram copiados para a worktree. O JSON de ações tem SHA-256 `c675c6cf1ba8453958a9bf09b9d540d0e5d71d0f7dce65489e639a003a771d08`. Ainda falta snapshot com essa geração, bateria ampla e check de formatos atualizados. Não há aprovação runtime final.

### Fechamento local B1 — antes de B2

Rodrigo autorizou continuar após a explicação do próximo passo. Corrigidos apenas os seis argumentos abreviados nas três chamadas; revisão final independente `B1-codigo-final-estilo.md` passou, sem residual. Snapshot final `20261007-163238-532a5b7b-9baf372e0e-e72fb9e9`, SHA-256 `9baf372e0e18d8ab6adf0b2cef23146e0f605c35979f3f14e2bb02a3fa0f04f8`, duas réplicas verificadas novamente após execução.

- RuboCop consolidado: 43 arquivos, zero pontos, código zero; ticket `m4-e49f421d806b4a76a5b8f5e5028d134f`, job `m2-edfee8d853714a0cac562472c724e295`.
- Bateria ampla: 414 arquivos, 4.819 exemplos, zero falhas, 74 pendentes, zero erros fora dos exemplos, 431,506s; ticket `m4-913ced82b71c48e6a87b661e33a7f2ca`, job `m4-8ae7e1f97e97416db6eba7e55bb1b4ea`. Relatório `/tmp/chat2you-agentes-b1-review-final.json`, SHA-256 `c79df41bf59777abb99280226d5e0ff5eee7f6eef1a91d8e6143063320bb7312`. 4.745 exemplos executados e aprovados. Pendentes: 71 avaliações pagas desativadas e três exemplos rotulados como quarentena no harness; não afirmada comparação independente com main.
- Formatos oficiais: `autonomia:guia:formatos:check` em dia, código zero no snapshot final; ticket `m4-64e38c670d734f88881a1a387ceeecd2`, job `m2-44a5f547168648479688c8a3487319c1`.
- Frontend no snapshot 11, mesmo conteúdo JS/Vue do snapshot final: ESLint seis arquivos código zero, ticket `m4-7c8a4137265e466795dd1e0b2691485f`, job `m2-ecf8b3040dc34c96ac790de5008ff581`; Vitest três arquivos/43 testes com TZ=UTC, catálogos fork (13/19.954 mensagens) e Guia (193 fluxos/186 telas/nenhuma sem explicação), todos código zero, ticket `m4-58815609506545e2bc99d20d37ad87d8`, job `m2-d2bd424f77ec4367a3e50fdbfbe2a3a6`.
- Build do mesmo frontend: 6.833 módulos/52,77s/código zero, ticket `m4-69a5fc7e9e954709b6f6a375818f814d`, job `m2-c5fc10421fb841c48274dfeb46fd3fd3`. Saída completa lida; avisos de Browserslist, enums e chunks não tratados como falha nem ocultados alterando dependências.

As três checagens limitadas dos sete achados e a revisão final do resíduo de estilo encerraram sem achado residual. B1 tecnicamente fechado **localmente**, não aprovado como tela ou release: sem commit/push, CI novo, PR de implementação, visual real, merge, fila, deploy ou produção. O avanço autorizado é testes primeiro B2; primeira tela permanece pendente e será aceita pelo Rodrigo antes da seguinte.
