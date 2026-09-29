# Operação controlada de Relacionamentos — Issue 757 / PR 760

Rodrigo autorizou merge/deploy, três extensões ligadas e validação posterior em produção.
Este workflow manual não altera IAM, secrets, autenticação ou os workflows blue/green.
Foi necessário porque o perfil local Hub2You está válido, mas o perfil local Autonom.ia
é inválido. Usa o mesmo papel OIDC já utilizado pelos deploys oficiais.

## Modos

- `preflight`: consulta alvo atual saudável, ponteiros HTTPS/SSM, instância anterior
  registrada/preservada, SHA de web/worker e contas elegíveis; nenhuma escrita de aplicação.
- `enable`: exige confirmação e SHA exato; executa smoke transacional e habilita somente
  relationships_navigation / relationships_attributes / relationships_company_media
  nas contas ativas elegíveis. Preserva Companies/custom_attributes/CRM e demais flags.
- `verify`: repete smoke e confirma as flags; registros QA são revertidos pela transação.
- `disable`: retorno funcional somente das três extensões, sem apagar definições/valores.

Conta suspensa não é alterada. Sem alteração dos padrões de criação de contas futuras,
sem migração, envio a clientes, inferência paga, upload ou processamento de acervo.
O smoke usa autenticação normal de usuário sintético não persistido e rotas reais da
aplicação carregada na imagem em produção; não é um teste de navegador externo. Toda
escrita de QA fica em transação revertida, e callbacks assíncronos de QA são interceptados e contabilizados, sem envio
somente no processo de verificação. O adapter dos processos web/workers não é alterado.
A operação de habilitação ocorre somente após o smoke aprovado, com lock e verificação
de que nenhuma outra flag foi modificada. O artifact registra IDs e flags, não nomes,
conteúdo de clientes, tokens ou credenciais.

## Execução

Selecionar manualmente tenant, action, expected_sha e confirm_production. `expected_sha`
é o commit efetivo da imagem, não o SHA de uma atualização exclusiva de documentação.
Falha de health, rollback, SHA ou smoke interrompe a operação. Não há retry de escrita
nem rollback automático de dados. A escrita de flags é transacional e idempotente.
Após publicar aplicação, validar novamente o rollback imediato; o anterior de dois
deploys atrás é removido pelo workflow existente. Não executar deploy duplicado.

## Proteções operacionais

Cada job compartilha a trava de concorrência do blue/green da respectiva stack;
nenhuma ativação deve concorrer com uma troca de tráfego. O relatório é comprimido
antes do transporte SSM, com limite conferido antes da escrita, e descomprimido com
limite no runner. O command_id e a evidência recebida são persistidos antes da
consulta posterior; falha de health pós-operação não apaga a evidência anterior.

Para rollback do binário, desabilitar as extensões e aguardar/esvaziar somente os
jobs de thumbnail Relationships::CompanyPreviewJob antes de retornar ao código
anterior, que não conhece essa classe. Não esvaziar filas inteiras nem jobs de IA,
mensagens ou clientes. Os originais não são apagados; derivados podem ser refeitos.


## Contrato do papel de deploy

O primeiro preflight OIDC interrompeu antes de enviar comandos SSM: a consulta em lote
GetParameters não está no contrato utilizado pelos workflows de deploy. A operação
passou a usar as quatro leituras GetParameter singulares já existentes. Nenhuma
permissão foi acrescentada. Teste unitário cobre o conjunto e os alvos de rollback.
