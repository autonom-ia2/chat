> Registro histórico. Estado atual, ativação da tela, incidente 502 e pendências: [repasse atualizado](instagram-tester-handoff-910.md).

# Preparação operacional Instagram Tester — #910 / PR #913

Data: 03/10/2026. Esta evidência complementa a avaliação de código e os testes
sintéticos; não declara homologação autenticada da Meta.

Rodrigo autorizou a preparação operacional e o adicional Webshare de até US$ 5/mês.
A jornada real de @placementseg na conta 18 do Hub2You será executada por ele após
publicação. N8n está fora do escopo. Não realizar convites ou mensagens para obter
evidência, nem repetir a chamada Meta anteriormente bloqueada por outra ferramenta.

## Fatos atuais

| Item | Evidência | Limite |
|---|---|---|
| Código publicado no PR | `461f0d11ff486f291aaf47e1aa0714b0a4d90d12`, PR aberto e rascunho | Novos arquivos operacionais ainda precisam de revisão/CI |
| Checks desse commit | 21 aprovados de 22; todos os checks focais Instagram aprovados | RSpec shard 7 falhou duas vezes em duas expectativas SMS fora do diff; nenhum SMS alterado ou check ignorado |
| Versão atualmente publicada nas duas stacks | Imagem `0abffb3ee75b4c7102b927f2d36c553a1e0db25c`, por metadata SSM | Não é a versão nova do onboarding |
| Configurações novas | Overlay SecureString v1 e chave pública String v1 preparados em SSM nas duas stacks; flags OFF; Hub2You allowlist 18, Autonom.ia vazia; namespaces distintos | Ainda não carregados pelos containers da imagem antiga; bindings Meta e coordenação não entregues |
| OAuth existente | App ID configurado em banco nas duas stacks, fingerprints iguais | Não foram lidos AppSecrets; o isolamento de states legados permanece condicional à revisão já documentada |
| Redis atual | Dois endpoints ElastiCache diferentes, ambos com TLS | Não existe prova de coordenador comum; não compartilhar credenciais dos caches de aplicação |
| Webshare | Static Residential atualizado com Unlimited IP Authorizations | Acréscimo recorrente autorizado de US$ 5; checkout total US$ 6,68 após créditos, contra US$ 1,68 antes do adicional |
| Origens autorizadas no Webshare | As duas stacks AWS e o gestor foram adicionados após aprovação específica | Autorização anterior preservada; IPs do blue/green precisam de reconciliação antes de cada ativação |
| Endpoint Direct | Endereço/porta conferidos em modo IP Authentication, sem usuário/senha | O status do fornecedor não comprova autenticação Meta |
| Proxy real por origem | GET público pelo gestor, pelos dois hosts AWS e pelo HTTParty dentro dos dois containers retornou o mesmo IP de saída do endpoint Direct | Transporte real comprovado; nenhuma sessão Meta usada |
| Sessão administrativa | Gestor, store cifrado e publisher implementados; runtime privado Node/Playwright 1.59.1 preparado no M4; janela dedicada de inicialização aberta pelo proxy | Login/2FA pelo operador, publicação e renovação reais ainda não comprovados; supervisor não ativado |

A comparação de App IDs foi uma consulta de leitura limitada a `INSTAGRAM_APP_ID`
e `FB_APP_ID`, com conexão PostgreSQL read-only, timeout e saída somente de presença
e fingerprint. Não carregou Rails, não consultou contas/conversas e não modificou
OAuth. Ausência das ENV OAuth não significa ausência de configuração: o produto
existente consulta InstallationConfig.

## Validação segura

- Testes anteriores: 316 exemplos Ruby; 48 Vitest; 32 Node; 25 Python; wizard
  56 casos/60 imagens de componentes reais com API sintética.
- A bateria adicional Instagram seguida da regressão delimitada no mesmo processo
  executou em snapshot e serviços isolados: **330 exemplos, zero falhas**, job
  `m4-3cec608c54244954b7262b5b9a4e524b`. Uma tentativa anterior foi recusada pelo
  scheduler por proteção térmica; somente a execução posterior conta como prova.
- Contratos Node incluindo transporte operacional, bootstrap e seleção Chrome:
  **47 testes, zero falhas**, job `m4-31018e05dec94ceba8ac4e41583f16ff`.
  ESLint focal passou, job `m4-d762cdefb8cd4bf4befe4c0ba5a8603f`; Node syntax
  passou. Os testes do publisher simulam AWS/SSH, não provam instalação remota ou
  publicação real.
- O probe do proxy usa somente `https://ipv4.webshare.io/`, indicado pelo próprio
  fornecedor. Não chama Meta, não usa credenciais de proxy nem oferece saída direta
  em caso de falha. As três origens passaram; nos hosts AWS, comandos SSM
  `f10d5645-26be-4b57-820a-6ae0fd27a092` e
  `96cf792f-839c-465d-a669-bcfd7fbdc05a` terminaram com sucesso.
  HTTParty nos containers também passou, com comandos
  `8166d775-bcba-4302-bd54-3c7554a01833` e
  `cf835642-2caf-4353-9e4d-e1c6f1d9c276`. Foram usados endereço/porta explícitos,
  zero retries, timeout e nenhum usuário/senha de proxy.

## Limites de publicação

O teste real da conta 18 foi reservado ao Rodrigo; não marcar essa etapa como
executada. Isso não substitui a inicialização da sessão administrativa pelo
operador nem comprova renovação automática. Refresh OAuth não renova cookies.

Não houve merge/deploy, criação de coordenador Redis ou instalação do publisher nos
hosts. A janela de inicialização não lê nem copia cookies, senhas, formulários ou
HARs; o operador conclui login/2FA no perfil dedicado fora de Git e fecha a janela.
Não declarar sessão autenticada pela mera abertura desse navegador.
As tentativas anteriores de append no parâmetro base não concluíram; o preparo
posterior criou dois parâmetros separados com SDK existente e saída sanitizada.
O parâmetro Hub2You já tem 4.028 bytes: novos campos excedem o limite Standard de
4 KB. A solução em revisão usa o SecureString separado
`/chatwoot/prod/instagram-tester-env`, sem migrar o parâmetro base para Advanced,
sem reconstruir seus valores e sem alterar a chave KMS. O overlay aceita apenas
13 variáveis backend explicitamente permitidas e entra como segundo env-file no
web/worker. Chaves duplicadas, sessão JSON, usuário/senha de proxy e variáveis do
gestor são rejeitadas. Fixtures sintéticas válidas/negativas, Bash syntax e YAML
dos dois workflows passaram; não equivalem à execução real do deploy.

Os workflows blue-green extraem o instalador do publisher da imagem revisada,
antes do cutover. A chave pública dedicada em SSM permite instalar o usuário com
comando forçado mesmo com a funcionalidade OFF; a chave privada fica apenas no
gestor. A chave Ed25519 nova foi gerada no diretório privado do operador, fora de
Git; a chave privada não foi lida nem transferida. Transporte usa SSH por túnel
SSM, sem abrir SSH público. Os dois ARNs de GetParameter foram acrescentados e
conferidos nas políticas EC2 das duas contas; todos os demais statements foram
preservados e as versões de `/chatwoot/prod/env` permaneceram iguais. Não houve
apply Terraform, reconstrução do env base, rotação OAuth ou mudança de KMS.
Os templates Terraform de bootstrap fora do workflow não recebem esse overlay;
o caminho suportado nesta entrega é exclusivamente o blue-green revisado.

O fornecedor mantém Auto-Replace por indisponibilidade acima de 15 minutos ligado.
Não foi alterada a opção global, que afeta outros proxies. Mudança real do endpoint
exige nova configuração e binding; não prometer permanência ilimitada do IP.

A ativação inicial controlada é somente Hub2You/conta 18; Autonom.ia permanece OFF.
Coordenação local atende essa ativação única. Ativação simultânea do mesmo App nas
duas stacks depende de coordenador comum e da resolução do isolamento legado;
nenhum dos dois está comprovado. Não declarar conclusão conjunta com dois caches
independentes.

Terraform declara o valor de `/chatwoot/prod/env` sem `ignore_changes`; um apply
amplo pode sobrescrever campos acrescentados fora de IaC. Não usar apply amplo
para preparar esta funcionalidade. Tratar ownership dessa configuração antes de
uma operação posterior de infraestrutura.

Antes de afirmar prontidão, resolver o transporte e supervisão, entregar bindings
reais App/Business/admin/consulta, provar publicação/renovação sem redeploy,
resolver coordenação de uma ativação conjunta e conferir CI do commit final.
Rollback de código usa a imagem/ponto blue-green anterior de cada stack;
desativação preserva caixas, conversas, tokens e papéis existentes. Nunca restaurar
uma sessão invalidada como rollback.
