# Issue #995 / PR #1129 — publicação das operações no Chrome da VPS

Plano preparado para revisão e aprovação. Não registra merge, deploy, mudança de ENV, instalação permanente ou convite real.

## Resultado e alcance

Busca, consulta de tester e convite passam pelo Chrome real da VPS, usando o perfil isolado já autenticado e o proxy da respectiva stack. Depois do status accepted observado pelo Chrome, o backend prepara a URL OAuth com o vínculo e nonce existentes. O painel aguarda o resultado sem copiar cookies para o backend. O callback OAuth e a reconexão de uma caixa existente mantêm o caminho atual. Recuperar a sessão administrativa da Meta não equivale a reconectar uma caixa Instagram.

A ativação é opcional: `INSTAGRAM_TESTER_BROWSER_OPERATIONS_ENABLED` ausente ou `false` mantém o comportamento atual. Só vale junto dos gates existentes e de `INSTAGRAM_TESTER_SESSION_SOURCE=managed`. Não muda banco, IAM, DNS, proxy, quotas, n8n ou perfil pessoal do Chrome.

Escopo do piloto a liberar: Hub2You, conta 18, @placementseg, alvo já autorizado para teste. A ativação em produção ainda exige a aprovação abaixo. Autonom.ia, conta 1, @autonomia.ia_: o nome exato não retornou candidato na Meta; confirmar o @ antes do aceite nessa stack. Nenhuma conta aproximada pode substituir o alvo. Envio de DM real exige destinatário autorizado antes de executar.

## Evidência antes da aprovação

1. Congelar o head funcional revisado e registrar SHA, checks, testes efetivamente executados e limitações. Issue → branch → PR → Project → revisão. Não usar bypass/admin.
2. POC22 já comprovou candidato único, seleção nativa, token novo no diálogo e uma requisição com 19 campos exatos. O POST foi abortado: isso não prova convite aplicado, resposta da Meta, OAuth ou conexão da caixa.
3. Revisão deve liberar os caminhos de permissão fresca, claim único, marcador de resultado incerto, prevenção de duplicidade, prazo e cleanup. Os erros desconhecidos não autorizam reenvio.
4. Obter aprovação explícita de Rodrigo para fila/merge, os dois deploys AWS, instalação do pacote VPS e ativação do piloto Hub2You. A aprovação deve indicar o head revisado. Autonom.ia recebe código com flag desligada até resolver o alvo.

## Publicação após aprovação

1. Revalidar main e o head da PR, checks obrigatórios e alterações externas desde a revisão. Se houver conflito material, voltar à revisão. Entrar na fila normal e comprovar mergeCommit pelo GitHub.
2. A mudança de código em main dispara os dois workflows blue-green. Acompanhar os runs automáticos, sem disparar deploy manual duplicado. Verificar por stack o SHA dentro do container, CURRENT, saúde, transporte publisher e previous target/instance. Workflow verde sozinho não comprova funcionalidade Instagram.
3. Manter a flag nova desligada durante deploy e preparação VPS. Confirmar os publishers AWS com o novo ACK estrito antes da ativação. Não reiniciar web/worker diretamente para carregar ENV: usar o caminho blue-green aprovado.
4. Preparar release VPS imutável do mergeCommit com manifesto/checksum e dependências locked existentes. Revalidar oito units, estado enabled, quotas/limites/drop-ins, release atual, nenhum login humano em andamento e exclusividade de ambos os perfis. O último baseline observado foi VPS `2cc6b4fb6e275e26c04ae126c06ac1b4f0b63b26` e ambas AWS `caca5eae44705d6d9449d00b005fae67b2da454c` (leitura22:28UTC, flagnovaunset); revalidar, não presumir atualidade.
5. O installer exige as oito units Instagram inativas. Drenar apenas `instagram-vps-{display,gateway,publisher,manager}@{hub2you,autonomia}.service`, verificar processos/locks e instalar. Nunca apagar lock vivo ou perfil. Preservar n8n, Traefik, Redis e serviços alheios. Retomar exatamente o conjunto anteriormente ativo na ordem display/gateway → publisher → manager.
6. Confirmar release selecionada, bootstrap pelo usuário/socket reais, perfis exclusivos, saúde de ambas as sessões, oito estados e todos os recursos preservados. Nenhum reboot da VPS está incluído.
7. Antes de ativar, reconfirmar Redis Alfred isolado entre as stacks e allowlist de uma conta por stack. A inspeção por fingerprint mostrou servidores diferentes; esse é um pré-requisito desta fila. Se Redis passar a ser compartilhado, não ativar sem corrigir afinidade. Congelar mudanças de metadata/app/admin/business/doc/proxy durante a janela.
8. Ativar primeiro o manager Hub2You e o backend Hub2You para conta 18 pelo caminho de configuração aprovado, preservando a sessão. Autonom.ia permanece desligada. Revalidar runtime, flag literal, revisão do bootstrap e allowlist; não registrar valores de credenciais.

## Aceite funcional

No painel autorizado da conta 18: busca exata → status fresco → convite somente se ausente → aceitação pelo titular se a Meta solicitar → status accepted → OAuth → caixa conectada. Novo login/2FA só quando a Meta realmente pedir. Nunca pedir senha/código no chat.

Comprovar consulta repetida sem POST duplicado, cancelamento/prazo sem operações sobrepostas e erro legível quando a sessão exige intervenção. A perda de resposta após início do POST deve manter resultado incerto; não repetir automaticamente. O status fresco pending/accepted pode reconciliar o estado pelo fluxo autorizado.

Verificar separadamente recuperação da sessão administrativa e reconexão da caixa existente pelo fluxo do painel. Registrar estado antes/depois sem dados de cliente. Reinício controlado apenas das units Instagram verifica persistência do perfil; não substitui duas renovações naturais já comprovadas na fase anterior nem prova reboot do host. Teste de mensagens só com destinatário explicitamente autorizado.

Autonom.ia exige seus próprios recibos após confirmação do @; não herda o aceite Hub2You. Não encerrar #995 antes dos aceites de conexão/reconexão pendentes.

## Reversão

Guardar antes da janela o SHA/release VPS, current, estados enabled/ativos, drop-ins e limites, além de CURRENT/previous target/instance AWS. Preservar recibos sem secrets.

Se o piloto falhar, desligar a flag nova pelo caminho aprovado e aguardar/drenar a operação. Não limpar marcador unknown para forçar repetição. Se o runtime falhar, drenar apenas as units Instagram, restaurar current atomicamente para a release anterior verificada e retomar o conjunto anterior, com perfis/locks exclusivos. Manter pacote novo e evidências; não excluir cookies, chaves, metadata, Redis ou dados.

Se houver regressão no backend, usar action=rollback/confirm_production=true do workflow blue-green da stack, após verificar saúde do previous target. Confirmar SHA e saúde depois. Backend e VPS têm reversões distintas; não executar restart manual web/worker, alterar DNS/IAM ou restaurar banco.
