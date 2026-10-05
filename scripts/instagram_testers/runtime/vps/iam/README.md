# Identidade e permissões pendentes de aprovação

Este diretório contém artefatos de review, não provisiona IAM ou SSM. Não existe
usuário AWS, role, tag, helper ou chave de acesso provisionados por esta entrega.

O publisher existente define os perfis `hub2you` (conta `354307071110`) e
`financial` (conta `140023375763`), região `us-east-1`. Cada usuário `igpub-STACK` deve
receber somente seu perfil, com `credential_process` de serviço aprovado,
credenciais temporárias, `AWS_SHARED_CREDENTIALS_FILE=/dev/null` e metadata EC2
inativa. Não copiar `~/.aws`, SSO, credenciais pessoais ou access keys de um Mac.
O perfil AWS e a chave SSH ficam exclusivamente em
`/var/lib/instagram-publisher-STACK/publisher/{aws-config,id_ed25519}`, 0600;
home e subdiretório 0700. Configuração do serviço em `publisher.env`, root0600.
Browser/manager/gateway não recebem AWS nem têm acesso a esses homes; o grupo
browser do processo publisher permite somente atravessar o runtime0710 e
conectar ao socket0660. As contas mantêm grupos primários exclusivos.
O helper precisa funcionar sem Mac, login interativo ou sessão pessoal, renovar
credenciais e estar protegido contra edição pelo runtime. O método de federação,
principal, trust policy e fonte de credenciais precisam de uma decisão aprovada;
não foram inventados neste template. Nenhum helper é executado pelo preflight.

Antes de aplicar `publisher-policy.template.json`, registrar separadamente por stack:

- `REQUIRED_ACCOUNT_ID`: a conta correspondente acima.
- `REQUIRED_STACK_INSTANCE_NAME_PATTERN`: `chatwoot-hub2you-prod-ec2-green-*`
  na conta Hub2You ou `chatwoot-autonomia-prod-ec2-green-*` na conta Autonom.ia.
  O ARN usa `instance/*` na conta/região exatas, condicionado pelas três tags
  e pelo Name da stack descritos abaixo; não há placeholder de instance-id fixo.
- `REQUIRED_APPROVED_PRINCIPAL_SESSION_ARN_PATTERN`: o ARN de sessões próprias
  do principal real. O prefixo depende da identidade AWS efetivamente provisionada;
  não inferir nome de usuário, `aws:userid`, role session name ou tag. Não substituir
  por `*` ou por todas as sessões da conta.

O template não tem criação/edição de recursos, escrita de parâmetros, KMS,
Redis, Secrets Manager ou shell SSM genérico. `sts:GetCallerIdentity`, usado pelo
publisher para confirmar a conta, não exige uma concessão adicional. A listagem
de resultados de comandos exige `Resource: "*"` porque a ação não oferece escopo
por recurso; a região fica limitada. Esse acesso inclui metadados/resultados de
outros comandos da região e precisa entrar na aprovação do principal.

`AWS-StartPortForwardingSession` permanece o documento do publisher existente.
IAM restringe o alvo e o documento, mas esse documento AWS aceita outras portas
além da 22. A limitação à porta 22 vem do código do publisher, não desta policy.
Uma credencial comprometida ainda pode encaminhar outras portas no alvo aprovado.
Não declarar confinamento a SSH por IAM. Um documento de encaminhamento com porta
fixa exigiria mudar o publisher e está fora desta entrega.

O documento `ChatwootInstagramPublisherHostKey` não possui parâmetros e executa
somente a leitura da chave **pública** do host. Seu provisionamento e manutenção
cabem a uma identidade administrativa separada e aprovada; o runtime não recebe
`CreateDocument`/`UpdateDocument`. Fixar e revisar o conteúdo/default version antes
da ativação. No VPS, o opt-in é
`INSTAGRAM_TESTER_PUBLISHER_HOST_KEY_DOCUMENT=ChatwootInstagramPublisherHostKey`.
Sem opt-in, o comportamento legado do publisher deve permanecer; esta policy
recusa o documento legado, portanto uma configuração VPS incorreta falha fechada.
Sem fallback para `AWS-RunShellScript` ou `ssh-keyscan`.

Referências oficiais consultadas para a revisão:
[autorização SSM](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ssm.html),
[Session Manager IAM](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-quickstart.html),
[GetCallerIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_GetCallerIdentity.html).

### Instâncias efêmeras sem quebrar no próximo deploy

O seletor de instância usa as tags que os dois workflows já aplicam:
Project=chatwoot-autonomia, Environment=prod, ManagedBy=github-actions.
A condição de Name deve ser `chatwoot-hub2you-prod-ec2-green-*` na conta Hub2You
ou `chatwoot-autonomia-prod-ec2-green-*` na conta Autonom.ia. A conta no ARN
continua exata. Conferir essas tags no destino real antes de aplicar a policy.
Documentos têm statements separados; condição de tag não se aplica ao documento.
A identidade não recebe permissão de criar/alterar tags nem documentos.
O runtime consulta CURRENT a cada chamada, não fixa ID de instância nem recorre ao Mac.
O próximo blue/green não exige trocar IDs na policy se conta, região e convenção
de tags/Name permanecerem iguais. Mudanças nesse seletor exigem nova revisão e
aprovação. O parâmetro CURRENT escolhe o destino do publisher, mas não limita
o IAM à instância atual: todas as instâncias que correspondem ao seletor, inclusive
releases anteriores ainda existentes, ficam autorizadas. Registrar esse alcance
na aprovação; a presença das tags nos workflows não comprova as tags no destino real.
Referência oficial: https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html
