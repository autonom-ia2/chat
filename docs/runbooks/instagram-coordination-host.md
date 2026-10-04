# Redis de coordenação Instagram: instalação nova no host n8n

Este provisionador roda **localmente no host Linux aprovado**, como root, após review do parent. Não usa SSH para instalar e não altera serviços Redis, n8n ou Traefik existentes. Não executar como startup, durante deploy de aplicação ou para recuperar estado perdido.

Entrada: IPv4 público e porta do **Webshare Direct**, mais o IPv4 residencial de saída esperado, conferidos previamente no inventário Webshare. Não fornecer token, senha ou cookie. A conexão HTTPS via proxy deve retornar exatamente o IP esperado, sem redirects ou fallback direto. Não chama Meta.

```sh
sudo bash scripts/instagram_testers/runtime/provision-coordination-host.sh \
  "$WEBSHARE_DIRECT_IPV4" "$WEBSHARE_DIRECT_PORT" "$EXPECTED_RESIDENTIAL_IPV4"
```

Antes de criar qualquer recurso, exige Docker **Server 28+**, Compose, SSH válido/ativo, porta 6381 livre e ausência de todos os nomes abaixo, inclusive symlinks quebrados:

- `/opt/instagram-coordination`, `/home/igcoord` e `/etc/ssh/sshd_config.d/70-instagram-coordination.conf`;
- usuário/grupo `igcoord`;
- volume `instagram_coordination_data`, container `instagram-coordination-redis` e rede `instagram-coordination-bridge`.

Falha de inspeção também bloqueia. Docker antigo é blocker: este script não atualiza Docker. A publicação é `127.0.0.1:6381` numa bridge interna dedicada, sem host network. Docker anterior ao 28 tem uma limitação documentada para portas publicadas em localhost ([Docker](https://docs.docker.com/engine/network/port-publishing/)). A configuração e TLS usam mounts separados readonly; dados ficam no volume dedicado. CPU 0,25; RAM e RAM+swap 256 MiB; 64 processos; filesystem readonly e capacidades removidas.

O host gera CA, certificado com SAN `ig-coord.internal`, senhas, epoch e três chaves SSH novos. Nenhum segredo vem do repositório. Todos ficam locais em `/opt/instagram-coordination/private`, protegido com modo 700 e arquivos 600. Não usar `cat`, tracing, logs de stdin ou cópia indiscriminada dessa pasta.

Aplicações recebem **somente** sua própria chave (`ig_hub.key` ou `ig_auto.key`), seu `.env`, a CA pública e host key SSH verificada pelo parent. `ig_m4.key` permite somente Webshare. O admin, CA privada e chave TLS privada permanecem no host; nunca distribuir `ig_admin.pass`. Publicação em SSM/instalações fica a cargo do parent após aprovação, fora deste provisionador. A host key deve ser fixada fora de banda, sem aceitar automaticamente resultados de `ssh-keyscan`.

As chaves novas têm `restrict`, forwarding local e `permitopen` apenas para Redis loopback e o endpoint Webshare validado; sem shell, sessão, TTY, agentes ou forwarding remoto. O script verifica a configuração efetiva de SSH antes de recarregar o serviço. Essa recarga é a única alteração a serviço compartilhado do host e precisa da aprovação operacional já prevista.

ACL usa [selectors Redis](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/): aplicações podem GET do epoch, mas SET/DEL dele são negados, inclusive quando enviados em transações. GET/SET/DEL/WATCH ficam limitados a `instagram_tester_coordination:instagram_testers:invite:*`. Demais comandos permitidos são PING, SELECT (há somente DB 0), UNWATCH, MULTI, EXEC, DISCARD e WAITAOF. Não há EVAL, FLUSH, CONFIG ou ACL para a aplicação.

O epoch nasce uma única vez via SET NX no setup. WAITAOF é executado **na mesma conexão** e precisa confirmar um fsync local. AOF usa `appendfsync always`, rejeita truncamento e `noeviction`; falha de TLS, startup, ACL ou persistência bloqueia antes de liberar SSH. O Compose nunca escreve/recria epoch durante startup. Perda de volume/epoch exige investigação e reconciliação dos convites; nunca reset automático.

Qualquer falha após começar a instalação preserva recursos parciais e exige review. Re-run é recusado; não existe auto-delete, reutilização ou rollback destrutivo. Não apagar volume, usuário, pasta ou epoch para tornar o script executável novamente. Rollback operacional: manter aplicações sem convites, preservar os recursos e revisar a falha; remoção/desativação manual exige autorização específica.

Validação offline, com comandos e infraestrutura fictícios:

```sh
bash -n scripts/instagram_testers/runtime/provision-coordination-host.sh
python3 tests/instagram_testers/provision-coordination-host_test.py
```

O teste verifica instalação simulada, colisões, inspeções falhando, Docker antigo, mismatch Webshare, preservação em falha de persistência, recusa de re-run e ausência de segredos na saída com `bash -x`. Não homologa Docker, certificados, ACL ou SSH reais. Antes da aplicação, o parent deve revisar o SHA final, registrar a evidência em `docs/audit/` e validar isolamento, restart sem mudança de epoch, permissões ACL e WAITAOF no host autorizado. Nada deste trabalho executou infraestrutura remota.
