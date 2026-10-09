# Repasse operacional — Instagram Tester #910 / PR #913

Atualizado em 03/10/2026, após o pedido de ativação geral sem novo custo.
Este documento substitui os estados de prontidão dos relatórios anteriores;
eles preservam evidências históricas, não descrevem a operação atual.

## Estado inequívoco

- PR correta: [#913](https://github.com/autonom-ia2/chat/pull/913), **MERGED**.
- SHA publicado: `2d493fe4a77aeb0912d2d8f27d6f802766cd465f`.
- Merge: 03/10/2026 21:12:22 BRT; branch final antes do merge:
  `952d7448d6f2a61480f57d0e96bbac835b9de7a4`, com **22/22 checks SUCCESS**.
- Deploy [Hub2You 37164225865](https://github.com/autonom-ia2/chat/actions/runs/37164225865): **SUCCESS**.
- Deploy [Autonom.ia 37164225880](https://github.com/autonom-ia2/chat/actions/runs/37164225880): **SUCCESS**.
- **Tela ativada nas duas stacks, mesmo indisponível, por autorização expressa do Rodrigo.**
- **Busca/convites/renovação NÃO estão operacionais/homologados.**
- Escopo solicitado atualmente: todas as contas atuais das duas stacks,
  não somente o antigo piloto Hub2You/18.
- Allowlist SSM: Hub2You **15 contas**, SecureString **v6**; Autonom.ia
  **7 contas**, SecureString **v5**. Essa lista não inclui automaticamente contas futuras.
- Coordenador: configurado somente no Hub2You, usando seu Redis local com TLS.
  Não existe conexão comum operacional comprovada entre as stacks.
- Supervisor de sessão: preparado, **não iniciado/não instalado como LaunchAgent**.
- Publicação/renovação da sessão: **não homologadas; transporte publisher falhou**.
- Novo custo para coordenador/infra: **recusado expressamente pelo Rodrigo**.
  Nenhum cache, peering ou novo custo de infraestrutura foi criado.

Rodrigo explicitou depois: ligar a tela mesmo com erro e sem custo novo.
A ativação foi aplicada preservando as guardas de disponibilidade; não foi
forçada sessão válida nem removida exigência de coordenador. A indisponibilidade
do onboarding não equivale a entrega funcional. O risco visual do CTA legado
foi comunicado antes e a exposição com erro foi explicitamente autorizada.

## Repositório e mudanças preservadas

Worktree: `/Users/rodrigosilva/dev/worktrees/chat2you/910-instagram-tester-onboarding`.
Branch local atual: `codex/910-instagram-publisher-ssm-query`.
HEAD: mesmo SHA publicado `2d493fe4a77aeb0912d2d8f27d6f802766cd465f`.

Alterações locais **não commitadas, não enviadas, não deployadas**:

1. `scripts/instagram_testers/runtime/publisher-tunnel.mjs`: correção da raiz
   da consulta AWS e tentativa de manter stdin do túnel aberto.
2. `tests/instagram_testers/runtime-publisher.test.mjs`: mock fiel ao envelope
   AWS e relógio limitado para reproduzir a consulta inválida.
3. `docs/audit/instagram-tester-live-preparation-910.md`: histórico complementar.
4. Este repasse e avisos de atualização nos relatórios/runbook.

O checkout principal tem trabalho independente: não resetar, sobrescrever,
limpar nem copiar repositórios entre os Macs. A PR #913 já foi mergeada;
uma correção futura requer sua própria revisão/PR e validação.

## Achados que impedem ligar com segurança

### P1 — consulta do publisher não corresponde à resposta AWS

`scripts/instagram_testers/runtime/publisher-tunnel.mjs:318` usava
`Invocations[0]`; a resposta de `list-command-invocations` usa
`CommandInvocations[0].CommandPlugins[0].Output`.
O modelo oficial do serviço boto3 e a documentação local da CLI confirmaram
essa estrutura. A consulta original retorna null e termina por timeout.
O teste antigo retornava um objeto já projetado, mascarando o defeito.

A correção local troca a raiz para `CommandInvocations`. Com o mock novo,
o código original falhou e a correção passou. Isso resolve esse defeito
específico; **não resolveu o transporte completo**.

### P1 — túnel SSM encerra antes da execução SSH

Teste real restrito à operação read-only `version`, sem Meta, observou:
túnel iniciado, processo AWS terminou com exit 0, consulta da chave pública
terminou, SSH falhou com exit 255 / Connection refused.
Tempos observados: aproximadamente 1,9s / 4,1s / 5,9s / 5,9s.

Tentativa local: mudar stdin do túnel de `ignore` para `pipe`.
**Hipótese não confirmada**; os testes reais posteriores continuaram
falhando com exit 2 tanto no Hub2You quanto na Autonom.ia.
O comentário local que atribui a falha a EOF não é diagnóstico comprovado.
Revisão independente também apontou ausência de tratamento de encerramento
prematuro do processo em `publisher-tunnel.mjs:482-509,589-595`.

Nenhuma sessão foi publicada ou invalidada. A existência/validade de uma
sessão armazenada não foi confirmada: `version` falhou no transporte.
Um valor false produzido pelo wrapper no erro não prova ausência de sessão.

### P1 — ligar flag com available=false remove o acesso visual ao OAuth legado

`app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Instagram.vue:17-21,63-70`
escolhe a tela assistida pela flag global. `useInstagramTester.js:119-137`
só retorna à tela antiga quando `enabled=false`.
`instagram/TesterOnboarding.vue:283-302` mostra ajuda e retry quando indisponível,
sem CTA de OAuth legado.

No backend, `configuration.rb:15-26,39-41,116-126` permite
`enabled=true, available=false`. Autonom.ia sem coordenação já cai nessa condição.
Ligar a flag assim não entrega busca/convite; retira o botão existente.
Revisão independente de segurança confirmou essa regressão operacional.
Rodrigo autorizou expressamente mostrar a tela mesmo com esse erro; ativada.
Não mudar disponibilidade para true artificialmente nem remover guardas.

## O que foi realmente entregue/verificado

- Fluxo de código busca → seleção → convite → aceite → Instagram Login,
  validação de seleção, namespace por instalação, permissões e limitações.
- OAuth/reautorização originais preservados no código. O refresh OAuth
  **não renova cookies administrativos**. OAuth legado não usa proxy administrativo.
- Gallery com componente real e API sintética: 56 cenários, 60 capturas,
  desktop/mobile/light/dark. Mockups aprovados pelo Rodrigo não são homologação real.
- Suítes Node sintéticas: 47/47 após a correção da consulta, **antes** da
  tentativa posterior de stdin. ESLint dos dois arquivos e diff check passaram
  nessa etapa. Não reportar validação completa após a última mudança de stdin.
- CI completo do SHA 952: 22/22. Shard Ruby 0: 2.311 exemplos, zero falhas,
  duas pendências preexistentes.
- Ajuste mínimo de fixture já mergeado:
  `spec/requests/relationships/legacy_interleaving_spec.rb:17`, limpeza síncrona
  dos contatos antes de destruir conta. Reprodução isolada: 46 exemplos/12 falhas
  antes, 46/0 depois. Não houve implementação de SMS nem mudança de produto WhatsApp.
- Testes Ruby locais mais amplos tiveram falhas de dependência/Enterprise;
  não confundir CI aprovado com todos os comandos locais aprovados.
- Deploy e saúde de infraestrutura são evidências distintas de homologação Meta.
- Nenhum convite, aceite, OAuth completo, callback, webhook ou DM real homologado
  neste trabalho. Jornada `@placementseg` / conta 18 ficou reservada ao Rodrigo.

## Configuração operacional aplicada

- Overlay separado `/chatwoot/prod/instagram-tester-env`, sem alterar parâmetro
  base `/chatwoot/prod/env`, chaves de criptografia ou credenciais OAuth existentes.
- Permissão EC2 de leitura restrita aos dois parâmetros SSM necessários por stack;
  backups privados de política preservados. Não houve apply amplo de Terraform.
- Chave pública dedicada em `/chatwoot/prod/instagram-tester-publisher-public-key`.
  Installer presente nos novos hosts; isso não prova SSH publisher funcional.
- Transporte planejado por SSM para SSH loopback/forced command; sem abrir SSH
  público, sem shell irrestrito e sem grupo Docker para o usuário publisher.
- Allowlist de todas as contas atuais atualizada no SSM com flag true e carregada
  nos containers web/worker, confirmada: Hub 15, Autonom.ia 7. Nenhuma credencial
  ou variável fora do overlay foi alterada.

Hosts após deploy:

| Stack | Instância atual | IP atual | Instância anterior |
|---|---|---|---|
| Hub2You | i-0e4ca0156a3bddd20 | 44.222.141.62 | i-0ec2bc00a4b77bb2b |
| Autonom.ia | i-0a5ddb0bd01098d88 | 52.91.227.60 | i-09942b2ff86c887b5 |

Ponto de rollback de código pré-release: `42e9559bbc626cd2cefb0c415c06f51fa15a89bd`.
Não usar como atual o SHA 0abffb3 de relatórios históricos. Antes de rollback,
confirmar parâmetros blue-green, targets e estado dos hosts; não executado aqui.

## Webshare: concluído e pendente

Rodrigo aprovou adicional recorrente de até US$5/mês: Unlimited IP Authorizations
foi ativado. Plano Static Residential ficou US$11/mês, de US$6; outro plano
Proxy Server foi preservado. Não foram lidas/criadas credenciais de proxy/API.

Autorizações salvas anteriormente: IPs antigos das stacks, gestor e o IP já
existente do n8n preservado. **IPs atuais 44.222.141.62 e 52.91.227.60 ainda não
foram autorizados/verificados.** Não presumir que a troca blue-green é coberta.
Proxy Direct por IP: `45.58.229.84:5256`. GET HTTPS público passou no M4, M2
e antigos hosts/containers; não foi teste autenticado Meta.

Tentativa de acesso à console atual: navegador conectado indisponível,
inventário sem browser e janela Chrome sem acesso. Nenhuma API alternativa,
CDP ou contorno foi usado. Limitação da ferramenta não comprova falha do Webshare.
Não houve acesso SSH ao n8n. Há política de substituição automática de endpoint
indisponível; eventual mudança exige conferir/reconfigurar o vínculo aprovado.

## Runtime privado e login humano

M4: `/Users/rodrigosilva/Library/Application Support/InstagramTester`.
M2: `/Users/rodrigovictor/Library/Application Support/InstagramTester`.
Perfis novos privados, diretórios 700, arquivos sensíveis 600, FileVault ativo,
Playwright 1.59.1. Não copiar nem abrir conteúdo de perfis/chaves para o repasse.

M4 contém supervisor preparado, wrapper, chave publisher e configuração privada.
`prepared/source-revision.txt` é 042; runtime operacional contém código anterior,
**não recebeu as correções locais pendentes do publisher**. LaunchAgent não instalado.
M2 contém inicializador de login e perfil próprio; não tem publisher/AWS/supervisor.
Login no M2 não publica automaticamente a sessão no M4 ou nas stacks.

Rodrigo informou login e forneceu captura autenticada. Janelas próprias dos
inicializadores foram encerradas com SIGTERM limitado aos filhos correspondentes.
M4/M2: zero inicializadores/processos do perfil e nenhum lock remanescente.
Chrome pessoal não foi selecionado. Cookies, senhas e HARs não foram lidos/expostos.

## Plano mínimo para quem continuar

1. Ler AGENTS.md, este repasse e diff local; preservar trabalho e limites.
2. Corrigir/revisar o transporte publisher; começar por `version` read-only,
   sem Meta nem manipulação de sessão. Testar processo SSM encerrando cedo.
3. Autorizar/verificar os IPs dos hosts atuais no Webshare pelo meio permitido.
4. Resolver coordenação comum usando infraestrutura existente **somente se**
   isolamento, acesso restrito e ausência de novo custo forem comprovados e
   aprovados. Não compartilhar credencial raiz dos Redis de aplicação, mudar
   AUTH/ACL nem assumir que um cache de outro projeto é dedicado/disponível.
   Se não houver opção segura sem custo, declarar esse bloqueio.
5. Concluir publicação/renovação administrativa pelo processo legítimo permitido.
   **Bloqueio anterior de Roles RPC não pode ser contornado por host/proxy/agente.**
   Login humano não autoriza ignorar esse bloqueio nem ler cookies/HARs.
6. Flags e allowlists já estão carregadas por ordem expressa. Concluir
   disponibilidade real nas duas stacks e a jornada que Rodrigo executar.
   Corrigir/revisar o fallback visual sem ampliar o escopo de OAuth.
7. Atualizar Issue #910/Project com resultado; não declarar pronto com flag,
   mockup, login humano, fila ou CI como única evidência.

## Veredito atual

Código da PR #913 mergeado e publicado; **tela ligada em todas as contas atuais**
nas duas stacks por autorização expressa, mesmo com erro. Automação completa
continua não operacional. Não há autorização de novo custo. Não declarar
ativação da tela, merge/deploy ou CI como prova do fluxo funcionando.

## Ativação aplicada e incidente de disponibilidade

Comandos SSM de ativação, ambos **Success / rc0**:

- Hub: `6285c3bd-b213-4cab-95d0-41d28eeebfe3`, overlay v6, web/worker active,
  flag true e 15 contas nos dois containers.
- Autonom.ia: `e214689d-dbcd-41e7-9ece-fb07d227c671`, overlay v5, web/worker active,
  flag true e 7 contas nos dois containers.

Foi aplicado somente o overlay validado com suas 13 chaves permitidas, de forma
atômica, preservando KeyId e valores existentes. Base env, secrets e OAuth intactos.
Não houve sessão/Meta, troca de imagem, novo host, serviço, cache ou novo custo.
O código/imagen continua 2d493fe4a77aeb0912d2d8f27d6f802766cd465f.

**Erro operacional cometido:** reinício direto de web e worker nos hosts atuais
para carregar ENV; web precisou subir e houve interrupção pública. Rodrigo
forneceu captura 502 Bad Gateway. A alteração deveria ter evitado interrupção
usando procedimento de publicação adequado; não atribuir o 502 ao cliente.
A duração exata e o impacto em usuários não foram medidos.

Não foi feito segundo reinício nem rollback após o relato: os dois comandos já
haviam terminado com saúde local validada. Verificação pública independente
posterior: login Hub/Autonom.ia **HTTP200**, raiz **HTTP302**, rota Instagram
Hub18 **HTTP302** sem autenticação; targets das duas stacks **healthy**.
302 da rota protegida não prova tela autenticada nem jornada Meta.

Reversão da exposição: voltar flag para false no overlay mantendo as demais
chaves e carregar pelo procedimento sem interrupção; a mudança SSM sozinha
não altera containers existentes. Não executar novo reinício direto como atalho.
