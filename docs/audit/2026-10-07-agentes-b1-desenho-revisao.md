# B1 — primeira revisão do desenho técnico

Baseline fixo: `6242e31695fd1c6b8b088f2fcb819c027fc5083c`.

Artefato diferente da revisão R9 do PRD. O desenho B1 já estava explicitamente marcado como rascunho não aprovado no PR documental #1115. A revisão inicial foi somente leitura; nenhuma implementação, spec, teste, eval pago ou nova consulta de produção foi executada.

| ID | Gravidade | Prova e problema | Correção exigida |
|---|---|---|---|
| B1-TEC-01 | P0 | B1 §7 previa revert genérico; PRD §14 exige impedir que o cron antigo apague rascunho com resposta no rollback | Volta blue-green, cron desativado antes do worker ou BE14 preservado; conferência dos IDs antes/depois do ciclo |
| B1-TEC-02 | P1 | Ação/shape AuditLog indefinidos; helper não reconhece tipo; ator SuperAdmin não resolve como atendente; filtros ausentes | Ação estável, shape sanitizado, handler/tipo/filtros e en/pt_BR |
| B1-TEC-03 | P1 | Valores operacionais sem tipo, limites, slugs, telefones ou shape de arrays | Contrato fechado e 422 com key antes do lock, old/new previsíveis e mascarados |
| B1-TEC-04 | P1 | Helper Autonomia não alcança Waha; BuildThreads/Playground têm erros sem code; cliente antigo lê error | Renderer aplicável a todos os alvos e lista de envelopes/códigos, compatibilidade do cliente |
| B1-TEC-05 | P1 | Headers do throttle e defaults ainda pendentes | Extração Rack exata, hash seguro, sessão/API cobertos e defaults numéricos antes do código |
| B1-TEC-06 | P2 | Rota SuperAdmin sem member/leitura/auth real/variantes | Contrato por formato e guards existentes, leitura para F7, sistema/Lia explícitos |
| B1-TEC-07 | P2 | Restaurar toda escrita no teste contradiz auditoria imutável | Restaurar configuração e manter auditoria como evidência |

B1 bloqueado para código. Worker recebeu ownership apenas de B1.md para corrigir; próxima etapa é checagem das correções. Se a checagem encontrar erro, parar, registrar causa raiz, corrigir causa e fazer uma revisão final; persistindo erro, retornar ao Rodrigo. Não repetir rodadas.

As correções locais não alteram o HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488` do PR documental #1115, que recebeu um único push. Nenhuma vaga solicitada, merge, deploy ou produção alterada.

## CI do PR documental e ambiente local

PR #1115, HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`: vinte checks concluídos com SUCCESS, incluindo RSpec (oito fatias e agregado), Vitest, ESLint, Rubocop, e-mail, segurança, traduções, Guia e Central. Auto-merge = null; fila não solicitada. Project atualizado para CI verde e OK específico pendente. Nenhum novo push após o primeiro envio do PR. A descrição explicita que o desenho B1 ainda não está aprovado.

Os arquivos ignorados `.codex/environments/environment.toml`, `.codex/setup-worktree.sh`, `.codex/run-local.sh` e `Procfile.worktree` foram preparados, sem executar setup: portas Rails/Vite/PostgreSQL/Redis 59710/59711/59712/59713, loopback, dados sob `.codex/runtime/`, env -i sem credenciais de produção. Sintaxe passou; formato TOML confirmado no validator público do app Codex instalado. O encerramento local foi ajustado para não mandar shutdown TCP a serviço alheio e só parar PostgreSQL iniciado pelo próprio processo.

`maccluster work plan --cwd <worktree> -- bash .codex/setup-worktree.sh` recusou execução: M2 cwd-missing, M4 insufficient disk. `maccluster resources`: M4 13,2 GB SSD livres, 6,2 GB RAM livres; M2 288,4 GB SSD livres, 2,9 GB RAM livres, Thunderbolt. Nada foi forçado, apagado, instalado ou iniciado. `workspace inspect`: 14.668 arquivos, 342.323.266 bytes para snapshot do estado observado; configs ignoradas não entram automaticamente. Uma eventual execução no M2 exige snapshot verificado e dependências isoladas, sem copiar checkout ativo. Nenhum snapshot criado ainda.

Fontes oficiais do ambiente Codex consultadas somente para configuração local: https://developers.openai.com/codex/app/local-environments (redirect oficial para ChatGPT Learn). A documentação não fixa o schema TOML; o formato exato foi confirmado no código público de `/Applications/Codex.app/Contents/Resources/app.asar`. Nenhum dado de usuário do app foi lido.

## Checagem e parada

A checagem independente fechou B1-TEC-01, 02, 04, 06 e 07, mas encontrou quatro P1 (B1-TEC-08 a 11): identidade de throttle controlável, duas chaves aprovadas sem contrato liberado, impossibilidade de limpar arrays e validação do payload possivelmente posterior à sanitização. A causa foi registrada **antes da nova correção** em `2026-10-07-agentes-b1-desenho-causa-raiz.md`. Não houve implementação. A próxima revisão do desenho é a final única; qualquer erro nela encerra o trabalho e exige retorno ao Rodrigo.

O diagnóstico adicional confirmou que o M4 está abaixo da reserva obrigatória de 20 GB (13,1 GB livres e zero utilizável para o scheduler); o M2 tem capacidade de disco, mas não esta worktree. O snapshot anterior não contém o estado atual nem as dependências de desenvolvimento. Nenhum snapshot, instalação ou execução foi feito. O setup ignorado precisa fixar `FRONTEND_URL` para a porta 59710 e capturar os PIDs dos processos reais antes de eventual uso.

Nova conferência direta do PR #1115: permanece OPEN/MERGEABLE, no mesmo HEAD, auto-merge nulo; todas as entradas de CI retornadas estão concluídas com SUCCESS, inclusive as duas entradas adicionais do Guia após a edição do corpo. CI não aprova o desenho B1 nem as telas reais. Nenhuma consulta de produção além das duas leituras autorizadas foi executada.

## Setup ignorado corrigido e limite da alternativa M2

Os dois scripts ignorados agora fixam `FRONTEND_URL=http://127.0.0.1:59710`. Redis e Overmind usam subshell com `exec` para capturar o PID real; cleanup chama `overmind quit` no socket próprio somente quando o processo atual atribuiu `OVERMIND_PID`. `bash -n` passou nos dois arquivos; nenhuma execução foi feita.

A primeira busca pelos caminhos pessoais não encontrou runtimes no M2, mas a conferência pelos wrappers oficiais corrigiu essa informação: Ruby 3.4.4, Node 24.11.0, Corepack/pnpm 10.2.0, PostgreSQL 16.15 e Redis 8.10.2 já existem sob `/Users/Shared/maccluster-tools/`. Não há rbenv, nvm ou Overmind compartilhado. Não instalar nem substituir esses runtimes sem necessidade demonstrada.

O CLI público não oferece `workspace snapshot --node`: captura somente um checkout existente no nó executor e materializa a cópia local antes da réplica. `--local-only` não muda a origem; `workspace prepare --node m2` exige snapshot prévio. Assim, o diagnóstico não encontrou uma rota oficial para capturar este checkout diretamente no M2 sem materializar antes a fonte ou o snapshot no M4. A reserva continua preservada; nenhum limite foi reduzido, diretório apagado ou checkout copiado por fora.

## Resultado final e retorno ao Rodrigo

Revisão final única: **B1-TEC-11 residual P1**. O desenho confunde o update genérico de Account no SuperAdmin com o PATCH de agente; a rota/param de conta não constitui entrada de config do agente. B1-TEC-01 a 10 sem outro erro concreto identificado nessa final. Prova e causa remanescente em `2026-10-07-agentes-b1-desenho-causa-raiz.md`.

O trabalho foi parado sem nova correção ou rodada e sem implementação. As telas reais continuam inexistentes e não aceitas; o protótipo já inspecionado não satisfaz esse gate. O PR documental #1115 continua no mesmo HEAD, com CI verde e sem migration; OK específico de merge permanece pendente. As correções do desenho e estes audits são locais e não foram incluídos no PR congelado. A última leitura de recursos registrou M4 com 11,4 GB livres, ainda abaixo da reserva de 20 GB; ambiente não iniciado.
