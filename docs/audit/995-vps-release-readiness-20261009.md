# Issue 995 — publicação VPS e teste autorizado na conta 16

Rodrigo autorizou liberar para testar a conta 16 da Hub2You, com o perfil @hub2you.ai. Esta decisão substitui o HOLD de publicação desta rodada; gates de CI, revisão e fila permanecem obrigatórios. A conta 18 e sua conexão existente devem ser preservadas.

## Provas antes da publicação

A revisão fb32568b52 tem 24 checks aprovados; os dois cancelados foram substituídos por checks aprovados e os dois skipped são da funcionalidade de e-mail fora do escopo. CI Instagram passou com 404 testes Node, 148 testes Python de contratos, 38 casos do painel e 72 do wizard. Chrome Linux passou nas rotas, falhas de UI, leituras atuais com página reutilizada, lifecycle e proxy. O piloto real anterior atingiu os seis limites históricos /10 no servidor; a métrica do cliente permanece separada.

Leitura atual somente de dados autorizados: uma caixa e um canal na conta 18, sem marca de reautorização e com vencimento futuro do token. Isso não prova entrega de mensagens nem reconexão atual. Conta 16: Instagram habilitado, assistido desligado e fora da allowlist vigente. VPS: oito serviços ativos, CURRENT 61f20cfd, publishers com CPU efetiva 200%, Node privado verificado. AWS Hub2You: web e worker em 28e1e0ac.

## Correções finais encontradas no preflight

1. Os gatilhos genéricos iniciariam ambos os deploys AWS para este patch exclusivo da VPS. A exclusão específica agora cobre somente session-manager.mjs, browser-operations.mjs e suas duas árvores de testes. Aplicação, publisher Ruby, wrappers e módulos compartilhados continuam acionando AWS; push misto também. Doze testes passaram com matcher por segmentos e casos de fronteira; a política anterior falha em 15 verificações. Revisão independente GREEN. O corpo de deploy, workflow_dispatch e rollback não muda. A fila pode agrupar outros PRs: um grupo com alteração da aplicação continuará acionando o deploy.
2. O candidato alterava o template publisher de 50% para 200%. O installer rejeita templates diferentes entre candidato, CURRENT e /etc/systemd. A linha foi restaurada para 50%; os quatro templates coincidem com a instalação anterior. Preservar os dois overrides existentes de 200% com SHA 41c6db5c35846b239a0da96950bc1e599703b0b1aabbb274a6f99f95d168ea43. Não remover esses overrides nem relaxar o installer. O piloto comprovou CPU efetiva 200%, sem teste de runtime 50%.

Este plano vigente substitui somente as instruções antigas de remover os overrides/voltar a 50% nos relatórios históricos de runtime e PR1155. Os hashes e fatos históricos desses relatórios permanecem históricos.

## Sequência autorizada

1. Concluir CI da revisão final e conferir fontes executáveis iguais às medidas. Entrar pela fila nativa com SHA exato; somente MERGED é publicação no Git. Nada de bypass administrativo, rebase ou force push.
2. Preparar o release VPS do SHA efetivamente mergeado, com fontes verificadas e dependências do lock: SSM SDK 3.967.0, noVNC 1.7.0, jose 6.2.12, Playwright 1.59.1 e ws 8.22.0. Pacote Linux x64, sem credenciais/perfis, extraído root-owned em ancestral privado; preservar Node24.21.0 e os binds existentes.
3. Acrescentar apenas a conta16 à allowlist da Hub2You no parâmetro ENV, resultando em 16,18, preservando todas as demais linhas. Publicar uma green Hub2You pelo workflow manual existente, confirmar wrapper/saúde/CURRENT e ENV efetiva em web/worker. A mudança de conta exige este deploy de configuração: não há alteração equivalente na Autonom.ia. Não duplicar um deploy automático caso a fila tenha incluído outra mudança da aplicação.
4. Com filas vazias e checkpoint de restauração, parar as units pelo procedimento já validado, aguardar liberação dos perfis/cgroups e executar o installer inativo com o bind Node privado. Conferir os quatro templates, overrides, pares/env, owners, perfis, CURRENT e manifesto. Iniciar display/gateway, depois publisher e manager; conferir bootstrap/renovação, CPU efetiva200%, saúde e fila. Não apagar cookies ou locks Chrome.
5. Rodrigo informou que habilitou a conta16 no super admin; confirmar a persistência dessa alteração e preservá-la. Habilitar somente instagram_assisted_onboarding caso a leitura ainda indique false, preservando todos os demais features. Confirmar configuration.enabled=true/available=true pela API autenticada da conta16 e preservar a conta18. Nenhum convite ou DM é enviado para habilitar a conta.
6. Entregar o painel da conta16 ao Rodrigo para selecionar @hub2you.ai e testar. O aceite precisa seguir diretamente o OAuth original; login/2FA e concessão Meta pertencem ao dono do perfil. Não afirmar reconexão real sem callback concluído e canal/caixa verificados.

## Rollback

Se o runtime falhar, parar units e processos próprios, retornar CURRENT via compare-and-swap para 61f20cfd107361a431fda51f02cace751cc4978d, preservar os mesmos templates, overrides200%, Node e perfis, retomar serviços e confirmar fila/saúde. Não reenviar convite de resultado incerto.

Se a liberação da conta16 falhar, restaurar somente o feature anterior dela. Reverter a allowlist somente à linha anterior registrada de forma privada; se necessário reverter a green Hub2You pela rotina blue-green aprovada, nunca reiniciar diretamente web/worker. Não afetar conta18, Autonom.ia, outras flags ou dados.

A Issue995 continua aberta até a aceitação funcional e reconexão real. CI e leitura de estado não substituem um novo grant Meta.
