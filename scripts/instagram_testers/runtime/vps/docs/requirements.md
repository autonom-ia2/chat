# Contrato do pacote Linux #995

Instalador: `install/install.py SOURCE_ROOT RELEASE_SHA`. Entrada é o
artefato preparado root-owned, sem escrita por outros nos arquivos/ancestrais,
contendo `scripts/instagram_testers`, um SHA aprovado de 40 hex
minúsculos e dependências **já instaladas** em `runtime/vps/node_modules` a partir
do `package-lock.json`. O instalador não consulta Git/rede nem prova que o SHA
representa o conteúdo recebido: essa correspondência/checksum é responsabilidade
do empacotamento e aprovação da release. Ele copia somente os sete módulos
JS do runtime existente e o pacote `vps/`; não copia Rails, `.env`, perfis ou
credenciais. Os links `.bin` do npm são ignorados; outros symlinks são recusados.

Requisitos Linux ainda não verificados no host nesta entrega:

- systemd com `PrivateTmp`, `JoinsNamespaceOf`, `InaccessiblePaths`, proteção de
  filesystem e filtro `IPAddressDeny/Allow` funcional (cgroup BPF). Instalação
  requer root; execução usa seis contas `nologin`, com UID e grupo primário
  exclusivos: `ig-hub2you`, `ig-autonomia`, `igpub-hub2you`, `igpub-autonomia`,
  `iggw-hub2you` e `iggw-autonomia`. Os dois grupos dedicados
  `igview-hub2you`/`igview-autonomia` têm GIDs distintos dos seis primários.
- Python 3.9+ e Node 22.12+ em `/usr/bin`. `Xvnc`, `xauth`, `mcookie`, Chrome,
  AWS CLI, OpenSSH, `systemctl`, `useradd`, `groupadd` e `runuser` nos caminhos do instalador;
  Session Manager plugin em `/usr/bin` ou `/usr/local/bin` e no PATH do serviço.
- TigerVNC `Xvnc` com `rfbunixpath`, `rfbunixmode` e `rfbport=-1`. Não usar Xvfb,
  x11vnc, websockify, VNC TCP, desktop, display manager ou shell no desktop.
- Chrome estável com sandbox via user namespaces disponível para usuário sem
  privilégio, inclusive políticas AppArmor. `max_user_namespaces > 0` e, quando
  presente, `unprivileged_userns_clone=1`. Não instalar Chrome, mudar sysctl,
  remover AppArmor ou passar `--no-sandbox` neste instalador. Com
  `NoNewPrivileges=true`, não depender do helper setuid: provar sandbox real na
  aceitação Linux. `chromiumSandbox=true` é necessário, não é prova de sandbox.
- Pacote VPS com noVNC 1.7.0, jose 6.2.12, ws 8.22.0 e Playwright 1.59.1;
  playwright-core precisa existir na árvore preparada. O coordenador é dono do
  manifest/lockfile e da preparação das dependências.
- Tailscale existente com HTTPS/certificado e ACL privada aprovados; o contrato
  informa `srv707880-claudete.tail0c0b18.ts.net`, Serve vazio e certificado não
  confirmado. Isso não foi verificado ao vivo nesta entrega.
- Proxy da stack e identidade AWS de serviço precisam de provisionamento aprovado
  separado. O pacote não escolhe identidade, cria tags, lê AWS ou testa Meta.

| Stack | UID lógico | Home e perfil | Display | HTTP loopback |
|---|---|---|---|---|
| hub2you | ig-hub2you | /var/lib/instagram-hub2you/profile | :91 | 18441 |
| autonomia | ig-autonomia | /var/lib/instagram-autonomia/profile | :92 | 18442 |

Os números UID/GID são atribuídos pelo Linux; não há ID numérico inventado.
Home browser e `profile` são 0700; Xauthority é 0600, dono browser.
O gateway usa home separado `/var/lib/instagram-gateway-STACK` e subdiretório
`gateway`, ambos 0700, dono/grupo `iggw-STACK`. Nonces/state são desse UID, 0600;
não apagar nonces para resolver problemas. Configurações em `/etc` continuam
root:root 0600, não são copiadas para homes browser.

| Processo | User | Group da unit | Suplementar da conta/unit |
|---|---|---|---|
| Display | ig-STACK | igview-STACK | viewer já cadastrado para ig-STACK |
| Manager/Chrome | ig-STACK | ig-STACK | igview-STACK |
| Gateway | iggw-STACK | iggw-STACK | igview-STACK |
| Publisher | igpub-STACK | ig-STACK | nenhum |

As contas publisher mantêm grupo primário próprio `igpub-STACK`; o Group da unit
é usado somente pelo processo/socket. Cada conta browser/gateway pertence somente
a seu grupo primário e ao viewer da própria stack. Cada viewer lista exatamente
browser e gateway; os seis grupos primários não têm membros suplementares.
O gateway nunca pertence a `ig-STACK`, que autoriza o publisher. O instalador e
os verificadores recusam grupos extras, aliases UID/GID e usuários externos com
GID primário desses grupos, inclusive viewer. UIDs/GIDs vêm de passwd/group e
initgroups, nunca de números ou variáveis de ambiente definidos manualmente.
Cada publicador tem home separado `/var/lib/instagram-publisher-STACK` e
subdiretório `publisher`, ambos 0700, dono `igpub-STACK` e grupo primário próprio.
Somente esse usuário lê `publisher/{id_ed25519,aws-config}`, 0600. Não criar
`publisher` dentro do home browser. Instalação/configuração legada nesse caminho
é recusada; migração exige plano aprovado, sem mover/apagar dados automaticamente.
O display cria `/run/instagram-STACK`, browser:viewer 0710, e socket `vnc.sock`,
browser:viewer 0660. O browser humano publica `browser-request.json`,
browser:viewer 0640, somente durante a solicitação. O manager mantém UMask=0077;
o módulo da Íris aplica fchown(-1, parent.gid) e fchmod(0640) antes do hardlink
exclusivo. Não criar marcador fictício ou sobrescrever um existente.
Gateway só atravessa o runtime e lê marker/conecta VNC pelo viewer, sem escrita
no diretório. Socket Unix requer escrita para conectar; VNC 0640 não serve.
Node deriva browserUid do stat do home fixo e viewerGid do runtime, verificando
ancestrais root-owned, tipos reais sem symlink, proprietário, grupo, modos e inode.
Somente state/nonce usam o UID gateway. Python valida contas/grupos e runtime na
partida; verify-pair não exige runtime efêmero, socket ou marker durante preparação.

Manager e display compartilham **somente o namespace tmp da mesma stack**, para
que X11 Unix funcione com `PrivateTmp=true`; displays diferentes e xauth privado
separam as stacks. Xvnc tem `-nolisten tcp`, autenticação X11 obrigatória e
`-SecurityTypes None` apenas no socket Unix privado. O gateway autenticado é a
única ponte web e não recebe env AWS/proxy/publisher. Clipboard VNC fica desativado.
Sem window manager: fechar a janela Chrome com `Ctrl+Shift+W`, não somente noVNC.

Configuração root: `/etc/instagram-meta/STACK/{display,manager,gateway,publisher}.env`,
0600 dentro de diretórios 0700. Os exemplos não são configurações prontas;
placeholders impedem a ativação. O verificador offline `env/verify-pair.py`
recusa env desconhecida, duplicada, quoting/expansão, caminhos divergentes,
permissões inseguras, chaves iguais e placeholders. `env/check.py STACK ROLE`
roda antes de cada serviço e recusa configurações essenciais inválidas.

`manager.env` não contém nenhuma `AWS_*` nem `INSTAGRAM_TESTER_PUBLISHER_*`, exceto
`INSTAGRAM_TESTER_PUBLISHER_SOCKET=/run/instagram-publisher-STACK/publisher.sock`.
O wrapper entrega o JSON ao `runtime/vps/publisher-client.mjs --stack STACK`;
não chama mais o túnel diretamente. `publisher.env` contém HOME/PATH/stack/socket,
AWS e chave SSH, inclusive o opt-in `ChatwootInstagramPublisherHostKey`.

`instagram-vps-publisher@STACK.service` executa `publisher-broker.mjs` como
`igpub-STACK` e `Group=ig-STACK` somente para permitir a conexão do browser pelo
socket. Não alterar o grupo primário da conta publisher nem adicioná-la ao grupo
browser. O RuntimeDirectory é `/run/instagram-publisher-STACK`, 0710, dono publisher
e grupo browser; UMask=0007. Não há `RuntimeDirectoryPreserve`, socket activation
ou limpeza por shell: systemd remove apenas o diretório efêmero ao parar.
Homes/perfis/chaves ficam preservados. Manager Requires/After publisher da mesma
stack. Todas as unidades browser/gateway ocultam os dois homes publisher;
display/manager/publisher ocultam os dois homes gateway. Publisher oculta os dois
homes browser e runtimes display. Gateway oculta perfil/Xauthority e não recebe
AWS/SSH. Homes de cada UID são privados, inclusive entre stacks.

O broker, de responsabilidade ATLAS, deve criar exclusivamente o socket AF_UNIX
`publisher.sock`, 0660, dono `igpub-STACK`, grupo `ig-STACK`, sem sobrescrever
socket existente. O preflight Python não cria nem abre sockets. O filtro systemd
permite AF_UNIX e AF_INET/AF_INET6: estas últimas são necessárias para conexões
de saída AWS/SSM/SSH, e não significam um endpoint TCP autorizado. Ausência de
listener TCP/HTTP é requisito do broker e da aceitação Linux, não prova fornecida
pelo filtro systemd. Broker/client e `publisher-socket.mjs` precisam integrar o
artefato: os módulos ATLAS importam esse helper. Sem qualquer um dos três, o
instalador recusa antes de escrever.
Não foram implementados nem executados nesta entrega NEXO.

A unidade gateway roda `runtime/vps/gateway.mjs`. Os nomes de env e caminhos
seguem o contrato do gateway: issuer é a origem HTTPS do Rails sem barra final;
URL do browser é `https://HOST/STACK/`; segredo hex >=64 caracteres, tamanho par,
bytes diferentes por stack. O form POST/JWT, validação de claims/cookies/Origin,
marcador e autorização são implementados pelos donos do gateway/Rails/browser.

O instalador só admite unidades novas ou byte a byte iguais. Mudança futura em
unidade existente precisa de plano explícito aprovado, não overwrite implícito.
Ele recusa dados gateway legados em `/var/lib/instagram-STACK/gateway`, inclusive
symlink, sem mover/apagar nonces. Também recusa runtime ativo/ativando/desativando, releases já existentes, paths
symlink, `current` de pacote legado/estranho e usuários preexistentes fora deste
contrato. Não altera recursivamente
ownership/permissões de perfis existentes, não limpa lock/perfil/Redis e não
habilita/inicia/reinicia serviços. Seleciona `current` só após a instalação e
`daemon-reload`. Uma falha pode deixar release/usuário/unidade **inativos**; não
há remoção automática e `current` fica na release anterior. Inspecionar e aprovar
recuperação antes de repetir, sem apagar dados por tentativa.

Testes offline têm UID/GID injetados e filesystem temporário. O smoke Linux da
Íris executado sob UID único simula a identidade gateway no filesystem injetado:
valida fluxo funcional, não isolamento DAC/processos/HS256 real. Não enfraquece
configFromEnv de produção para passar o smoke. Aceitação posterior aprovada deve
comprovar os seis UIDs, oito grupos e permissões efetivas, incluindo impossibilidade
de browser ler state/segredo gateway e de gateway conectar ao publisher.

Referências: [Xvnc oficial](https://tigervnc.org/doc/Xvnc.html),
[namespaces systemd](https://github.com/systemd/systemd/blob/main/man/systemd.unit.xml),
[isolamento systemd](https://github.com/systemd/systemd/blob/main/man/systemd.exec.xml).
