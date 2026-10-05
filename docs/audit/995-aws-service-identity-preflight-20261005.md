# #995 / PR #1003 — identidade AWS de serviço: preflight e plano

> Registro histórico da etapa de preparação. A execução posteriormente autorizada,
> seus recibos e os gates ainda pendentes estão na
> [auditoria operacional de 05/10](995-vps-runtime-operations-20261005.md).
> Os resultados abaixo preservam o contexto e o horário da observação original.

Data: 05/10/2026. Escopo desta frente: leitura de código, documentação oficial e metadados AWS; somente este relatório foi escrito. Nenhuma role, policy, trust anchor, profile, certificado, chave, documento ou parâmetro foi criado/alterado. Não houve StartSession, SendCommand, execução do publisher ou acesso à Meta nesta frente.

## Conclusão operacional

Não foi demonstrado bloqueio IAM de provisionamento: os dois principais administrativos têm AdministratorAccess e a simulação das ações necessárias retornou allowed. Isso não equivale a execução autorizada pelo serviço nem verifica integralmente SCPs/controles externos. Os recursos de serviço ainda não existem. A implantação integral permanece dependente da preparação da VPS, cuja execução anterior sofreu rejeição automática, registrada em `tmp/approved-1003-20261005/HANDOFF.md`. Não repetir essa operação por outro wrapper, ferramenta ou rota. IAM não será provisionado prematuramente enquanto as dependências operacionais estiverem bloqueadas.

A autorização informada pelo coordenador abrange merge/deploy OFF, runtime VPS n8n, identidades AWS dedicadas, HTTPS privado e rollback (Issue #995, comentário 5997020246). O runbook e os exemplos continuam sendo contratos de configuração; não são recibos de execução. Esta auditoria não altera os gates ou a autorização de ativação.

## Evidência obtida em AWS

CLI descoberta: `/Users/rodrigosilva/.local/bin/aws`; Python `/usr/bin/python3`. Região das consultas: `us-east-1`. Credenciais administrativas existentes foram utilizadas somente em leitura e não foram exibidas ou copiadas.

| Stack | Perfil administrativo | Conta confirmada por STS | Principal administrativo observado |
| --- | --- | --- | --- |
| hub2you | hub2you | 354307071110 | arn:aws:iam::354307071110:user/cursor-hub2you |
| autonomia | financial | 140023375763 | arn:aws:iam::140023375763:user/terraform_client |

Nas duas contas: `rolesanywhere list-trust-anchors` e `list-profiles` retornaram listas vazias; `iam list-roles` não encontrou trust para `rolesanywhere.amazonaws.com`; `ssm describe-document --name ChatwootInstagramPublisherHostKey` retornou `InvalidDocument`, indicando documento inexistente.

`iam list-attached-user-policies` mostrou AdministratorAccess em ambos. `iam simulate-principal-policy` retornou allowed, sem MissingContextValues, para CreateRole, PutRolePolicy, UpdateAssumeRolePolicy, TagRole, rolesanywhere:CreateTrustAnchor, CreateProfile, PutAttributeMapping, ImportCrl, EnableCrl, ssm:CreateDocument, UpdateDocumentDefaultVersion e PutParameter. Não houve tentativa real dessas ações.

| Evidência no instante consultado | Hub2You | Autonom.ia |
| --- | --- | --- |
| CURRENT String/Standard | i-059b5ed9f63bb4d59, v394 | i-033c8e5a0bdfcd984, v383 |
| SSM do CURRENT | Online, agente 3.3.5226.0 | Online, agente 3.3.5226.0 |
| Name do CURRENT | chatwoot-hub2you-prod-ec2-green-37307521541 | chatwoot-autonomia-prod-ec2-green-37307521591 |
| Correspondências do seletor IAM | 6: 2 running, 4 stopped | 3: 2 running, 1 stopped |
| Outra instância running observada | i-06a683f197980ef20, sufixo 37331059255 | i-0fc4a7b5611bf768e, sufixo 37331059104 |
| Parâmetro da chave pública do publisher | String/Standard, v1 | String/Standard, v1 |

Todos os CURRENT tinham Project=chatwoot-autonomia, Environment=prod e ManagedBy=github-actions. O conjunto adicional de instâncias running é compatível com blue/green em andamento; não prova conclusão ou promoção. Reconsultar CURRENT depois do deploy antes de associar a nova chave SSH.

O parâmetro `/chatwoot/prod/instagram-tester-publisher-public-key` contém a mesma chave pública ED25519 nas duas contas: fingerprint SHA256 `4IhD3nnbkiUbkiy6cAIy2ysGWkU12H6T1HQPsCblOa8`. Somente algoritmo, versão e fingerprint foram registrados. Isso não identifica o dono da chave privada. O plano VPS exige duas chaves novas distintas, geradas na VPS; não reutilizar nem copiar a privada correspondente.

`describe-parameters` confirmou a presença de `/chatwoot/prod/instagram-tester-env` SecureString v7/v6, `/chatwoot/prod/env` SecureString v370/v346 e parâmetros de coordenação. Seus valores secretos não foram lidos nesta frente. A identidade do publisher não precisa receber acesso a eles.

## Recursos propostos, ainda não existentes

Uma CA exclusiva deste runtime, com custódia offline fora da VPS; dois certificados cliente; uma role, um trust anchor e um profile Roles Anywhere em cada conta. Não criar IAM user ou access key estática. Não reutilizar roles de GitHub Actions, bastion ou EC2.

| Item | Hub2You | Autonom.ia |
| --- | --- | --- |
| Nome da role proposta | chatwoot-instagram-publisher-hub2you-vps | chatwoot-instagram-publisher-autonomia-vps |
| ARN da role proposta | arn:aws:iam::354307071110:role/chatwoot-instagram-publisher-hub2you-vps | arn:aws:iam::140023375763:role/chatwoot-instagram-publisher-autonomia-vps |
| Nome do trust anchor proposto | chatwoot-instagram-vps-hub2you | chatwoot-instagram-vps-autonomia |
| Nome do profile proposto | chatwoot-instagram-publisher-hub2you-vps | chatwoot-instagram-publisher-autonomia-vps |
| CN do certificado proposto | igpub-hub2you-srv707880 | igpub-autonomia-srv707880 |
| OU do certificado proposto | hub2you | autonomia |
| Role session name proposto | igpub-hub2you-vps | igpub-autonomia-vps |
| Perfil AWS dentro do publisher | hub2you | financial |

Os nomes são uma proposta concreta para execução; ARNs de trust anchor/profile dependem dos UUIDs retornados pela criação e não podem ser inventados. Região fixa: us-east-1. Certificados devem ser X.509v3, CA=false, DigitalSignature e assinatura SHA256 ou mais forte. Para a CA: CA=true, keyCertSign e cRLSign. Proposta de operação: certificado cliente de 30 dias, renovação até o dia 20; duração de CA e responsável por custódia/renovação devem ser registrados antes da emissão. O helper renova credenciais AWS, não o certificado.

## Trust, profile e permissões

Trust da role, renderizado separadamente com a conta, CN, OU, nome da sessão e ARN real do trust anchor de cada stack:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "rolesanywhere.amazonaws.com"},
    "Action": ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"],
    "Condition": {
      "ArnEquals": {"aws:SourceArn": "ARN_REAL_DO_TRUST_ANCHOR_DA_STACK"},
      "StringEquals": {
        "aws:SourceAccount": "CONTA_DA_STACK",
        "aws:PrincipalTag/x509Subject/CN": "CN_EXATO_DA_STACK",
        "aws:PrincipalTag/x509Subject/OU": "OU_EXATA_DA_STACK",
        "sts:RoleSessionName": "NOME_FIXO_DA_SESSAO_DA_STACK"
      }
    }
  }]
}
```

Usar igualdade obrigatória; não substituir por IfExists ou remover condições para contornar falha. Criar profile contendo somente a role da stack, `durationSeconds=900`, `acceptRoleSessionName=true`; mapear explicitamente x509Subject CN e OU via PutAttributeMapping. Criar inicialmente desabilitado e habilitar apenas na etapa de prova de identidade. Role MaxSessionDuration=3600 é o mínimo configurável da role; a duração efetiva fica limitada pelo profile de 900 segundos e pelo pedido do helper de 900 segundos.

Base da policy: `scripts/instagram_testers/runtime/vps/iam/publisher-policy.template.json`. Substituições aprováveis:

- REQUIRED_ACCOUNT_ID: conta da stack.
- REQUIRED_STACK_INSTANCE_NAME_PATTERN: `chatwoot-hub2you-prod-ec2-green-*` ou `chatwoot-autonomia-prod-ec2-green-*`.
- REQUIRED_APPROVED_PRINCIPAL_SESSION_ARN_PATTERN: ARN SSM `arn:aws:ssm:us-east-1:CONTA:session/PREFIXO_REAL_COMPROVADO-*`. Não usar ARN STS assumed-role, não inferir o prefixo a partir de aws:userid e não liberar todas as sessões da conta.

Preservar as cinco primeiras concessões: GetParameter apenas de CURRENT; SendCommand/StartSession nas instâncias com as quatro condições de tags; SendCommand apenas do documento público restrito; StartSession apenas do documento AWS-StartPortForwardingSession; ListCommandInvocations somente us-east-1. Não conceder GetParametersByPath, escrita de parâmetros, KMS, Secrets Manager, Redis, CreateDocument, alteração de tags ou AWS-RunShellScript ao runtime.

Para TerminateSession, manter o ARN SSM comprovado e acrescentar a condição documentada para assumed roles:

```json
"Condition": {
  "StringLike": {
    "ssm:resourceTag/aws:ssmmessages:session-id": "${aws:userid}*"
  }
}
```

OpenDataChannel permanece restrito ao mesmo padrão SSM comprovado. A condição de propriedade acima pertence ao statement TerminateSession; não supor que a mesma condição seja suportada por ssmmessages.

### Como comprovar o prefixo sem conceder acesso amplo

Na etapa operacional autorizada, começar com a policy limitada às cinco primeiras concessões, sem OpenDataChannel/TerminateSession. Fazer uma única chamada StartSession sob a identidade de serviço para o CURRENT e documento de port-forward com porta22, por um cliente SDK que emita somente SessionId; não conectar SSH, não enviar payload e não executar o publisher. O principal administrativo encerra imediatamente essa sessão em bloco de cleanup. A resposta integral contém tokens e não deve aparecer em logs.

Com o SessionId real, renderizar as duas concessões restantes; comprovar abertura/encerramento da própria sessão e recusa de sessão alheia. Se o padrão não for estável com o role-session-name fixo, interromper a ativação e revisar. Não ampliar o Resource para `*` como correção. Essa prova é uma operação futura; não foi realizada nesta auditoria.

## Chaves, helper e configuração da VPS

Cada chave privada X.509 e cada chave SSH deve ser gerada no host de serviço, em diretório privado da stack. Enviar apenas CSR para assinatura pela CA offline e devolver apenas certificado/cadeia pública. AWS recebe somente o certificado público da CA via sourceType=CERTIFICATE_BUNDLE. A CA privada não fica na VPS, em SSM, no repositório ou no artefato de deploy.

Paths por stack, dono igpub-STACK, arquivo0600, home e subdiretório0700:

- `/var/lib/instagram-publisher-STACK/publisher/rolesanywhere.key` e `rolesanywhere.crt`;
- `/var/lib/instagram-publisher-STACK/publisher/id_ed25519`;
- `/var/lib/instagram-publisher-STACK/publisher/aws-config`.

Helper oficial proposto: versão1.8.5, path `/opt/instagram-meta-tools/aws_signing_helper-1.8.5`, root-owned0755 e ancestrais protegidos. A documentação AWS consultada publica para Linux x86-64 o SHA256 `beec9ed1c492d93db809890f16713e3556353294b823c2184ad4e891f1b2b54d`, URL `https://rolesanywhere.amazonaws.com/releases/1.8.5/X86_64/Linux/Amzn2023/aws_signing_helper`. Confirmar arquitetura e compatibilidade real do binário antes da instalação; isso não autoriza contornar o bloqueio existente das dependências.

`aws-config` deve conter exatamente o perfil esperado, region e credential_process, conforme os exemplos do repositório. Modelo para Hub2You, com os dois ARNs UUID reais ainda pendentes:

```ini
[profile hub2you]
region = us-east-1
credential_process = /opt/instagram-meta-tools/aws_signing_helper-1.8.5 credential-process --certificate /var/lib/instagram-publisher-hub2you/publisher/rolesanywhere.crt --private-key /var/lib/instagram-publisher-hub2you/publisher/rolesanywhere.key --trust-anchor-arn ARN_REAL_TRUST_ANCHOR_HUB2YOU --profile-arn ARN_REAL_PROFILE_HUB2YOU --role-arn arn:aws:iam::354307071110:role/chatwoot-instagram-publisher-hub2you-vps --role-session-name igpub-hub2you-vps --session-duration 900 --region us-east-1
```

Autonom.ia usa `[profile financial]`, conta140023375763 e os paths/ARNs/nome de sessão da sua stack. `publisher.env` conserva `AWS_SHARED_CREDENTIALS_FILE=/dev/null`, `AWS_EC2_METADATA_DISABLED=true`, AWS_CONFIG_FILE exclusivo e opt-in `INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT=ChatwootInstagramPublisherHostKey`. Não usar helper serve/update, arquivo credentials, SSO interativo, metadata EC2 ou credenciais de pessoa. Não imprimir diretamente a saída credential-process: ela contém credenciais.

## Ordem de provisionamento para o executor, após resolver as dependências

1. Revalidar SHA aprovado, OFF, CURRENT pós-deploy, tags reais, estados dos gestores e rollback. Preparar armazenamento da CA, CSR/certificados e os JSONs públicos revisáveis. Nenhum serviço Instagram inicia nessa etapa.
2. Criar em cada conta o documento Command/JSON `ChatwootInstagramPublisherHostKey` a partir de `iam/ssm-publisher-host-key-document.json`, sem parâmetros. Ler de volta conteúdo/default version e comparar com o artefato; não usar documento genérico como fallback.
3. Criar trust anchor CERTIFICATE_BUNDLE com somente certificado público da CA e habilitado; guardar ARN/ID retornados. Criar role com trust exata e policy inicial das cinco concessões. Criar profile desabilitado com somente essa role,900s e acceptRoleSessionName; aplicar mapeamentos CN/OU. Importar a CRL válida da CA, habilitada e associada ao trust anchor. Ler de volta todos os recursos e comparar.
4. Provisionar helper e arquivos privados da stack; executar `env/verify-pair.py`, que não chama AWS/helper. Depois habilitar o profile para o teste e, como igpub-STACK, consumir o helper pelo CLI/SDK e emitir apenas STS Account/Arn/tempo. Confirmar role exata e independência de Mac/SSO. Provar recusa de CA/certificado/OU/CN da outra stack e de role-session-name diferente.
5. Comprovar SessionId e finalizar a policy conforme a seção anterior, com cleanup administrativo da sessão de prova. Validar negativas sem executar shell genérico, publisher ou Meta. Não confundir policy simulator com prova real de acesso.
6. Gerar duas chaves SSH distintas na VPS. Registrar somente fingerprints. Depois da parada coordenada dos publishers Mac e do fim do blue/green, atualizar somente o parâmetro String `/chatwoot/prod/instagram-tester-publisher-public-key` de cada conta com a respectiva pública; associar a mesma pública ao forced publisher do CURRENT usando o installer revisado. Reconsultar CURRENT antes e depois para detectar troca durante a operação.
7. Comprovar forced command, sudoers e fingerprint do CURRENT; preservar a pública/versionamento anteriores para rollback. Após a aceitação de identidade/transporte e os demais gates do runbook, o coordenador pode seguir com a ativação integral aprovada. Este relatório não inicia unidades nem altera OFF.

Comandos AWS previstos, todos futuros: `ssm create-document --document-type Command --document-format JSON --name ChatwootInstagramPublisherHostKey --content file://DOCUMENTO_REVISADO`; `rolesanywhere create-trust-anchor --cli-input-json file://TRUST_ANCHOR_REVISADO`; `iam create-role --role-name NOME_DA_STACK --max-session-duration 3600 --assume-role-policy-document file://TRUST_RENDERIZADA`; `iam put-role-policy --role-name NOME_DA_STACK --policy-name InstagramPublisherRuntime --policy-document file://POLICY_RENDERIZADA`; `rolesanywhere create-profile --name NOME_DA_STACK --role-arns ARN_ROLE_DA_STACK --duration-seconds 900 --accept-role-session-name --no-enabled`; `rolesanywhere put-attribute-mapping --profile-id ID_REAL --certificate-field x509Subject --mapping-rules '[{"specifier":"CN"},{"specifier":"OU"}]'`; `rolesanywhere import-crl --name NOME_CRL_DA_STACK --trust-anchor-arn ARN_REAL --crl-data fileb://CRL_PEM_REVISADA --enabled`. Cada chamada usa explicitamente o perfil administrativo correto e `--region us-east-1`. As formas dos comandos Roles Anywhere foram verificadas com `--generate-cli-skeleton input`, sem chamadas de criação.

## Forced SSH e sobrevivência ao blue/green

Referências: `.github/workflows/deploy-hub2you-blue-green.yml` e `deploy-autonomia-blue-green.yml`, função de configuração do Instagram publisher. Os workflows leem o tipo e a pública do parâmetro SSM e executam `runtime/install-remote-publisher.sh` com a chave pelo stdin. Isso torna a fonte SSM necessária para os próximos deploys; alterar somente authorized_keys no CURRENT não persiste.

O installer instala `chatwoot_publisher`, forced command `/usr/bin/sudo -n /usr/local/libexec/instagram-tester-publisher-root`, sem PTY, agent forwarding, X11 forwarding ou port forwarding. O sudoers concede somente esse comando sem argumentos. O wrapper recusa SSH_ORIGINAL_COMMAND/argumentos e executa o publisher Ruby no container chatwoot-web. O installer substitui authorized_keys por uma única chave: não acrescenta as novas preservando as antigas. Portanto a migração altera de fato o acesso do publisher antigo e precisa de corte coordenado. Nenhuma instalação/inspeção remota desse destino foi feita por esta frente.

## Riscos comprovados e limites

- O alcance IAM por tags é maior que CURRENT: no snapshot,6 instâncias Hub e3 Aut. Não trocar para IDs fixos, pois isso quebra o blue/green. A role não pode iniciar instâncias paradas, mas o escopo passa a alcançá-las se outro principal as iniciar.
- AWS-StartPortForwardingSession permite outras portas no alvo autorizado. Porta22 é imposta pelo código `publisher-tunnel.mjs`, não por IAM. Não declarar confinamento de porta por policy.
- ListCommandInvocations usa Resource=* porque a ação não oferece escopo por recurso; pode expor resultados de outros comandos da região. Não foi utilizado para ler comandos nesta auditoria.
- O preflight valida o helper/path/config, não os ARNs/certificados; `verifyAwsAccount` no publisher confirma conta, não role. A aceitação precisa conferir STS Arn exato.
- Cada invocação CLI via credential_process pode solicitar credenciais novamente. Medir o tempo real com a identidade de serviço dentro do orçamento de25s do publisher; nenhuma latência operacional foi medida aqui.
- Certificado/privada roubados permitem novas sessões até revogação/expiração. Roles Anywhere usa CRL importada, não consulta CDP/OCSP. Revogar certificado ou desabilitar trust/profile não elimina automaticamente credenciais já emitidas; duração900s reduz a janela, e incidente requer plano próprio de revogação de sessões/permissões.
- A mesma chave pública hoje nas duas contas não comprova compartilhamento da privada nem seu local. Não investigar/coletar a privada antiga para concluir a migração.

Rollback: manter OFF; parar apenas serviços/mounts Instagram conforme runbook. Antes do corte registrar as públicas anteriores e seus números de versão. Se a migração SSH precisar ser revertida, restaurar a pública anterior na fonte SSM e no CURRENT ainda correto, pelo executor autorizado, sem recuperar/copiar a privada dos Macs. Preservar certificados/chaves/nonces/perfis; não remover em massa identidades IAM. Revogação de credenciais em incidente é operação distinta da reversão de release.

## Custo e fontes oficiais

O plano não cria EC2, NAT, AWS Private CA ou serviço de CA hospedado. IAM Roles Anywhere é anunciado pela AWS sem cobrança adicional; a CA offline evita a contratação AWS Private CA. Run Command e Session Manager nos alvos EC2 atuais não têm cobrança adicional por uso; custos existentes de EC2/rede e eventuais serviços adicionais continuam aplicáveis. A carga de manutenção de certificados/CRL é operacional e não foi monetizada. Não há medição de faturamento nesta auditoria.

- IAM Roles Anywhere e custo: https://aws.amazon.com/about-aws/whats-new/2023/12/iam-roles-anywhere-additional-aws-regions/
- SSM pricing (EC2 vs hybrid, consulta atual): https://aws.amazon.com/systems-manager/pricing/
- Trust, requisitos X.509, SourceArn e CRL: https://docs.aws.amazon.com/rolesanywhere/latest/userguide/trust-model.html
- Mapeamento obrigatório CN/OU: https://docs.aws.amazon.com/rolesanywhere/latest/userguide/attribute-mapping-and-trust-policy.html
- Helper oficial, versão/checksum e credential_process: https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html
- Duração, acceptRoleSessionName e chamada STS: https://docs.aws.amazon.com/rolesanywhere/latest/userguide/authentication-create-session.html
- Escopo de sessões próprias e tag de proprietário: https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html

Referências do repositório: `docs/runbooks/instagram-vps-runtime-995.md`; `scripts/instagram_testers/runtime/vps/iam/README.md`; `iam/publisher-policy.template.json`; `iam/ssm-publisher-host-key-document.json`; `env/hub2you.publisher.env.example`; `env/autonomia.publisher.env.example`; `env/hub2you.aws-config.example`; `env/autonomia.aws-config.example`; `env/check.py`; `runtime/publisher-tunnel.mjs`; `runtime/install-remote-publisher.sh`; `runtime/forced-publisher.sh`. Alguns caminhos curtos nesta lista são relativos a `scripts/instagram_testers/runtime/vps` ou `scripts/instagram_testers`, conforme o prefixo.

## Correção operacional posterior do contrato CRL

A execução autorizada confirmou que ImportCrl recebe CRL em PEM; o exemplo acima
foi corrigido de DER para PEM. A API também rejeitou a CRL inaugural vazia.
O procedimento revisado emite um certificado inaugural real pela CSR, emite o
definitivo com serial distinto e revoga o inaugural como superseded antes de
importar a CRL não vazia. O inaugural nunca vira certificado ativo. Fixture real
OpenSSL: 19/19. Emissão, respostas AWS e readbacks estão na auditoria operacional;
isso não transforma as simulações anteriores em provas de execução.

Fonte do formato: [API ImportCrl](https://docs.aws.amazon.com/rolesanywhere/latest/APIReference/API_ImportCrl.html).
