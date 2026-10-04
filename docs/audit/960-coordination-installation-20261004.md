# #960 — instalação de coordenação, 04/10/2026 UTC

**Estado: instalação real parcial; operação conjunta ainda pendente.**
AGENTS.md lido. Issue #960 e branch `release/2026-10-04-instagram-960` existentes.
Esta rodada alterou somente `.env.example`, o adendo do runbook e esta auditoria.
Leitura local e revisão documental; nenhuma rede, banco, perfil, credencial ou teste executado.
PR → Project update → Review → Approval → Merge → Deploy/Rollback continuam pendentes
para estes novos diffs; esta documentação não autoriza ações operacionais.

## Fontes e alcance

Artefatos em `tmp/resume-finalization-20261004/`:

- `provision-result.json`, `n8n-installation-metadata.json`, `n8n-proxy-proof.json`;
- `synthetic-acl-format.json`, `final-validation.json` e logs finais correspondentes;
- pareceres `provision-independent.md`, `provision-fix.md`, `redis.md`, `webshare.md`, `deploy.md`.

Fontes locais atuais: provisionador, instalador/validador do túnel, preflight,
`coordination_redis.rb`, `proxy.rb`, workflows blue-green e auditorias de proxy/Íris/Atlas.
Pareceres descrevem revisões anteriores: achados e resultados não comprovam execução remota.
Bloqueio do diagnóstico, ausência de SSM e histórico `906f…` vêm do relato operacional
fornecido para esta consolidação; não foram reconsultados nesta rodada.

## Instalação observada no n8n

Execução real às **14:42:35 UTC**, duração 10,39 s, exit **1** (`provision-result.json`).
Fonte executada: SHA-256 `a0b0c00d5e73de0086bdcff935371961fe365e7f4dbf75f8ddfbb0a5c7ee0410`.
`main_merge=false`, `application_deploy=false`; código atual da aplicação não publicado.

Metadados coletados às **14:49:05 UTC**:

- container novo ativo, `read_only=true`, capacidades removidas, **zero restarts**;
- volume `instagram_coordination_data`, bridge nova `instagram-coordination-bridge`;
- publicação exclusivamente `127.0.0.1:6381`; RAM e RAM+swap **256 MiB**, CPU **0,25**;
- **27 serviços existentes com especificações iguais**, nenhuma mudança registrada;
- n8n editor **1/1**, webhook **10/10**, worker **6/6**.

Nenhum Redis existente foi modificado. Há recursos novos parciais a preservar.
`igcoord` **não criado**; parâmetros SSM **não criados**; autenticação não consultada
nos metadados (`auth_not_queried=true`). Não há prova de túneis instalados nas stacks/M4.

## Bloqueio de ACL e limite do diagnóstico

A execução parou em `epoch_write_ACL_failed:0`, antes de liberar o usuário SSH.
Hipótese: o matcher esperava `This user …`, mas Redis responde `User ig_hub …`.
A divergência foi comprovada **somente em Redis local sintético**:
GET recebeu `OK`; SET/DEL receberam `User ig_hub has no permissions to access the
'instagram_tester_coordination:integrity:epoch' key`, com exit 0.
Isso explica um possível falso negativo do checker; **não comprova a ACL do host**.

A fonte atual aceita as duas mensagens de negação para a chave exata.
O host não foi reexecutado após essa correção. Uma tentativa autenticada de diagnóstico
foi bloqueada pela ferramenta; não houve contorno nem confirmação autenticada posterior.
Não atribuir sucesso de ACL, integridade/AOF ou SSH ao simples estado ativo do container.

## Webshare e fronteiras de confiança

Prova às **14:35:55 UTC**: saída **do n8n** via Webshare, CONNECT/HTTP **200/200**,
IPv4 residencial observado igual ao esperado; sem Meta, credencial de proxy ou fallback direto.
Essa prova não cobre caminhos **AWS → túnel → n8n** ou **M4 → túnel → n8n**.

Identidade canônica: `INSTAGRAM_TESTER_PROXY_IDENTITY=IPv4:porta` do upstream Direct real,
sem tag arbitrária, alias ou porta local. Backend/gestor usam a mesma identidade/fingerprint;
o validador rejeita identidade explícita divergente, inclusive em fonte sobrescrita.
Forwarding TCP não filtra destinos HTTP/CONNECT; host/gateway Docker são fronteiras
de confiança. Exclusividade administrativa não é garantida pelo transporte.
Não se registra ampliação de trust/rede das stacks nem entrega de segredo compartilhado.

## Configuração e recuperação escritas, ainda não publicadas

`INSTAGRAM_TESTER_COORDINATION_EPOCH` verifica o marcador persistido `integrity:epoch`.
CA dedicada em `INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE=/run/igcoord/ca.crt`,
passada em `ssl_params` somente à conexão Redis com `VERIFY_PEER`; **não usar
`SSL_CERT_FILE` global** para substituir a confiança TLS das demais integrações.

EC2: SSH encaminha gateway Docker **16381 → 127.0.0.1:6381 no n8n** e
**16380 → IPv4:porta Webshare real**. Containers acessam aliases internos;
host key fixada, credenciais próprias por stack, sem segredo administrativo distribuído.

Parâmetros esperados em cada conta/região AWS da stack (ainda não criados):

| Nome exato | Tipo | Conteúdo |
|---|---|---|
| `/chatwoot/prod/instagram-coordination/ssh-key` | SecureString | Chave SSH dedicada |
| `/chatwoot/prod/instagram-coordination/redis-env` | SecureString | URL Redis autenticada, epoch e caminho CA |
| `/chatwoot/prod/instagram-coordination/ca` | String | CA pública |
| `/chatwoot/prod/instagram-coordination/known-hosts` | String | Host key verificada por canal confiável |

No deploy normal, falha de preflight/boot da green impede parar a blue.
Na recuperação, o assistido fica **OFF somente no overlay**; serviços gerais retornam
com processo/imagem publicados, inclusive blue antiga sem runtime de coordenação.
Rollback não depende de Redis/proxy disponível nem altera ENV base, sessões ou outcomes.
Proteção de convite incerto permanece **24 horas**; sem mudança de TTL ou reset de epoch.

## Resultados finais já disponíveis

Leitura de `final-validation.json` e logs existentes; nenhuma execução nesta rodada:

| Rodada registrada | Resultado |
|---|---|
| `backend-final` | Exit 0; 702 exemplos, 0 falhas, 1 pendente preexistente em quarentena |
| `coordination-offline-final` | Exit 0; 10 testes sintéticos aprovados |
| `provision-offline-final` | Exit 1; 3 testes, 1 falha em `test_new_install_and_rerun_refusal`, `epoch_write_ACL_failed:0` |

Não há nova validação final integral aprovada. CI do último publicado **`906f…`** é
histórico e não aprova estes diffs nem a correção atual; testes locais não homologam o host.

## Próximos passos técnicos, sujeitos à aprovação operacional

1. Confirmar ACL no host: leitura do epoch permitida, escrita/remoção negadas aos dois usuários.
2. Revisar e continuar manualmente a instalação parcial **sem reset/re-run do NEW ONLY**:
   preservar volume, epoch, certificados e credenciais; concluir SSH restrito após validar ACL/AOF.
3. Obter host key por canal confiável, preparar os quatro SSM e permissões mínimas por stack;
   instalar/provar túneis AWS e M4 com suas chaves dedicadas, sem expor segredo administrativo.
4. Provar coordenação entre as duas stacks, TLS/epoch, exclusão de convites e `WAITAOF`
   na mesma conexão; verificar persistência após restart sem alterar epoch ou proteção de 24 h.
5. Fechar a validação final do código corrigido e review/CI do commit correspondente;
   obter aprovação antes de merge/deploy e ativação. Homologação Meta continua pendente.

## Fechamento local pelo coordenador — complemento da leitura documental

Após a redação inicial de Clio, o fake de ACL passou a emitir a negação real com usuário e chave;
foi acrescentado um caso que rejeita NOAUTH sem liberar SSH. **4/4 testes de provisionamento
fictício passaram**, incluindo preservação de instalação parcial. O checker do host não foi reexecutado.
O helper de suspensão usa criação exclusiva de temporário com modo 0600, mantendo o rename atômico.

Recibos locais finais: **702 exemplos backend, zero falhas e uma pendência antiga**; proxy focal
**10/0** após refatoração semântica equivalente; **135/135 Node**; **10/10 runtime Python**;
RuboCop **16 arquivos sem infrações**, ESLint do escopo sem erros/avisos; autoload e formatos do Guia em dia.
Baterias se sobrepõem e não devem ser somadas. A execução ampla local da recuperação foi
interrompida pelo limite externo de 360 s, após 16 métodos concluídos; os 11 métodos restantes
passaram numa seleção separada em 57,43 s. Isso cobre os **27 métodos**, mas não é uma execução
integral concluída. O CI executará a bateria completa, sem modificar os limites do produto.

Nexo aprovou correção do fake, temporário e inclusão das duas suítes Python no CI. Argos
aprovou os ajustes finais de lint/nomes sem novo bloqueador de código. A aprovação é para
commit/CI, não para operação: ACL real, SSH/SSM/túneis e integração entre stacks seguem pendentes.
O novo container continua isolado; nenhuma tentativa de contornar o bloqueio da ferramenta foi feita.

A composição local inclui a main até `fa67d4cbbdaf2db722fe00d0a5cff2923c9b89d1`.
Durante os testes a main avançou para `5b9807f5856dd1dac6ca8ec45a467eb89ec633ba`, incluindo
atualização do processo de fila/CI e paginação. Não sobrescrever nem presumir excluídas essas mudanças:
antes de merge/deploy, validar o commit combinado efetivo e o processo de release em vigor.
CI do novo head será registrado na PR; o resultado antigo `906f…` não comprova este complemento.
