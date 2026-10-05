# Runtime Instagram na VPS — #995

A instalação do runtime e a publicação HTTPS privada foram aprovadas por Rodrigo
no escopo da [issue #995](https://github.com/autonom-ia2/chat/issues/995).
A aprovação não comprova execução ou homologação: registrar cada etapa concluída
e os bloqueios reais antes de avançar. O onboarding assistido permanece OFF até
a aceitação operacional. IAM/SSM, credenciais e login Meta seguem o escopo de
aprovação correspondente, sem ampliar permissões para contornar bloqueios.

## Estado da execução

A [auditoria operacional de 05/10](../audit/995-vps-runtime-operations-20261005.md)
registra o que foi instalado, publicado e verificado de fato, com os gates ainda
pendentes. Os comandos deste runbook são procedimentos; não são recibos de aceite.
As auditorias de preparação mantêm sua fotografia histórica e apontam para esse
registro de continuidade.

## Pacote e requisitos

Usar exclusivamente `scripts/instagram_testers/runtime/vps/`.
Os scripts/unidades anteriores em `runtime/` (Xvfb/x11vnc/websockify e TCP VNC)
não integram este pacote e não devem ser usados para ativar o contrato #995.
Foram preservados para o coordenador reconciliar o diff.

Ler o [contrato Linux](../../scripts/instagram_testers/runtime/vps/docs/requirements.md)
e a [identidade/IAM](../../scripts/instagram_testers/runtime/vps/iam/README.md).
O pacote usa seis usuários de serviço Linux com UID/GID primários exclusivos:
browsers `ig-hub2you`/`ig-autonomia`, publishers `igpub-hub2you`/`igpub-autonomia`
e gateways `iggw-hub2you`/`iggw-autonomia`. Há mais dois grupos dedicados,
`igview-hub2you`/`igview-autonomia`, com GIDs exclusivos para viewer.
Cada stack tem perfil privado, publisher com home separado, TigerVNC por socket
Unix e gateway Node autenticado. Nenhum Mac participa do
caminho operacional planejado. n8n, Traefik, Redis e demais serviços não são
instalados, alterados nem reiniciados pelo instalador.

## Preparação e gates operacionais

1. Review de INFRA e integração com os donos de Rails/gateway/browser/waiter.
   Confirmar opt-in do documento SSM, marker/deadline e encerramento real do Chrome.
   Não usar apenas botão visível, CI verde ou serviço ativo como prova funcional.
2. Preparar artefato sem segredos, com SHA aprovado e checksum registrado. Incluir
   os scripts do runtime e o pacote VPS completo. Preparar `node_modules` com o
   lockfile congelado do pacote VPS na etapa de empacotamento Linux; não copiar
   `node_modules` do Mac nem `.aws`, `.env`, perfis ou sessões pessoais.
3. Stage de deploy root-owned em diretório root-owned sem escrita por outros,
   por exemplo `/opt/instagram-meta-staging/RELEASE_SHA`; o instalador recusa
   checkout pessoal, stage em `/tmp`, symlinks e artefato gravável por terceiros.
   Os ancestrais existentes da release (`/`, `/opt`, `/opt/instagram-meta` e
   `releases`) também precisam ser diretórios root-owned, sem escrita por terceiros
   e com travessia para os usuários `ig-*` (bit de execução para outros, como 0755
   ou 0711). Um ancestral 0700/0750 é recusado no preflight antes de qualquer escrita;
   o instalador não corrige permissões existentes automaticamente. Essa exigência
   não muda o 0700 dos perfis nem dos diretórios privados em `/etc/instagram-meta`.
   Não há instalação de pacotes/download em `install.py`.
4. Propor identidade AWS permanente de serviço sem access keys pessoais, trust
   policy e helper de credenciais temporárias, um perfil restrito por stack.
   Preencher `REQUIRED_ACCOUNT_ID`, `REQUIRED_STACK_INSTANCE_NAME_PATTERN` e
   `REQUIRED_APPROVED_PRINCIPAL_SESSION_ARN_PATTERN` com valores aprovados.
   A policy usa `instance/*` na conta/região exatas com Project=chatwoot-autonomia,
   Environment=prod, ManagedBy=github-actions e Name por stack:
   `chatwoot-hub2you-prod-ec2-green-*` ou `chatwoot-autonomia-prod-ec2-green-*`.
   Conferir as tags no destino real; os workflows são evidência da convenção,
   não da configuração aplicada. Não há instance-id fixo a atualizar no blue/green
   enquanto o seletor permanecer igual. CURRENT escolhe o destino do publisher;
   IAM autoriza todas as instâncias que casam com o seletor, inclusive anteriores.
   Registrar esse alcance e revisar/aprovar qualquer mudança do seletor.
5. Registrar estado prévio dos serviços e Serve, release `current` e permissões
   dos paths. Confirmar certificado HTTPS, ACL privada, suporte Unix do Xvnc,
   isolamento systemd e sandbox Chrome na distribuição instalada. Não alterar
   sysctl/AppArmor para fazer passar sem aprovação específica.
6. Registrar plano de rollback e janela de operação. Na primeira instalação não
   existe release anterior: o rollback é parar somente as unidades novas e
   remover somente os dois mounts Serve, preservando perfil, chaves e nonces.

## Instalação autorizada

As variáveis abaixo são caminhos/SHA aprovados, nunca segredos. Não executar
este bloco como parte dos testes. O instalador só aceita Linux/root e serviços
Instagram VPS inativos; não contém `enable`, `start`, `stop` ou `restart`.

```sh
sudo /usr/bin/python3 "$APPROVED_ARTIFACT/scripts/instagram_testers/runtime/vps/install/install.py" \
  "$APPROVED_ARTIFACT" "$APPROVED_RELEASE_SHA"
```

Instala release imutável em `/opt/instagram-meta/releases/SHA`, unidades em
`/etc/systemd/system` e usuários/directórios privados. Faz somente
`systemctl daemon-reload` e troca `current` depois de sucesso. Não inicia nem
habilita unidades, não provisiona env, chave SSH, AWS ou proxy. Perfis existentes
não sofrem chmod/chown recursivos, limpeza ou migração. Reinstalar o mesmo SHA é
recusado, assim como unidade existente com conteúdo diferente; inspecionar a
instalação incompleta em vez de apagar arquivos e tentar de novo.

O responsável autorizado deve provisionar por stack:

- `/etc/instagram-meta/STACK/{display,manager,gateway,publisher}.env`: root:root 0600,
  diretório root:root 0700. Seguir os exemplos `env/*.env.example`, substituir
  placeholders por valores aprovados sem imprimir/capturar os arquivos.
- `/var/lib/instagram-publisher-STACK/publisher/id_ed25519`: chave exclusiva do publisher,
  usuário `igpub-STACK`, 0600. Provisionamento de auth aprovado separadamente;
  associação ao forced publisher existente não é feita aqui.
- `/var/lib/instagram-publisher-STACK/publisher/aws-config`: usuário `igpub-STACK`, 0600,
  exatamente o perfil da stack, região e `credential_process`. Helper absoluto,
  executável, root-owned e sem escrita por outros, incluindo seus ancestrais.
  Não criar arquivo `credentials`; não usar perfil de pessoa/SSO interativo.
- Documento `ChatwootInstagramPublisherHostKey` e IAM mínimo, por identidade
  administrativa aprovada. Opt-in só no `publisher.env` VPS; legado fora do VPS
  deve continuar preservado. A policy entregue não permite o documento legado.
- Chaves de assinatura diferentes por bytes entre stacks, hex >=64 caracteres
  e tamanho par. Cada Rails recebe a sua chave correspondente, stack e URL HTTPS;
  gateway recebe somente sua chave e issuer. O instalador `install.py` não gera
  chaves; elas são criadas pelo provisionamento autorizado e privado.

### Persistência da configuração Rails

Usar o `SecureString` específico existente `/chatwoot/prod/instagram-tester-env`
de cada conta, na região `us-east-1`. Antes de gravar as três chaves, publicar as
allowlists atualizadas dos dois workflows blue/green e confirmar que nenhum
deploy/bootstrap com allowlist antiga continua em execução.

| Stack | Conta AWS | Parâmetro específico |
| --- | --- | --- |
| hub2you | `354307071110` | `/chatwoot/prod/instagram-tester-env` |
| autonomia | `140023375763` | `/chatwoot/prod/instagram-tester-env` |

Registrar estas três entradas adicionais, preservando literalmente todas as
entradas existentes e os metadados do parâmetro:

| Variável Rails | Valor por stack |
| --- | --- |
| `INSTAGRAM_TESTER_RUNTIME_STACK` | `hub2you` ou `autonomia`, conforme a conta AWS |
| `INSTAGRAM_TESTER_OPERATOR_BROWSER_URL` | `https://srv707880-claudete.tail0c0b18.ts.net/STACK/`, substituindo `STACK` pelo nome exato e preservando a barra final |
| `INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY` | A chave exclusiva da mesma stack provisionada em `gateway.env`; nunca registrar o valor |

O bootstrap já lê esse overlay, valida seus nomes e instala o arquivo local
`/opt/chatwoot/instagram-tester.env` com modo 0600; web, worker e preflight o
carregam. A mudança na allowlist acrescenta somente esses três nomes, sem prefixo
genérico ou aceite de outras chaves. O overlay antigo continua válido depois
da atualização do código. Um leitor antigo recusa as três entradas com
`instagram_tester_env_keys_invalid`, por isso a ordem da publicação é obrigatória.

A escolha substitui o plano inicial de usar `/chatwoot/prod/env`: a medição real
do Hub em 05/10 encontrou 4.060 bytes no principal Standard, insuficientes para
mais 242 bytes. Os overlays existentes tinham 699 e 522 bytes e comportam a
adição. Não duplicar as três entradas no principal, remover variáveis antigas
ou promover o Tier para contornar o tamanho.

O Rails deriva `iss` da origem de `FRONTEND_URL`, que continua sendo lida no
parâmetro principal; não lê `INSTAGRAM_TESTER_OPERATOR_ISSUER`. Preencher essa
variável apenas no `gateway.env`, com a origem HTTPS exata do FRONTEND_URL
efetivo da mesma stack, sem caminho nem barra final. Conferir a origem real;
Autonomia usa `https://agents.autonomia.site` e Hub `https://chat.hub2you.ai`
na operação registrada, mas o executor deve revalidá-las.

Os workflows consultados apenas leem o overlay no SSM. A gravação deve ainda
validar versão, conteúdo integral e metadados imediatamente antes e depois,
com backup privado 0600; SSM não tem compare-and-swap. O rollback restaura
somente se a versão e o digest aplicados continuam iguais, sem depender de
acesso à VPS. Qualquer alteração concorrente exige reconciliação.

Usar uma publicação blue/green autorizada da versão atual para carregar as
chaves nos containers; mudar SSM não altera processos já em execução. Validar
na green os nomes/valores não secretos e a presença válida da chave, sem
imprimir env, hash da chave, JWT ou cookies. Comparar a chave com a do gateway
em memória e emitir apenas o resultado booleano.
Manter `INSTAGRAM_TESTER_AUTOMATION_ENABLED=false` e não colocar
`INSTAGRAM_TESTER_RUNTIME_MODE=vps` no Rails.

Home e subdiretório do publisher: `/var/lib/instagram-publisher-STACK` e
`publisher`, 0700, dono `igpub-STACK`, grupo primário `igpub-STACK`.
As seis contas são `nologin`. `Group=ig-STACK` na unit publisher vale somente
para o processo/socket, não para o grupo primário da conta nem para os arquivos
privados. Publisher não tem grupos suplementares e não reutiliza UID/GID de browser/gateway.
`manager.env` conserva somente `INSTAGRAM_TESTER_PUBLISHER_SOCKET` e não recebe
nenhuma `AWS_*` ou outra variável de publisher. O wrapper chama o client Unix;
HOME/PATH/stack/socket e toda a configuração AWS/SSH são do `publisher.env`.

Home e subdiretório do gateway: `/var/lib/instagram-gateway-STACK` e `gateway`,
0700, dono/grupo `iggw-STACK`. State/nonce permanecem 0600 desse UID.
Browser/manager usam conta/grupo primário `ig-STACK`, suplementar apenas
`igview-STACK`; display mantém UID browser e usa `Group=igview-STACK`.
Gateway usa `User=iggw-STACK`, `Group=iggw-STACK`, suplementar apenas viewer,
jamais `ig-STACK`. Cada viewer lista exatamente browser e gateway; nenhum membro
extra nos seis grupos primários, alias UID/GID ou conta externa com esses GIDs.
Contas e IDs são descobertos por passwd/group/initgroups, sem UID/GID numérico
em env. Não alterar grupos/permissões de conta antiga automaticamente para
instalar: o preflight recusa inconsistência antes dos writes. Na partida o check
confere também os grupos efetivos do processo com o Group da unit.

`gateway.env` aponta `INSTAGRAM_TESTER_GATEWAY_STATE_DIR` para
`/var/lib/instagram-gateway-STACK/gateway`. Homes gateway ficam inacessíveis a
manager/display/publisher. O gateway pode fazer stat do home browser para derivar
UID, mas não ler perfil/Xauthority ou chaves/config publisher. O segredo HS256
não fica no UID Chrome. Configs `/etc` continuam root:root 0600.

O instalador recusa home browser com `publisher` ou `gateway` legado, inclusive symlink, e
unidades antigas com conteúdo diferente. Não migra, apaga nem muda ownership de
perfis/chaves existentes. Uma atualização a partir do pacote anterior precisa
de plano operacional aprovado de migração das credenciais/env/unidades,
preservação dos perfis e rollback compatível. Broker/client de ATLAS e seu módulo
importado `publisher-socket.mjs` precisam estar no artefato final; sem qualquer
um deles a instalação é recusada no preflight.

Verificação offline de configuração, sem executar helper, AWS, SSH ou publisher:

```sh
sudo /usr/bin/python3 /opt/instagram-meta/current/scripts/instagram_testers/runtime/vps/env/verify-pair.py
```

Saída de sucesso: `instagram_vps_env_pair_ok`. Erro: `instagram_vps_env_pair_failed`.
Não registrar conteúdo da env/config, ticket, JWT, perfil ou chave na auditoria.

## Ativação autorizada e aceitação Linux

Ativar primeiro display e gateway de uma stack, validar sem ticket, depois
publisher e manager. A unit manager exige o publisher da mesma stack.
Exemplo para hub2you; aplicar o equivalente a autonomia em bloco separado:

```sh
sudo systemctl start instagram-vps-display@hub2you.service instagram-vps-gateway@hub2you.service
sudo systemctl show --property=ActiveState --value instagram-vps-display@hub2you.service
sudo systemctl show --property=ActiveState --value instagram-vps-gateway@hub2you.service
```

O estado `active` de uma unit `Type=simple` pode anteceder a abertura do listener.
Antes de aceitar a partida, aguardar em prazo finito a resposta HTTP real: GET no
prefixo da stack, Host da URL privada e X-Forwarded-Proto=https devem retornar
401 sem Set-Cookie. Depois conferir Unix VNC, Xauthority regular 0600 do UID
browser, permissões, identidades e listener exclusivamente loopback. Recusa de
conexão durante a partida não é sucesso; timeout é falha. Não repetir `start`
em loop. Em falha, preservar evidência e parar somente o par novo conforme o
rollback, mantendo publisher/manager inativos.

Publicação privada HTTPS proposta para revisão do Serve da versão instalada:

```sh
sudo tailscale serve --bg --https=443 --set-path=/hub2you/ http://127.0.0.1:18441/hub2you/
sudo tailscale serve --bg --https=443 --set-path=/autonomia/ http://127.0.0.1:18442/autonomia/
```

O destino inclui o mesmo prefixo porque o gateway exige `/STACK/`; validar a
preservação do path, Host, Origin e upgrade WebSocket pela versão instalada antes
de abrir login. Não servir arquivos/dirs noVNC diretamente. Sem Funnel, mount de
raiz, HTTP público ou proxy VNC cru. Serve existente só pode ganhar estes mounts;
se houver conflito, parar e revisar, não usar `tailscale serve reset`.
A referência oficial é [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve).

Aceitação precisa demonstrar, sem registrar dados privados:

- socket `/run/instagram-STACK/vnc.sock` AF_UNIX, browser:viewer 0660; diretório
  browser:viewer 0710; marker `browser-request.json` browser:viewer 0640; nenhuma escuta TCP VNC/X11; HTTP somente `127.0.0.1:18441/18442`.
- Xauthority 0600, displays separados e X11 compartilhado só dentro da stack.
  Uma stack não lê perfil/nonce/env da outra. Confirmar seis UIDs distintos,
  oito GIDs distintos e memberships exatos; gateway nunca no grupo `ig-STACK`.
  Browser/manager não lê home/nonce/segredo gateway; gateway não conecta ao socket
  publisher. Testar com identidades sintéticas e autorizações específicas da
  homologação, sem examinar environ/memória/segredos reais. Gateway não lê `profile`, home publisher
  ou Xauthority; unit não recebe variáveis AWS/proxy. Manager/browser/display
  não leem nenhum home publisher, nem recebem AWS/configuração SSH.
- Publisher roda com UID `igpub-STACK` e GID `ig-STACK`; runtime
  `/run/instagram-publisher-STACK` 0710, socket `publisher.sock` AF_UNIX 0660,
  dono publisher, grupo browser. Browser pode conectar ao socket, mas não criar,
  substituir ou remover entradas nesse diretório e não lê chave/config AWS.
  Publisher não lê nenhum home browser/gateway nem o home publisher da outra
  stack. Não existe listener TCP/HTTP/público do broker. AF_INET/AF_INET6 na unit
  permitem saída necessária AWS/SSM/SSH; o listener interno é exclusivamente Unix.
  Testar recusa de symlink/socket preexistente e cancelamento por desconexão/
  timeout no broker/client conforme contrato ATLAS, com dados sintéticos na
  homologação autorizada. Não gerar publicação real para esse teste.
- Ao parar publisher, systemd remove o runtime efêmero: sem
  `RuntimeDirectoryPreserve`, limpeza por shell ou remoção de home/perfil/chave.
  Confirmar escopo do cgroup e preservação de dados; não matar processos alheios.
- HTTPS válido e acesso somente pelo grupo autorizado da tailnet. Sem ticket,
  assets/console/status/WS são recusados. Ticket expirado, replay depois de
  reinício, Origin errado e ticket de outra stack falham fechados.
- Sem marcador, marcador expirado ou request diferente, VNC não conecta.
  Não criar marcador à mão para fazer teste passar.

A partir daqui há execução do publisher/Meta: só continuar com aprovação
operacional correspondente e configuração validada.

```sh
sudo systemctl start instagram-vps-publisher@hub2you.service instagram-vps-manager@hub2you.service
sudo systemctl show --property=ActiveState --value instagram-vps-manager@hub2you.service
```

Provar sandbox real do Chrome (não só flag), manager contínuo, bootstrap/recebimento
real da publicação e health do backend. Provocar reconexão apenas pelo fluxo
SuperAdmin aprovado. O operador abre o form protegido, espera a janela humana,
conclui verificação Meta e **fecha Chrome remoto** com `Ctrl+Shift+W`; fechar só
a aba noVNC não conclui. Verificar desaparecimento do marcador e encerramento do
acesso. Não limpar perfil/Redis/lock para simular recuperação. Desligar Macs e
confirmar o mesmo fluxo sem dependência deles.

Só depois da aceitação, habilitar as quatro unidades da stack para boot por decisão
aprovada. Falha de startup fica limitada pelo StartLimit (3 por 300 s); não
adicionar loop de restart infinito ou reiniciar outros serviços. O health do
runtime não equivale à autorização/saúde Meta ou ao recebimento da publicação.

## Rollback aprovado

1. Fechar a janela humana, retirar somente mounts desta entrega, preservar o
   restante do Serve. Remover os mounts com os mesmos flags da ativação:

   ```sh
   sudo tailscale serve --https=443 --set-path=/hub2you/ off
   sudo tailscale serve --https=443 --set-path=/autonomia/ off
   ```

2. Parar **somente** `instagram-vps-gateway@STACK`, `instagram-vps-manager@STACK`,
   `instagram-vps-publisher@STACK` e `instagram-vps-display@STACK`. O manager usa
   cgroup para encerrar Chrome e filhos; confirmar ausência dos processos antes
   de trocar release. Se units
   foram habilitadas nesta operação, desabilitar somente essas unidades.
3. Se há release anterior aprovada, conferir owner/checksum/paths e compatibilidade
   das unidades/env. Criar symlink temporário root-owned para ela e trocar `current`
   atomicamente, sem apagar a release nova ou a anterior. Reativar somente as
   unidades Instagram aprovadas e repetir health. Se unidades/env mudaram, a
   reversão precisa usar a configuração anteriormente revisada, não improvisar.
4. Não remover usuários, profiles, Xauthority, SSH keys, nonces, estado do publisher
   ou Redis. Não limpar nonces para recuperar acesso: isso reabre replay. Não
   reiniciar n8n, Traefik, Rails/web/worker ou Redis neste rollback. Se a identidade
   AWS precisar revogação, tratar em aprovação própria, sem ampliar este script.
5. Registrar SHA/path antes/depois, estados das quatro unidades por stack, HTTPS,
   recebimento do publisher e impacto observado. Nenhum secret/dado de cliente.

## Testes offline do pacote

```sh
python3 -B tests/instagram_testers/vps-infra_test.py -v
```

Filesystem temporário, comandos/account/ownership injetados. Os binários falsos
não são executados; o código real do publisher/gateway/browser não é importado ou
executado. Inclui sintaxe do wrapper e falha fechada da CLI sem argumentos.
Isso não verifica instalação no Linux, systemd/Xvnc/Chrome reais, federação AWS,
SSM, Tailscale/HTTPS, proxy, Redis ou Meta. Resultados reais e bloqueios estão na
[auditoria operacional](../audit/995-vps-runtime-operations-20261005.md).
A [auditoria Nexo](../audit/995-nexo-infra-20261005.md) preserva o histórico de preparação.

## Integração final e verificações ainda obrigatórias

- O pacote Ubuntu 24.04 fornece `/usr/bin/Xtigervnc`; o instalador não exige um
  `/usr/bin/Xvnc` inexistente. AWS CLI é aceita em /usr/local/bin ou /usr/bin.
- `INSTAGRAM_TESTER_RUNTIME_MODE=vps` é obrigatório no manager VPS. O ciclo completo
  tem teto de 120 s; a pausa VPS é 13 min para que a publicação e heartbeat seguintes
  ocorram dentro dos 16 min do TTL. Fora do pacote VPS, 30 s/15 min continuam iguais.
- Limites por stack: manager MemoryMax=2G/CPUQuota=150%; display512M/50%; gateway256M/50%;
  publisher512M/50%.
  São limites de projeto, não consumo medido. Homologar a carga junto ao n8n existente.
- A página Rails que POSTa o ticket usa `strict-origin`, não `no-referrer`: Fetch
  transforma Origin em null com no-referrer em POST de navegação. O gateway exige
  Origin exata e nunca aceita null. Nenhum token é colocado em URL ou Referer.
- Tailscale Serve TCP reverse proxy preserva Host e define X-Forwarded-Proto=https;
  o path base também deve ser preservado nos dois lados. Conferir na versão real.
  Fontes: https://fetch.spec.whatwg.org/#append-a-request-origin-header e
  https://github.com/tailscale/tailscale/blob/main/ipn/ipnlocal/serve.go.
- O marcador do browser é JSON público completo publicado via hardlink exclusivo
  no mesmo diretório browser:viewer0710, com mode0640; nunca sobrescreve marcador existente. O leitor permite
  dois links somente nesse marcador durante a janela de remoção do temporário;
  nonces de autenticação continuam exigindo um link. Perfil e cookies não são lidos.
- Reboot abrupto pode deixar lock de perfil: preservar, bloquear e revisar dono;
  não há limpeza automática de locks desconhecidos nem garantia de recuperação após SIGKILL.
- CI Linux smoke não acessa Meta nem produção. Sob UID único, o smoke da Íris
  simula ownership gateway no filesystem injetado e declara que não prova
  isolamento real. configFromEnv de produção continua exigindo UIDs separados;
  o teste não permite UID único no código operacional. Somente homologação após aprovação
  comprova HTTPS, autenticação AWS de serviço, login humano e duas renovações reais.
