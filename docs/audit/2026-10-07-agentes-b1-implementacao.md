# B1 — implementação local, testes primeiro

Issue de execução: [#1120](https://github.com/autonom-ia2/chat/issues/1120), ligada por referência à épica #1114. Branch e worktree existentes preservadas por instrução do Rodrigo. O PR documental #1115 permanece no HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`; nenhum novo push ou release.

## Entrada da implementação

Após duas paradas documentadas e autorização explícita para continuar, a checagem focada fechou TEC-11. Desenho revisado no hash `eb6a02821cc6c44202582961628edc0e0c5e7760f372a54b4ca6a2bd9d192399`; os dez pontos anteriores já estavam fechados. Histórico em `2026-10-07-agentes-b1-desenho-causa-raiz.md`. A aprovação é do desenho, não de código ou de telas reais ainda inexistentes.

Primeira fase: somente specs. Owners separados: configuração pública/operacional e auditoria; analytics/FAQ/thread/reaper/janela; principal nos códigos de erro restantes e throttle. Nenhum código de produto alterado nesta fase. Sintaxe Ruby dos quatro specs do principal e `git diff --check` passaram; RSpec ainda não executado, logo não há prova vermelha ou verde.

## MacCluster — regra conferida no código

O setup pesado foi recusado no M4 por `work_plan` com reserva de20 GB, enquanto há aproximadamente16 GB livres. A inferência inicial de que isso também bloquearia todo snapshot foi corrigida pela leitura do código público do MacCluster: `workspace_snapshot` não aplica a reserva de20 GB; copia e verifica o conteúdo. A réplica valida disponibilidade operacional; `workspace prepare` e o scheduler dos testes têm seus próprios guards de espaço.

A cópia oficial desta tarefa é pequena, aproximadamente342 MB; há espaço físico no M4 para ela e capacidade no M2 para preparação/testes. Isso permite usar o fluxo oficial sem apagar arquivos, copiar checkout ativo por fora, reduzir reservas ou forçar uma recusa do scheduler. O snapshot só será criado quando os writers tiverem parado. Nenhum runtime, instalação, snapshot ou banco iniciado/preparado nesta fase.

No M2, a inspeção do wrapper oficial confirmou Ruby3.4.4/Bundler2.5.16, Rails test e serviços descartáveis em127.0.0.1:55432/56379. Na consulta, não havia processo Ruby/Rails/RSpec/Bundler/wrapper nem clientes nos listeners. Reconfirmar antes de preparar o banco compartilhado de teste. Nunca usar produção, ambiente herdado ou portas habituais5432/6379.

## Compatibilidade BE-10

`WhatsappApi.vue:32–39,58–59` usa `data.error` como código para traduzir erros de provisionamento. Os specs novos preservam esse valor legado, acrescentam `code` estável e `message` localizado. Não trocar a semântica de `error` no Waha: isso faria o cliente antigo cair em erro genérico. Autonomia conserva seus erros localizados e recebe `code`. Erros desconhecidos de provedor não podem sair ao cliente ou ao log como detalhes brutos.

## Project

Item #1120 adicionado ao Project Autonom.ia Dev com sucesso: `PVTI_lAHOC3T16M4BX9UHzg_LCCI`. Leitura direta do node confirmou issue/projeto. As edições dos campos retornaram erro interno GraphQL, inclusive uma tentativa estruturada independente; não declarar campos atualizados. Metadados pendentes até o serviço permitir escrita. Isso não altera produção nem impede escrever/validar specs locais.

## Limites

Sem merge, fila, deploy, novas leituras de produção, limpeza de config ou eval pago. Antes B1 e Q12a são as únicas leituras de produção autorizadas, já concluídas. Nenhuma migration prevista; confirmar o diff quando houver implementação. Toda demonstração das telas reais continua pendente e bloqueia o primeiro deploy do redesign.

## Execução RED real e início do código

Snapshot oficial `20261007-121824-532a5b7b-1d85635416-494a4267`, conteúdo SHA-256 `1d85635416b8ed16efcd9a919f064d34b0520179520efa0fd82a0725fbf2ffed`: 14.676 arquivos, 342.402.207 bytes, duas réplicas verificadas. `workspace prepare` recusou o symlink rastreado `.windsurf/rules/chatwoot.md`; não alteramos o guard nem o snapshot. O runtime Ruby previamente disponível permitiu plano oficial de teste elegível no M2.

Wrapper `prepare` concluído, exit0, ticket `m4-84295141864c4b1e9239e1a5ffde0682`, job `m2-b87d61a298ed4ec98ce999712de4d752`: schema de teste carregado sem migrations. Antes dele, nenhum processo Ruby/teste ou conexão nos serviços de teste foi observado.

RSpec dos13 arquivos B1 realmente executado, 161 exemplos, 95 falhas, zero pendentes e zero erros fora dos exemplos, duração18,276s; ticket `m4-b254798510124dd48f5d8c6804b9770d`, job `m2-f37dba8ee3794db5a0c533934e1bfb31`. Relatório local `/tmp/chat2you-agentes-b1-red-m2.json`, SHA-256 `aa6f5d1fdd799ae6f4617474338ad3a1fe43a15a8930b7baf1bb2fd0709f4ac9`. Há falhas esperadas de recurso ausente e falhas de setup dos helpers de configuração por argumentos Ruby3: corrigir estes helpers antes de declarar RED desses contratos. Os demais testes demonstram falta de filtros de permissão, janela/preservação de draft, códigos e throttles. Nenhuma falha é aceita como prova verde.

Código liberado em ownership separado após leitura do relatório. Sem push para #1115; alterações locais para #1120. Nenhum aceite de tela real realizado nesta fase.

A segunda execução (somente dois contratos, helpers corrigidos), ticket `m4-dcf6ea7fa3d54a6f94e5175785ba5f34`, job `m2-0c1591648f3a446b87b139b3d3eeeab7`, abortou no boot: zero exemplos, dois erros fora dos exemplos. Causa concreta introduzida pelo principal: referência a `Autonomia::Agents::Config` durante initializer, antes de autoload dessa classe estar disponível. Registro dos throttles movido para `after_initialize`, preservando leitura de ENV uma vez e falha de boot para valor inválido. Não contar essa execução como RED ou verde. Nenhuma revisão independente de código começou; esta é a fase de implementação/teste.

Terceira execução no snapshot `20261007-123037-532a5b7b-15371b43fc-851ce8b5`, checksum `15371b43fcc31f05ec659d500eeba9a37bb954f956a4216e68110afc1411cdba`, ticket `m4-da3552cf96ff49acb3c33768164b0e1c`, job `m2-c860cd4407dc480bb00282f8b3ddb68e`:161 exemplos,45 falhas,0 pendentes/erros fora de exemplo,41,705s. Relatório `/tmp/chat2you-agentes-b1-partial-m2.json`, SHA-256 `51c38d7ddaa012c75d677535ef4067bf55ea67dfef6709a04db1b7a352611000`.

BE20(26 throttle+6 ENV), Waha(16), Playground(2), conexão(6), reaper(13), analytics(9) e FAQ(11) passaram. BE19/31 tem RED comportamental válido:24 recusas públicas não aplicadas,18 casos da rota operacional ainda ausente e1 filtro de audit ausente. Duas fixtures legadas com6min falharam após a mudança para600s; corrigidas para `STALE_PROCESSING_AFTER + 1.second`, mantendo casos dentro/fora da janela. Implementação dos contratos liberada após esse RED; não há verde global.

Dependências frontend instaladas apenas no snapshot original/M2 pelo job `m2-237a4daed75a4011b5e5fbd9aca1db65`: pnpm10.2.0,1.092 pacotes, lockfile inalterado, `workspace verify consistent=true` nos dois nós. `husky install` informou ausência de `.git` do snapshot; não se adicionou Git nem alterou esse isolamento. Sem servidor ou tela real iniciados.

RuboCop somente leitura no snapshot parcial:11 arquivos,7 offenses, ticket `m4-8ee2116b645a449ba00c5661ae0822cf`, job `m2-de7226e515b54e4a92822b8015c3d028`. Correções manuais no principal: reduzir a complexidade do parser de rota com match exato de segmentos em helper de domínio, manter Config no teto de linhas, extrair locale array da iteração e alinhar argumentos de spec. Sintaxe do parser conferida no Ruby3.4.4 via rbenv; Ruby2.6 do macOS não é o runtime do projeto. Sem auto-fix no snapshot; nova rodada de lint e testes será sobre snapshot novo.

## Contratos implementados, validação ainda parcial

Quarta execução: 162 exemplos, 20 falhas, zero pendentes e zero erros fora de exemplos; 36 testes JS do Registro passaram. Snapshot, jobs e hashes estão em `2026-10-07-agentes-b1-codigo-causa-raiz.md`, que precede o bloco corretivo. Configuração pública passou nos 27 casos; as falhas restantes estão no wrapper JSON da nova action operacional, nas fixtures de autenticação e no transporte do filtro de auditoria. Sem revisão independente de código até concluir a validação exigida.

## Preview e preparação B2

Preview isolado no M2, job `m2-30bfd439114242cebb6928cf76175665`: Rails 59720, Vite 59721, PostgreSQL 59722, Redis 59723. `/` e `/app/login` retornaram HTTP200; Redis respondeu PONG. Wrapper fora do Git usa ambiente limpo, dados descartáveis, IA externa desativada e SMTP sem envio externo. Serviços de teste 55432/56379 foram preservados. Trata-se do snapshot original, com a interface antiga; nenhuma tela do redesign foi aceita.

Issue B2 #1122 criada e adicionada ao Project, item `PVTI_lAHOC3T16M4BX9UHzg_Lg4o`. `design/B2.md` e `2026-10-07-agentes-b2-mapeamento.md` são rascunhos documentais, sem implementação ou aprovação de desenho. Os campos do Project continuam pendentes após os erros internos do GitHub já registrados; não houve nova tentativa em loop.

## Localização dos casos Enterprise do BE-25

Os três casos de permissão por função personalizada (`autonomia_view` sem permissão de conversa, participação limitada às conversas próprias e isolamento entre contas) ficam em `spec/enterprise/requests/api/v1/accounts/autonomia/agents/analytics_permissions_spec.rb`. O arquivo geral `spec/requests/api/v1/accounts/autonomia/agents/analytics_spec.rb` mantém somente os contratos de analytics aplicáveis ao núcleo comum. Esta é uma correção de localização; não houve execução de RSpec, banco ou extrapolação de resultado. Nesta etapa foram previstos apenas sintaxe Ruby e `git diff --check`.
