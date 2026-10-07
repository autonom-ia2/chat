# Mensagem inicial para o Codex

Assuma a execução da recuperação do Instagram assistido da Autonom.ia/Hub2You. Estamos há dias nisso; preciso que você retome do ponto comprovado, conclua a correção e valide o uso, sem reiniciar a investigação ou me pedir outro login por tentativa e erro.

Repositório: https://github.com/autonom-ia2/chat
Issue principal: https://github.com/autonom-ia2/chat/issues/995
PR de continuidade: https://github.com/autonom-ia2/chat/pull/1112
Project obrigatório: https://github.com/users/autonom-ia/projects/3

No M4, use a worktree `/Users/rodrigosilva/dev/worktrees/chat2you/995-meta-page-bootstrap`, branch `fix/995-meta-page-bootstrap`. Primeiro leia `AGENTS.md`, `docs/runbooks/instagram-assisted-codex-handoff.md` e `docs/audit/995-handoff-evidence-20261007.json`. O handoff contém estado, caminhos, evidências, arquivos a alterar, testes, revisões e rollback. Se estiver num checkout cloud, os artefatos `.codex` são locais: não presuma que existem; use as evidências versionadas e o workspace autorizado para operação.

Estado a preservar:
- A #1089 JÁ FOI INSTALADA na VPS n8n: release `9a48a2de08e93f2f7dc6916d7a4c79729f88dec4`. Os sete serviços foram retomados; o gestor da Autonom.ia ficou parado intencionalmente para diagnóstico sem concorrência. Revalide o estado vivo; não reinstale nem reinicie tudo. M2/M4 são estações administrativas, não runtime do Instagram.
- A #1112 está draft. O commit funcional `0dab6b6c4d401312d25d4ec91e8e707d0c5315cc` impede respostas não elegíveis de ocupar a captura. Passaram 290 testes locais; o CI desse head estava verde, com dois jobs de e-mail pulados. Isso não é homologação Meta nem CI de um novo head. O código da #1112 ainda NÃO está instalado na VPS.
- O filtro atual bloqueia `GeoNextAppControllerContainerQuery`, emitida no carregamento da página. A natureza `query` JÁ foi confirmada no módulo compilado real, com um único argumento `appID` e documento correspondente à requisição. SHA256 do ID público: `e3050f6f5039fae023bca06560b9aba52597bccd045d0e84bf1388e8abeca508`. Falta a RESPOSTA dessa consulta e a sequência até a tabela de papéis; não falta redescobrir que ela é uma query.
- Não existe confirmação de sessão publicada ou renovada. O assistido não foi liberado. Bootstrap ainda oscila próximo do limite de 25 segundos.

Primeiro trabalho concreto: revalidar a exclusividade do perfil e revisar o diagnóstico `.codex/observe-initial-read.mjs` para observar, por execução permitida, a resposta da consulta inicial estritamente vinculada ao documento, aplicativo, negócio e administrador. Manter sandbox/proxy/identidade e não publicar nesse diagnóstico. Depois separar permissão de carregamento de elegibilidade para captura na mesma PR. Não aceitar `fetch__Application.id` como substituto de papéis completos. Preservar CAS, revisão canônica, proteção contra replay e os validadores existentes. Se surgir outro pré-requisito, comprová-lo antes de liberar.

Em paralelo, meça os tempos de STS/CURRENT, túnel, chave, SSH e boot/execução Rails e corrija o gargalo demonstrado. Não aumente CPU/TTL ou acrescente retries/cache sem evidência. O handoff aponta os arquivos exatos e a configuração transitória que precisa ser consolidada.

Use subagentes reais com funções distintas: captura/contrato, transporte/latência e revisão independente. Informe nomes e escopos, mas mantenha um único executor de produção e evite dois agentes alterando o mesmo arquivo. Não lance mais uma rodada apenas para repetir os pareceres já concluídos.

Não misture os seis deltas não aprovados da worktree antiga `995-operator-recovery`; seus paths/hashes estão no manifesto. Não apague perfil ou lock vivo, não copie cookies/credenciais para logs e não refaça DNS/Tailscale/IAM/Redis/n8n sem causa demonstrada. Recusas de ferramenta não provam queda do servidor: use seu acesso normal autorizado, respeitando controles; se houver bloqueio real, peça uma única ação humana específica, com o comando e resultado esperado, sem contornar a recusa.

Atualize README/runbooks/auditoria quando necessário e os sete campos do Project: Projeto, Status, Tipo, Prioridade, Risco, Próxima ação, Ambiente. Siga Issue → Branch → PR → Project → revisão → aprovação → fila → confirmação MERGED → deploy/rollback. Não faça bypass nem confunda deploy AWS com instalação do runtime VPS.

Aceite: sessão legítima registrada no Chat2You, duas renovações naturais, serviços e recursos persistentes após reinício e conexão/teste de uma conta autorizada pelo painel. Priorize Autonom.ia; depois homologue Hub2You separadamente. Só peça login/2FA se o perfil realmente exigir. Comece mostrando o que confirmou e o menor próximo passo executável; depois avance até o uso real ou um bloqueio verificável, sem tratar teste simulado ou Chrome aberto como conclusão.
