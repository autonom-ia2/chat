# B2 — testes primeiro para os dados da primeira tela real

Issue #1122, épica #1114, branch/worktree existentes. B1 fechado localmente conforme audit de causa raiz; PR documental #1115 congelado. Primeira tela real Seus agentes acompanhada pela issue #1130, item Project `PVTI_lAHOC3T16M4BX9UHzg_ObEc`; nenhum aceite visual feito.

## Divisão e contratos

- Root: gate BE00, payload/toggle da conta, projeção em lote BE01, index/serialização, integração sequencial em AgentsController/Agent/Config.
- r9_tecnica: serviços privados BE08 de estado/digest/resultado, integração assíncrona e testes; estado tipado sem consulta no resolver, apenas backend escreve metadados.
- registrar_decisoes: MaterialProjection BE27 e ListStats BE01; decisão de uso compartilhada com Retriever, sem mídia; fontes/versões pré-carregadas para lote sem N+1.
- r9_produto: canais BE11, identidade BE16 e disponibilidade BE32, com testes de isolamento e recusa antes de escrita parcial. BE28 e integração de arquivos compartilhados serão ligados pelo root.

Estado atual: teste primeiro executado e implementação inicial B2 em integração, ainda sem resultado GREEN nem revisão normal de código. Owners não executam banco/testes; root captura snapshots estáveis e usa wrapper oficial isolado. Nenhuma avaliação paga, segredo, conta de cliente, produção, merge, fila ou deploy. As telas F0/F1 ainda não existem.

## Conferência antes do RED

Antes da captura, root encontrou duas classes de defeitos de fixture: referência a serviço inexistente no topo do arquivo impediria carregar os exemplos; e o caso E1/E2 estava semeado com presença de instrução, contradizendo a precedência E3/legado. Causa: fixture não foi cruzada com o estado tipado e disponibilidade real da classe. Correção restrita aos testes: resolver a constante dentro do exemplo, sem stub de produto; E1/E2 sem instrução, legado com instrução deve ser E3; conclusão E4 exige sessão e ator completos. Constantes em blocos RSpec foram substituídas por let para evitar vazamento; busca SQL/prefixo usa métodos de string, sem regex. Isso é conferência de fixtures antes do RED, não nova revisão normal nem resultado executável presumido.

Interfaces: MaterialProjection recebe `agent`, `sources` e `entry_versions` opcionais; retorno com decisões/ids utilizados/rejeitados. Entry versions contém ready_count/latest_updated_at. ListStats recebe agents/now e retorna week/month por ID. AgentStateResolver recebe fatos tipados, teste, digests e prazo; AgentStateStore é único escritor. As integrações preservam account scope e chaves públicas/calculadas, não alteram instrução do runtime.

## RED executado, antes do produto

Snapshot `20261007-165304-532a5b7b-52bd2e6c7e-ac8f47f5`, SHA-256 `52bd2e6c7e8d7b8baff6b830bb3f08298a4f21463db1c205a15b870eda92cfb0`, 14.730 arquivos/342.864.234 bytes, duas réplicas verificadas na captura. Autores pausados; nenhum produto B2.

Comando: `maccluster work plan/run --kind test --cwd <snapshot>/src -- /Users/Shared/maccluster-test-services/bin/run-ruby-tests-node.sh rspec <18 arquivos B2 e integração> --format json --out /tmp/chat2you-agentes-b2-red.json`. Planner escolheu M2 nominal; ticket `m4-63254b3960eb49659d6de4b08cbbe802`, job `m2-e8aeaa5cf08d4f5db3e1f89bfdac7861`, exit 1. JSON SHA-256 `73d0fcb46663ef6932bfbd5faca4038d7afb4ffe03b052889aed3d189ccacc8e`: 114 exemplos, 105 falhas, zero pendentes, zero erros fora dos exemplos. Nove exemplos existentes passaram; 99 falhas são contratos/classe/API ainda ausentes. Seis falhas de BE28 são fixture inválida, não prova RED do DTO.

Causa das seis: a fixture tentou `AgentEvent.create!(conversation: objeto)` mas o modelo tem somente coluna conversation_id, sem belongs_to conversation. Corrigir somente para conversation_id antes da implementação BE28 e executar seus exemplos no snapshot seguinte. Não adicionar associação de produto para acomodar fixture. Nenhuma nova revisão normal foi iniciada; esta é validação do teste primeiro.

Interface de material consolidada pelo root: `MaterialProjection` DTO expõe decisões/ids/digest/state e `test_digest_input(with_knowledge_effective:)`; este método retorna hash plano com material_snapshot_digest/state/source_ids/source_fingerprints/knowledge_entry_updated_at/with_knowledge_effective. TestDigest recebe esse hash, retorna tested_digest/person_digest separados; sem segundo digest de entrada obrigatório. Motivo person prevalece quando ambos mudam; material isolado mantém person_digest. Store preserva a chave órfã sem underscore e escreve exclusivamente o namespace privado. Specs de integração usam caminho real controlador/Redis/job, com apenas Answerer determinístico, sem stub Store/Recorder.

### RED BE28 após corrigir a fixture

Snapshot `20261007-165703-532a5b7b-38a27ee1ba-e14d385e`, SHA-256 `38a27ee1ba6d85167e25af1058506c4c9b41daf9c26fd2b896a4c60717a03556`, 14.730 arquivos/342.866.326 bytes, duas réplicas verificadas na captura. Somente o arquivo Enterprise BE28 foi executado com o mesmo wrapper isolado, sem código de produto BE28. Ticket `m4-98989886cb74479daacf5510f6f2b310`, job `m2-b20678daa9234e1c89c3e7f7d7320988`: sete exemplos, seis falhas esperadas de DTO/contagem ausentes, zero pendentes/erros externos; isolamento cross-account/arquivado existente passou. JSON `/tmp/chat2you-agentes-b2-be28-red.json`, SHA-256 `316560856b3ab6711e9e0e7d0ad6a0fcc313cf854e9a8ee1aa68a9189a6dbe26`. stdout/stderr completos lidos; warnings de enum Rails 8, sem falha de harness. Depois disso, root iniciou a implementação BE28.

### Integração inicial após RED

Implementados localmente gate opt-in default-off e toggle SuperAdmin, lista em lote com último estado de thread projetado sem mensagens, canais mantidos e métricas; mesma decisão material compartilhada com Retriever; disponibilidade do ajudante; espelhos nativos; namespace privado e caminho assíncrono do teste. Root integra os arquivos compartilhados. Nenhum resultado desta implementação é presumido: GREEN, budget de consultas, revisão limitada e telas reais continuam pendentes.

Identidade: callback de nome preserva os writers existentes; avatar sincroniza pelo endpoint, sem invalidar teste. Instrução/config de resposta invalida somente pré-live; refresh/restore preservam comparação atômica e entram no domínio de lock do Agent, sem substituir o blob inteiro. Material informativo e hash efetivo são separados; writers de material continuam sendo integrados. Gates e serializers de conta não alteram o gate antigo nem opt-in de conta real.

Issue F0 #1123 atualizada com a continuação autorizada e D7 corrigida; alteração verificada por nova leitura. Históricos de parada/revisões finais preservados. Nenhum novo ciclo de revisão iniciado.
