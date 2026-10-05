# #995 — bloqueio de preparação da VPS — 05/10/2026

Status: dependências e runtime VPS não instalados. Esta rodada fez somente
consultas locais/remotas e escreveu este relatório; nenhum download, extração,
pacote, usuário/grupo, unidade, configuração, segredo ou serviço foi provisionado.

## Autorização e rejeição automática

A [Issue #995, comentário 5997020246](https://github.com/autonom-ia2/chat/issues/995#issuecomment-5997020246),
publicado em 05/10/2026 às 14:55:35 UTC, registra a autorização de Rodrigo para
merge/fila da PR #1003, deploy OFF nas duas stacks, runtime integral na VPS n8n,
identidades AWS dedicadas, HTTPS privado e rollback.

O arquivo `tmp/approved-1003-20261005/HANDOFF.md`, no estado das 15:02 UTC,
registra rejeição automática da ferramenta ao executar `prepare-dependencies.py`,
antes da execução do wrapper local/remoto. O motivo detalhado da rejeição não foi
recuperado nesta retomada. Não atribuir a recusa a uma causa presumida.
`dependencies-execution.json` continua ausente; o código preparado não é recibo
de execução. A operação rejeitada não foi repetida por outra ferramenta ou rota.

Script preservado: `tmp/approved-1003-20261005/prepare-dependencies.py`.
SHA256 lido nesta rodada:
`d5cfe54ebcea3610b16c4c4260389ec6748c3bf5d1f1d4866313cc09908ea4c6`.
Esta auditoria não autoriza a reexecução do script.

## Linha de base remota confirmada

Consulta de 05/10/2026 às **15:17:58 UTC**, por SSH de manutenção estrito:
`BatchMode=yes`, `StrictHostKeyChecking=yes`, `HostKeyAlgorithms=ssh-ed25519`,
`ForwardAgent=no`, `UpdateHostKeys=no`. Não houve alteração de `known_hosts`.
Destino resolvido: `root@85.31.60.100:22`; hostname retornado: `srv707880`.
Fingerprint ED25519 igual à confirmada por Rodrigo no console:
`SHA256:ZMarrHM0jX27CrSoO2QP24f4eGC5eFHVl6DqqZT6krw`.

| Item | Resultado observado |
|---|---|
| Sistema e arquitetura | Ubuntu 24.04.4 LTS, x86_64; UID efetivo da consulta 0 |
| Node do host | /usr/bin/node, v18.19.1; abaixo do mínimo 22.12.0 |
| Python | 3.12.3 |
| Chrome | Google Chrome 154.0.8037.97 |
| TigerVNC | /usr/bin/Xtigervnc e os três pacotes candidatos ausentes |
| AWS e Session Manager | Executáveis presentes em /usr/local/bin, caminho aceito |
| Armazenamento | 226G disponíveis; partição raiz 42% utilizada |
| Memória | 19.440 MiB disponíveis; swap utilizada 5.629 MiB |
| Tailscale Serve | Configuração vazia: {} |
| Unidades Instagram VPS | Oito instâncias: not-found, inactive e MainPID=0 |

`/opt/instagram-meta-tools`, seu recibo `dependencies-995.json`,
`/opt/instagram-meta-staging`, `/opt/instagram-meta/releases`, `current`,
`/etc/instagram-meta` e os seis homes previstos não existem.
As seis contas `ig-*`, `igpub-*`, `iggw-*` e os oito grupos previstos não existem.
Não foram encontradas escutas TCP nas portas verificadas
18441, 18442, 5900, 5901, 5991, 5992, 6000, 6091 e 6092; não é inventário de toda a rede.

Os ancestrais existentes `/`, `/opt`, `/etc/systemd/system` e `/var/lib`
são diretórios root:root 0755. Kernel declara USER_NS, BPF, BPF_SYSCALL e
CGROUP_BPF habilitados; max_user_namespaces=128226, unprivileged_userns_clone=1
e apparmor_restrict_unprivileged_userns=0. Esses dados não comprovam sandbox
Chrome, isolamento de namespaces ou filtro de rede systemd funcionando.

## Dependências: leitura de metadados, sem baixar pacotes

`apt-cache show --no-all-versions` informou estes candidatos do Ubuntu noble.
Nenhum deles estava no cache de arquivos .deb do host.

| Pacote | Versão / arquitetura | Bytes | SHA256 informado pelo índice local |
|---|---|---:|---|
| tigervnc-standalone-server | 1.13.1+dfsg-2build2 / amd64 | 1141656 | a51c4686dc0e95fdc8fb7109ef17a7399267eb70a1a58df2ab2c6f155448584b |
| tigervnc-common | 1.13.1+dfsg-2build2 / amd64 | 84370 | 69be5ad23b703a8f199e5aa6571f6c2dbb73f131926dd14dd06766b04515589e |
| libfile-readbackwards-perl | 1.06-2 / all | 10178 | be199d349bb7e48ef5f2a7284c049f8e4a1ad1af1c54c1c8ff5bf59cf2b080c1 |

`dpkg-query` confirmou instaladas todas as bibliotecas declaradas nos campos
Depends desses pacotes, exceto os próprios três candidatos. Incluem glibc 2.39,
GnuTLS 3.8.3, libXfont2, libGL, libX11 e Perl. Também existem xkbcomp, dados XKB,
xfonts-base, fontconfig, fontes misc, DejaVu e Liberation.
`/usr/lib/xorg/modules` não existe. Sem obter/examinar o ELF, não foi validada
a resolução completa de bibliotecas, módulos opcionais ou inicialização gráfica.

O pacote aprovado ainda exige noVNC 1.7.0, jose 6.2.12, Playwright 1.59.1 e
ws 8.22.0 preparados no Linux pelo lockfile; não copiar node_modules do Mac.
A proposta anterior fixa Node v24.21.0 linux-x64 em diretório privado, sem trocar
Node18 global. O arquivo `node-release.json`, observado às 14:53:41 UTC, registra
SHA256 do tarball `fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6`.
O script registra helper AWS Signing 1.8.5 com SHA256
`beec9ed1c492d93db809890f16713e3556353294b823c2184ad4e891f1b2b54d`.
São referências preparadas, não evidências de download, instalação ou execução.

## Alternativa privada: proposta não validada

Foi considerada, somente no papel, a obtenção verificada dos três .deb e sua
extração em diretório versionado root-owned em /opt, com exposição privada
apenas às unidades Instagram e ao instalador. Isso reduziria o alcance frente
a apt-install: não registraria pacotes globais nem executaria maintainer scripts,
triggers, update-alternatives ou reinícios originados pelo gerenciador de pacotes.
Essa diferença de risco não demonstra qual foi o motivo da rejeição automática.

Há uma pendência concreta: /usr/bin/Xtigervnc não existe. O manual systemd255
de BindReadOnlyPaths exige destino existente ou criável. Não foi demonstrado que
um bind direto nesse destino ausente evitaria criar um ponto de montagem no
filesystem do host. O caso difere do Node, cujo destino já existe.
A proposta, portanto, não foi considerada pronta para execução. A investigação
foi encerrada sem desenvolver overlays, alterar o contrato ou preparar outro
método de execução da operação rejeitada.

A lista oficial do pacote confirma que o runtime pode invocar Xtigervnc
diretamente; nosso systemd não usa tigervncserver/tigervncsession.
As dependências Perl/common incluem wrappers e configurações auxiliares.
Essa inspeção de layout não substitui a verificação do binário efetivo,
suporte rfbunixpath/rfbunixmode/rfbport, socket Unix e sandbox no Linux.

## Instalação, preservação e próximo passo

O instalador imutável exige stage confiável, SHA/conteúdo correlacionados,
dependências completas e unidades Instagram inativas. Cria seis UIDs e oito GIDs
exclusivos, faz daemon-reload e seleciona current só após sucesso; não inicia
nem habilita serviços. Repetir o mesmo SHA ou sobrescrever unidade divergente
é recusado. Uma instalação parcial exige inspeção; não apagar dados para tentar novamente.

Permanecem pendentes provisionamento AWS/env/HTTPS e aceitação real de DAC,
grupos efetivos, Chrome, VNC, Origin/WebSocket, bootstrap e renovação Meta.
Nenhum publisher, manager, navegador ou sessão Meta foi executado nesta frente.
Não foram lidos valores de secrets, perfis, cookies ou ambiente de processos.
Redis, n8n, Traefik e gestores dos Macs não foram alterados nem reiniciados.

O rollback da primeira instalação continua o do runbook: retirar apenas os
mounts Serve novos e parar/desabilitar somente unidades Instagram que tenham
sido ativadas, preservando perfis, chaves e nonces. No estado atual, não há release
VPS anterior nem unidades novas ativas para reverter. Não fazer apt autoremove,
purge, limpeza de profiles/nonces/Redis ou troca global de Node como compensação.

O coordenador conclui a publicação Rails autorizada com assistido OFF e a
corretiva P2 revisável; a decisão específica sobre preparação da VPS permanece
separada, com a rejeição automática e a ausência de motivo detalhado explicitadas.

## Referências verificadas

- `docs/runbooks/instagram-vps-runtime-995.md`
- `scripts/instagram_testers/runtime/vps/install/install.py` e quatro templates systemd
- `tmp/approved-1003-20261005/{HANDOFF.md,vps-baseline.json,dependencies-preflight.json,nexo-deps-isolation.md}`
- Manual instalado: `/usr/share/man/man5/systemd.exec.5.gz`, seção BindReadOnlyPaths
- [Ubuntu: arquivos standalone](https://packages.ubuntu.com/noble/amd64/tigervnc-standalone-server/filelist)
- [Ubuntu: arquivos common](https://packages.ubuntu.com/noble/amd64/tigervnc-common/filelist)
- [Ubuntu: arquivos Perl](https://packages.ubuntu.com/noble/all/libfile-readbackwards-perl/filelist)
- [Ubuntu noble: manual Xtigervnc](https://manpages.ubuntu.com/manpages/noble/man1/Xtigervnc.1.html)
