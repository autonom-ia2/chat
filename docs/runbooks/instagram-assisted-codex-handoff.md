# Instagram assistido — handoff operacional para o Codex

## 1. Comece aqui

Consolidação de 07/10/2026. GitHub e worktrees relidos às 10:07 UTC (07:07 de Brasília). Este documento entrega continuidade; NÃO declara Instagram conectado, não encerra a #995 e não autoriza ignorar verificações. Nesta entrega não se executou novo login, publicação, alteração de configuração ou manutenção da VPS.

Leia `AGENTS.md`, este documento e `docs/audit/995-handoff-evidence-20261007.json`. Depois leia apenas as fontes indicadas para o bloqueio atual. O runbook operacional detalhado é `docs/runbooks/instagram-vps-runtime-995.md`. Relatos antigos de que a #1089 não foi instalada ou os sete serviços não foram retomados foram superados pelos recibos de 07/10.

- Repositório: https://github.com/autonom-ia2/chat
- Issue principal, ainda aberta: https://github.com/autonom-ia2/chat/issues/995
- PR de continuidade, ainda draft: https://github.com/autonom-ia2/chat/pull/1112
- Project obrigatório: https://github.com/users/autonom-ia/projects/3 — Autonom.ia Dev.

Objetivo de produto: Rodrigo conseguir concluir o Instagram assistido e conectar uma conta autorizada pelo painel, com sessão administrativa Meta válida e renovada automaticamente. Priorizar Autonom.ia, onde ele já realizou login humano; homologar Hub2You separadamente. Não prometer reaproveitamento de autenticação sem observar o perfil: login humano concluído na página não é recibo de sessão publicada.

Arquitetura estabelecida: painel/SuperAdmin e backend Chat2You na AWS; Chrome persistente, gestor e publicador na VPS acessada por `ssh n8n`, servidor srv707880. Proxy obrigatório no caminho do browser. Macs são estações de desenvolvimento/administração, NÃO runtime permanente, renovadores ou gestores do Instagram.

## 2. Worktree certa e estado do código

Retomar no M4 em `/Users/rodrigosilva/dev/worktrees/chat2you/995-meta-page-bootstrap`, branch `fix/995-meta-page-bootstrap`, PR #1112. Head funcional antes deste handoff: `0dab6b6c4d401312d25d4ec91e8e707d0c5315cc`; base da PR: `6242e31695fd1c6b8b088f2fcb819c027fc5083c`. Um commit apenas documental desta entrega poderá avançar o head; reconsulte GitHub antes de usar hashes/checks. A worktree estava limpa antes da escrita deste handoff.

NÃO trabalhar por engano em `/Users/rodrigosilva/dev/worktrees/chat2you/995-operator-recovery`: branch antiga `fix/995-operator-session-recovery`, HEAD `5ff4be0a7f8df86653498dfbfb659917dfa8beb5`, com seis arquivos experimentais não commitados, não aprovados e não instalados. Seus paths/hashes estão no manifesto de evidências. Não apagar, resetar, sobrescrever, instalar nem misturar automaticamente esses deltas; reconciliar autoria/intenção primeiro.

Esse candidato antigo acrescentava `GeoNextAppControllerContainerQuery` à captura e aceitava `fetch__Application.id` como alternativa à resposta completa de papéis. Revisores o reprovaram por reduzir a validação e confundir carregamento com autorização para publicar sessão. Ele não é a correção a reaproveitar cegamente.

## 3. O que já está entregue

| Item | Estado comprovado |
|---|---|
| #1065 — transporte concorrente | Incorporada anteriormente; deadline individual continua 25 s. Não refazer. |
| #1089 — supervisão de reconexão | Merge `9a48a2de08e93f2f7dc6916d7a4c79729f88dec4`, instalado na VPS em 07/10 às 09:12:56 UTC. |
| Retomada após #1089 | Rodrigo iniciou sete units; releituras confirmaram seus mesmos PIDs. Não reinstalar por inferência de comentário antigo. |
| #1112 — classificação antes da captura | Implementada, revisada e em draft. NÃO está instalada no runtime da VPS. |
| Documento inicial Meta | Identificado no módulo compilado real em 09:52:27 UTC; falta a resposta da consulta inicial e comprovação do fluxo completo. |
| Sessão / assistido | Sem recibo de publicação/renovação. Último bootstrap observado não tinha ponteiro de sessão. Assistido registrado como OFF; revalidar o estado antes de qualquer ativação. |

A #1089 mantém a supervisão do mesmo pedido durante claim, bootstrap, navegador e manager; reconcilia resposta perdida com o backend e respeita vencimento confirmado. TTL de lease de 90 s e teto de uma hora não foram ampliados. Sucesso real deve encerrar/drenar o filho sem repetir publicação. A #1112 classifica endpoint, método POST e `rolesQueryFields` ANTES de reservar `publication` ou aguardar `allHeaders()`. Não modifica o filtro de navegação, publisher Rails, papéis ou CAS.

Testes registrados: #1089, 286 testes locais; #1112, 290 testes locais ampliados e 70 focais manager/observer, sem falhas/skips/cancelamentos nas execuções finais. Dois testes GET/HEAD reproduziram o defeito antes da correção; depois foram acrescentados POST irrelevante e POST inválido. Revisão Nexo aprovada para o código; os dois casos negativos POST foram adicionados após o parecer sem novo delta funcional. São testes simulados, não homologação Meta.

CI da PR #1112 relido em 10:07 UTC no head funcional acima: 23 checks passados, dois jobs de e-mail SKIPPED; RSpec agregado, Vitest, central, trava, fork-i18n e os jobs Instagram SUCCESS. Isso NÃO é CI do futuro commit de handoff, nem da futura correção do carregamento ou do grupo da fila. A PR permanece draft e fora do fluxo de liberação operacional.

## 4. Último estado operacional observado — não confundir com leitura nova

Runtime selecionado: `/opt/instagram-meta/releases/9a48a2de08e93f2f7dc6916d7a4c79729f88dec4`, acessado por `/opt/instagram-meta/current`. A tabela abaixo é a leitura de 09:55:50 UTC; às 10:02:42 UTC reconfirmaram-se Autonomia manager inativo, publisher ativo, sem janela humana, lock ou diagnóstico restante. Uma nova leitura agregada da VPS nesta entrega foi recusada pela ferramenta antes de fornecer resultado: NÃO há confirmação operacional mais recente neste handoff.

| Unit `instagram-vps-…@….service` | Estado | PID |
|---|---|---:|
| display@hub2you | active | 72724 |
| gateway@hub2you | active | 72773 |
| publisher@hub2you | active | 72721 |
| manager@hub2you | active | 72762 |
| display@autonomia | active | 72727 |
| gateway@autonomia | active | 72775 |
| publisher@autonomia | active | 72722 |
| manager@autonomia | inactive, intencional para diagnóstico | 0 |

Todas tinham NRestarts=0 nessa leitura. Active/PID não comprovam heartbeat recente ou sessão válida. Não habilitar manager Autonomia enquanto outro processo usar seu perfil. O usuário o parou explicitamente; só retomar na etapa operacional apropriada. Boot automático não foi homologado e as units estavam desabilitadas nas leituras anteriores; revalidar e consolidar antes do aceite.

Gestor = wrapper `manager.sh` alternando manager automático e waiter da autorização humana. Publicador = broker Unix que acessa o backend AWS com identidade restrita; não é o workflow n8n. Display/gateway = acesso privado ao Chrome. O serviço n8n/Traefik/Redis não deve ser reiniciado para corrigir o Instagram.

## 5. Bloqueio atual, com evidência e limites

**Fato A — filtro incompatível com o carregamento inicial.** O manager instalado permite POST GraphQL apenas quando `rolesQueryFields` identifica `RolesTable_Query`. Na observação real de 09:22:16–09:23:12 UTC, a página emitiu três `GeoNextAppControllerContainerQuery`: uma variável `appID` correta; negócio, administrador e ator correspondentes; documento diferente do RolesTable. As três falharam sob o filtro instalado. A consulta final de papéis não apareceu e o título da página não foi observado. A presença da URL não prova que o login permaneceu válido.

**Fato B — já sabemos que o documento inicial é uma query.** O diagnóstico `instagram-autonomia-document-095152`, concluído às 09:52:27 UTC, leu o módulo compilado usado pela própria página, sem ampliar o filtro: kind Request, nome correspondente, operationKind=query, exatamente um LocalArgument appID e documento igual ao observado na requisição natural. SHA256 do identificador público do documento: `e3050f6f5039fae023bca06560b9aba52597bccd045d0e84bf1388e8abeca508`. Bootstrap 20.010 ms, HTTP200 de navegação, browser_closed=true, sem publicação. O recibo sanitizado está no manifesto versionado de evidências.

Esse hash é do ID público, não o ID numérico em si. Não inventar nem substituir o documento RolesTable por ele. O ID da carga inicial e o documento da consulta de papéis são distintos. A leitura do módulo NÃO é a resposta GraphQL, não demonstra papéis e não é prova de sessão publicada. Falta observar a resposta da consulta inicial permitida de forma estreita e a sequência que vem depois. É possível que apareçam outros pré-requisitos: comprovar cada um, sem aceitar tudo por nome.

**Fato C — disputa de captura já corrigida na #1112.** Respostas GET/HEAD ou POST não elegíveis não podem reservar `publication` enquanto a consulta válida chega. A correção está no branch, não no runtime. Manter essa seleção separada mesmo depois de permitir consultas apenas de carregamento.

**Fato D — transporte ainda próximo do limite.** O publicador tem 25 s para STS/CURRENT, túnel SSM, chave do host, SSH e execução remota. Há sucessos de bootstrap em aproximadamente19–22s e falhas perto de25s. Um bootstrap somente leitura às09:38:49UTC passou em19.002ms com configuração completa e version=null. Não declarar transporte estável por esse resultado. O código repete preparação por chamada e o Ruby carrega Rails antes de processar o pedido; ainda não há medição que identifique o maior custo.

**Hipótese a validar:** liberar de forma restrita a query de inicialização deve permitir montar a página e chegar à consulta de papéis. Não está demonstrado que essa única alteração baste. Não continuar afirmando que o documento inicial é desconhecido: sua natureza query e vínculo com a requisição já foram observados. O que falta é resposta/sequência completa.

## 6. Próxima execução recomendada

1. Reconciliar worktree/head da #1112 e estado vivo da VPS por meios autorizados. Não reaplicar #1089. Conferir ausência de janela/Chrome/lock concorrente na Autonomia. Revalidar CURRENT e release AWS antes de qualquer mudança: o último SHA Rails não foi reconfirmado nesta entrega e pode ter avançado pela fila.
2. Revisar o candidato diagnóstico `.codex/observe-initial-read.mjs` da worktree atual. Ele propõe permitir SOMENTE a query inicial pelo hash já observado, endpoint/método/variáveis/identidades, preservando o restante do filtro e sem publish/heartbeat. Está preparado e foi enviado a staging, mas sua execução foi recusada: não existe resultado da resposta inicial. Conferir limite de execução, buffers/respostas e drenagem antes de usá-lo; o arquivo não é release aprovada.
3. Executar a observação permitida com o mesmo perfil, usuário, grupos, Node, sandbox e proxy do serviço. Carregar a configuração canônica por bootstrap. Registrar só fases, tempos, status e estrutura/booleans sanitizados. Não fabricar/repetir requisição capturada, não extrair credenciais, não pedir novo login sem evidência real de challenge ou sessão expirada.
4. Ajustar o carregamento na MESMA PR #1112 com contrato próprio de leitura, preservando captura/publicação só pela consulta final de papéis. Um pin novo precisa de fonte explícita, validação, documentação e revisão; se for metadata canônica, incluir no protocolo e revisão de configuração, sem criar fallback silencioso ou afetar stacks ainda sem configuração. Não usar `fetch__Application.id` como substituto dos papéis.
5. Em paralelo, medir cada fase do transporte em chamadas de leitura com identificação efêmera e sem payloads. Corrigir o custo demonstrado, não acrescentar cache/retry/conexão permanente/worker aquecido só por suposição. Preservar vínculo conta/instância/chave e resultado incerto sem replay. Configuração transitória de CPU200% exige decisão fundamentada e persistência antes do aceite; não aumentá-la novamente às cegas.
6. Reproduzir a falha e validar fix com testes, revisão independente final e CI do SHA exato; enfileirar sem bypass. Confirmar MERGED e depois o upgrade imutável da VPS. Não confundir o deploy Rails com troca do runtime externo. Revalidar hashes e estado após cada fase, restaurando apenas serviços previstos, com rollback disponível.
7. Comprovar captura natural, registro real da sessão no backend e duas renovações automáticas sem intervenção, em ciclos naturais. Consolidar recursos/boot e testar recuperação dos serviços. Ativar primeiro Autonomia, fazer conexão de conta autorizada pelo painel e teste de funcionamento do canal; homologar Hub2You em sequência separada. Não inventar conta de teste ou aceite humano.

## 7. Onde mexer — mapa focal

| Arquivo / área | Papel e mudança possível |
|---|---|
| `scripts/instagram_testers/session-manager.mjs` | `isAllowedBrowserRequest`, seleção de respostas, navegação e publicação. Manter a classificação antecipada da #1112; separar permissão de carga da elegibilidade de captura. |
| `scripts/instagram_testers/session-observer.mjs` | Configuração, `rolesQueryFields`, `observedSession`, `safeBrowserLocation`, `validateRolesResponse`. Não reduzir validação de identidade/documento/papéis. |
| `scripts/instagram_testers/runtime/operator-waiter.mjs` | Correção da lease já instalada pela #1089; não reimplementar ou aumentar TTL. |
| `scripts/instagram_testers/session-browser.mjs` | Janela humana, perfil e lock. O caminho humano não é prova de captura. Não disparar novo login como teste. |
| `scripts/instagram_testers/runtime/publisher-tunnel.mjs` | Orçamento de 25 s, STS/CURRENT, SSM, host key, SSH. Instrumentar fases sem expor comandos/credenciais. |
| `scripts/instagram_testers/runtime/vps/publisher-{client,broker,socket}.mjs` | Socket por stack, validação de identidade, fila e deadlines. Não usar root para simular o client do gestor. |
| `scripts/instagram_testers/session_publisher.rb` | Entrada Ruby que carrega Rails por operação. Medir boot e execução antes de escolher otimização. |
| `app/services/instagram/automation/{metadata,session_publisher,operator_control}.rb` | Fonte canônica, revisão, gravação de sessão e estados de reconexão. Alterar apenas se o contrato comprovado exigir. |
| `scripts/instagram_testers/runtime/operator-protocol.mjs` | Envelope tipado exato; eventual metadata nova precisa manter compatibilidade e limites explícitos. |
| `tests/instagram_testers/{session-manager,session-observer,operator-control,operator-waiter,runtime-publisher,vps-publisher,runtime-entrypoint,publisher-concurrency}.test.mjs` | Testes Node de captura, lease e transporte. |
| `spec/services/instagram/automation/session_publisher_spec.rb` e testes de parser/metadata existentes | Resposta completa, casos negativos e preservação de sessão; não depender só de doubles de parser/CAS. |
| `.github/workflows/instagram-tester-onboarding.yml` | Listas explícitas de teste/lint. Toda regressão nova precisa efetivamente entrar no CI. |

Testes adicionais para o carregamento: query inicial permitida sem gerar sessão; nome/documento/identidades errados recusados; mutação ou query desconhecida recusada; resposta inicial seguida de RolesTable válida publica uma vez; app.id isolado, resposta mista/incompleta, erro ou paginação inconclusiva não publicam; CAS divergente preserva sessão anterior; cancelamento e atraso não produzem publicação duplicada. Exercitar o route handler real no harness, não um stub de route que sempre passa.

## 8. Caminhos de operação e evidências recuperáveis

No servidor: `/opt/instagram-meta/current` aponta à release instalada; releases são imutáveis em `/opt/instagram-meta/releases/`. Staging da implantação #1089: `/opt/instagram-meta-staging/upgrade-1089-20261007/`, com recibos de stage, before, stop, preflight, install e resume-observed. Não executar automaticamente fontes históricas só porque estão em staging.

O gestor usa `ig-autonomia`/`ig-hub2you`; os publicadores têm usuários `igpub-*`; gateways `iggw-*`. Node privado `/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin/node` é montado em `/usr/bin/node` pelas units. Um processo transitório fora desse namespace pode usar outro Node; conferir também subprocessos. Perfil Autonomia: `/var/lib/instagram-autonomia/profile`; marcador humano `/run/instagram-autonomia/browser-request.json`; lock `.instagram-manager.lock` no perfil; socket do publicador `/run/instagram-publisher-autonomia/publisher.sock`. Nunca apagar lock de processo alheio para avançar.

`/etc/instagram-meta/autonomia/manager.env` contém configuração local de runtime, não todos os IDs canônicos. Usar bootstrap e `observerConfiguration(env, bootstrap)`, não `configuration(process.env)` diretamente. O wrapper prepara o comando do publicador; carregar apenas ENV não o reproduz. Não imprimir ENV, envelopes completos, cookies, senhas ou chaves; usar a configuração existente sem reproduzi-la no relatório.

Metadados/configurações históricas a preservar: perfil e link `.config -> profile/.chrome-config`; proxy obrigatório; sandbox Chromium; runtime CPU200% dos publicadores versus template50%, e manager150% nas últimas leituras. A discrepância é dívida de consolidação operacional, não licença para alterar quotas. HTTP401 no gateway sem grant demonstra recusa esperada, não erro de login Meta.

No M4 antigo: `/Users/rodrigosilva/dev/worktrees/chat2you/995-operator-recovery/.codex/ops-995/after-manual-resume-20261007/` contém `public-document-metadata.mjs` e `instagram-autonomia-document-095152.{intent,result}.json`. O result foi relido nesta entrega e sua cópia sanitizada é versionada junto ao handoff. SHA do script: `1bce6de47549fa3709c2902cc52f48a879f5d8e593bc62c853f6a6a327e5d080`.

No mesmo prefixo `.codex/ops-995/retomada-20261007/` ficam `natural-query-evidence-092216.json`, `observe-natural-query.mjs`, `observe-query-document.mjs`, pacote/manifesto #1089 e revisões. São evidências históricas e ferramentas de diagnóstico; não alterações instaladas. Na worktree de continuidade existe `.codex/observe-initial-read.mjs`, SHA `fe0fbf429943f0d17776be95c18e53691014a20c58085417babf96106e7bb9b0`: candidato pendente de execução/validação, NÃO resultado.

Arquivos em `.codex` são locais/ignorados e podem não existir num checkout cloud. Não inventar paths de outro ambiente. Usar o manifesto versionado para conhecer a evidência e solicitar acesso ao workspace autorizado quando os bytes operacionais forem necessários. O runbook contém passos históricos; o presente handoff define o estado de retomada.

## 9. Revisores e lições para não reiniciar a investigação

Revisões mais relevantes já realizadas: Iris-carga/Argos-contrato separaram carregamento de captura; Iris-carga40282 identificou a reserva antecipada; Atlas-latencia40283 mapeou o custo repetido sem medir fases; Argos-guard40284 preservou contrato de papéis; Nexo-revisao65637 aprovou a correção funcional da #1112. Revisões anteriores da #1089 e de sua implantação estão nos comentários e auditorias próprios. Não relançar todos apenas para repetir os mesmos pareceres. Estes são processos históricos concluídos, NÃO agentes ativos transferidos ao Codex.

Para continuação em paralelo: um responsável pela resposta/contrato inicial, outro pela medição do transporte, um revisor independente dos testes/segurança. Um único executor de produção e um dono por arquivo/worktree. Nomear processos e registrar escopo real; não contar tentativa recusada ou exit0 sem atividade como validação.

Erros já esclarecidos: `configuration(process.env)` falhou antes do Chrome por ignorar bootstrap; isso não provava perda do login. Saída zero de diagnóstico indicava término da coleta, não sessão válida. Houve saídas SSH genéricas e comandos recusados; nem toda recusa significava servidor indisponível. O Chrome manual não publicava sessão por si: o manager precisava de navegação/captura natural posterior. Não repetir esses testes como se fossem evidência nova.

Ferramentas: GitHub e Rodrigo_Local_Terminal responderam a várias leituras/escritas. Também houve recusas de ações específicas e `Native routing blocked: enrollment outcome unavailable; no local replay.`. Não atribuir causa além da evidência; não alterar políticas, relaxar permissões, trocar identidades ou roteamentos para contornar recusa. Em Codex, usar o acesso normal explicitamente autorizado; se uma ação continuar indisponível, pedir somente o comando humano mínimo e revisar o resultado antes do próximo. Não transformar novamente um erro de invocação em tarefa de reconstruir a infraestrutura.

O conector dedicado Autonom.ia_GitHub_Projects retornou404 em rodadas anteriores; a CLI `gh` atualizou o board com leitura de retorno. Respeitar as permissões atuais. Se o Project ficar inacessível, ainda atualizar issue/PR e registrar `Project update pendente` com os sete valores exatos, sem alegar sucesso.

## 10. Aceite, governança e reversão

O fechamento requer: nova versão identificada em execução; página inicial carregada pelo contrato permitido; captura natural com resposta completa de papéis e identidades correspondentes; recibo real de gravação no backend (não apenas uma URL ou log de browser); duas renovações naturais sem operador/replay; estabilidade do transporte; recursos e boot persistentes; conexão e teste de funcionamento de conta autorizada no painel. Autonomia e Hub2You têm aceites separados. Se ocorrer desafio/2FA real, Rodrigo autentica na janela privada; nunca solicitar senha/código no chat.

Não alterar DNS/Tailscale/proxy/Redis/IAM/n8n, reaplicar migração de chave ou voltar a managers nos Macs sem causa demonstrada e escopo aprovado. Não usar `--no-sandbox`, apagar perfil/lock vivo, inventar heartbeat ou editar recibos/fases para fabricar sucesso. Não publicar uma requisição capturada de outra tentativa. Preserve prazo, revisão canônica e comparação de versão na gravação (CAS).

Fluxo de entrega: Issue → Branch → PR → Project → revisão → aprovação → fila → confirmação MERGED → plano de deploy/rollback → upgrade VPS → validação. Revalidar RSpec agregado, Vitest, trava, central, fork-i18n e jobs Instagram no SHA exato; executar os checks próprios da fila. Não fazer force-push ou bypass. Autorizações anteriores de Rodrigo continuam subordinadas às regras do repositório, isolamento, escopo e evidências; a solicitação atual a este chat foi preparar handoff, não executar outra implantação.

Para rollback futuro, conferir a release anterior realmente instalada (9a48a2d neste checkpoint), drenar apenas as units Instagram envolvidas, preservar perfis/chaves/metadata/resultados e restaurar a seleção da release por procedimento já revisado; retomar somente o conjunto de serviços explicitamente previsto. Não interpretar rollback como reinício geral ou restauração de sessão antiga no Redis. Não sobrescrever releases imutáveis. O installer exige oito units inativas; não iniciar nova manutenção sem caminho permitido de retomada/reversão.

Project atual desejado: #995 Projeto=Hub2You; Status=Em desenvolvimento; Tipo=Infra; Prioridade=P1; Risco=Alto; Ambiente=Produção. #1112 Projeto=Hub2You; Status=PR aberta; Tipo=Bug; Prioridade=P1; Risco=Alto; Ambiente=Produção. Próxima ação deve apontar a este handoff e à resposta inicial ainda não observada; não marcar conectado/concluído.

## 11. Referências mínimas, em ordem útil

1. https://github.com/autonom-ia2/chat/issues/995#issuecomment-6035608339 — documento inicial identificado, sem resposta/publicação.
2. https://github.com/autonom-ia2/chat/issues/995#issuecomment-6035524599 — #1112, 290 testes, limitação da captura.
3. https://github.com/autonom-ia2/chat/issues/995#issuecomment-6035123828 — sete serviços retomados e query inicial bloqueada.
4. https://github.com/autonom-ia2/chat/issues/995#issuecomment-6034834229 — instalação #1089; a pendência de retomada descrita aqui foi resolvida pelo item3.
5. `docs/audit/995-post-resume-page-loading-20261007.md` — histórico da rodada; complementar com a evidência de09:52, mais recente.

Primeira entrega do Codex: revalidar o ponto de retomada, apresentar o menor teste conclusivo da resposta inicial e executar pelo canal autorizado. Acompanhar até uma correção testada e um resultado de produto ou um bloqueio verificável com uma única ação necessária. Não encerrar em mais um plano genérico, contagem de testes ou relatório de serviços ativos.
