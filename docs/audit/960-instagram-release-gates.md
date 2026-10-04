# Instagram — fechamento dos três gates de publicação (#960)

## Escopo e decisão de publicação

Rodrigo autorizou preparar a versão conjunta, resolver o acesso Webshare e fechar a coordenação, preservando o Redis do Chatwoot. Esta rodada não autoriza nem executa merge na main, deploy ou rotação de segredo. O pedido de fechar os gates não será usado para compartilhar a credencial geral do Redis, aplicar rede/ACL ou assumir custo sem aprovação específica do risco.

Candidato `release/2026-10-04-instagram-960`: main `34eb8ddf1b0af0e530110a3cfb73f7d05cf3578e` combinada com `97d4a3be60327cca3082c403ea30c11fb71fff1f` (#956, que contém #937). As branches originais foram preservadas. Nenhum conflito textual. Os cinco arquivos auto-mesclados foram revisados; geração e conferência do Guia/formatos não produziram diferença adicional.

A consulta atual corrigiu o diagnóstico anterior de PR não mesclável: #937 e #956 estavam CLEAN/MERGEABLE. Porém, a main tinha 14 commits posteriores à base testada. Ser mesclável não equivale a testar a combinação com esses commits.

Um único merge futuro do candidato evita duas rodadas de deploy blue-green em fila. O processo e a janela de retorno estão em `docs/processo-de-release.md`. Este candidato permanece em rascunho e não está autorizado para produção.

## Equipe e evidências locais

| Agente | Responsabilidade | Resultado desta rodada |
|---|---|---|
| Nexo | Composição da versão e revisão independente | Main recente, Primeiros Passos/Central e bits existentes preservados; revisão final depende dos recibos completos |
| Atlas | Proxy e acesso ao painel do fornecedor | Código aceita apenas IP; painel da conta não acessível pela ferramenta, sem leitura de credenciais |
| Gauss | Coordenação e risco Redis | Confirmou que namespace não limita permissões; compartilhamento da credencial geral exige decisão específica |
| Íris | Compatibilidade e ativação do runtime | Atualizar o conjunto #937+#956; apenas os dois scripts antigos não bastam |
| Argos | Segurança e diagnóstico remoto | Payload revisado; conexão autenticada condicionada a DNS privado e TLS verificado |
| Turing | Seleção e execução de testes frontend | Duas invocações inválidas de ambiente preservadas; execução final do coordenador descrita abaixo |

A execução via Codex no Mac não equivale ao painel nativo de subagentes do ChatGPT. Relatórios e logs de execução estão em scratch próprio da worktree; não se publicam prompts, logs privados ou arquivos de destino de infraestrutura.

## Gate 1 — versão integrada

- Backend: 6.497 exemplos, zero falhas, 76 pendentes preexistentes, em 593 arquivos. Avaliações pagas permaneceram desligadas. Não contar pendentes como testes aprovados.
- Frontend focal: 274 testes aprovados em 20 arquivos, incluindo Instagram, autenticação, Guia, Primeiros Passos e vídeos da Central.
- Node: 134 testes aprovados; zero falhas, cancelamentos ou skips na execução final. Não houve chamadas Meta.
- Build forçado, autoload, Guia, formatos, Central e traduções concluíram com exit 0. Traduções: 17.462 mensagens; Central: 175 artigos. Avisos preexistentes de depreciação, sourcemap, Browserslist e tamanho de chunks permanecem nos logs.
- Os resultados de browser/CI da #956 não são reapresentados como execução desta combinação. O CI do novo SHA deve ser conferido antes do aceite da versão; recibo final será vinculado no comentário da PR.
- Duas tentativas anteriores foram inválidas: dependências por symlink fora da worktree impediram setup do Vitest; outra invocação colocou TMPDIR dentro do Git, contrariando a proteção do perfil. Ambas estão registradas, não convertidas em PASS. Dependências foram materializadas offline com lockfile congelado; execução final usou o ambiente correto, sem alterar produto, testes, guards ou prazos.

## Gate 2 — Webshare: bloqueado por autenticação do fornecedor

Às 12:43 UTC de 04/10/2026, os dois servidores CURRENT fizeram um único GET ao endpoint público Webshare fornecido por Rodrigo. Ambos retornaram HTTP 407. Sem credenciais enviadas, chamada à Meta, fallback direto, alteração de configuração ou repetição do convite.

Ruby e Node aceitam somente modo IP no código atual. Usuário/senha exigem alteração coerente do contrato e análise do transporte até o proxy; o HTTPS do destino, isoladamente, não demonstra proteção da credencial do proxy. Nenhum modo novo foi implementado ou ativado nesta rodada.

O agente não conseguiu acessar a aba autenticada Webshare. Plano, quantidade de origens autorizáveis e opções de transporte não foram confirmados. Próxima ação humana mínima: disponibilizar a página do plano/autorização, com credenciais ocultas, para leitura. Não pedir senha/cookie/HAR pelo chat. A credencial exposta anteriormente não será reutilizada; qualquer rotação exige avaliar consumidores antes.

O gate só fecha depois de corrigir a autenticação na opção aprovada e obter prova de saída pelo proxy, sem acesso direto, nos dois backends e no gestor dedicado. Cadastro manual de IPs atuais não comprova persistência após blue-green ou mudança da rede do Mac.

## Gate 3 — coordenação: risco identificado, não aplicada

Diagnósticos somente leitura às 12:25–12:29 UTC confirmaram:

- Ambas as aplicações executavam main `34eb8ddf1b0af0e530110a3cfb73f7d05cf3578e` e o mesmo App pai Meta. Na versão publicada inspecionada, a fonte desses IDs é ENV; na versão nova será necessário conferir os metadados persistidos.
- Hub2You configura o coordenador no mesmo fingerprint de endpoint do seu Redis geral; DNS privado e PING autenticado funcionaram. O payload diagnóstico exigiu verificação TLS de certificado. Não se afirma igualdade das credenciais. A configuração de coordenação da Autonom.ia está ausente.
- Cada instalação tem Redis privado próprio. Não há peering ativo ou rotas de peering/transit nas rotas observadas. Os endereçamentos não se sobrepõem; nenhuma conexão privada comum foi demonstrada.
- Os grupos Redis inspecionados usam AUTH token, sem user groups RBAC associados. Isso não prova permissões restritas por prefixo.

Não copiar a credencial geral Hub para Autonom.ia: namespace organiza chaves, mas não restringe acesso. Peering, rotas e security groups ampliariam a superfície de acesso; restrição por porta/origem não limita comandos Redis. Nenhuma dessas mudanças foi executada.

Recomendação de segurança a decidir: coordenação isolada dos dados do Chatwoot, com acesso privado e credenciais próprias, ou credencial realmente restrita se houver autorização explícita para configurar RBAC. Infraestrutura nova, custo e migração dos outcomes precisam de plano/review antes da aplicação. Não foi criado outro Redis nem componente HTTP improvisado.

Prova adicional do candidato: 44 exemplos de cache e controle em PostgreSQL/Redis descartáveis reais passaram, incluindo valores e expiração absoluta de sentinelas, CAS concorrente e publicação. Boot OSS separado: 11 exemplos, zero falhas. Essas baterias têm sobreposição com a suíte ampla; não foram somadas para inflar cobertura. Elas não provam conectividade produtiva entre stacks.

## Publicação e retorno — ainda não executados

1. Conferir CI/review do SHA conjunto, resolver os gates operacionais e obter novo de acordo explícito.
2. Publicar uma versão coerente de backend, publisher, forced-wrapper, waiter e gestor; não atualizar apenas um fragmento do protocolo.
3. Salvar os cinco metadados no SuperAdmin antes de iniciar o gestor; preservar campos OAuth e caixas existentes. Não fazer rollout geral de contas antes da prova real.
4. Testar uma conta própria em cada instalação: convite/aceite quando necessário, OAuth, webhook e mensagem de ida/volta. Comprovar primeira e segunda publicação da sessão e alerta recebido.
5. Se falhar, suspender novas operações assistidas e aplicar o rollback conjunto previamente aprovado. OFF por conta não reverte protocolo. Não apagar sessão, outcomes, locks, tokens, caixas ou marcadores.

Nenhum merge na main, deploy, reinício de Redis, FLUSH, alteração de ACL/eviction, peering, security group, rotação de senha ou mudança de credenciais foi executado. Os diagnósticos SSM criaram somente execuções transitórias; Redis recebeu apenas comandos de conexão e PING, sem leitura/varredura de chaves produtivas.

## Próximas decisões humanas exatas

- **Webshare:** permitir leitura do painel do plano/autorização, com credenciais ocultas. Confirmar a opção e os consumidores antes de qualquer alteração de autenticação.
- **Coordenação:** aprovar o desenho isolado e seu custo/limites antes de provisionar. A alternativa de compartilhar a credencial geral Hub foi explicitamente rejeitada como mudança silenciosa.
- **Release:** aprovação separada somente após evidências; esta preparação não é pedido de merge/deploy.

## Revisão final local

Nexo aprovou a composição e os recibos para commit/push ao CI, sem aprovar produção. Argos confirmou os bloqueios e exigiu a explicitação do risco de credencial/rede; as duas precisões documentais foram aplicadas. RuboCop focal: 65 arquivos sem infrações; ESLint focal: 36 arquivos, zero erros e 48 avisos conhecidos de i18n. Nenhuma regra, teste ou prazo foi reduzido. O recibo do CI final pertence ao SHA que será publicado e será registrado na PR, não presumido aqui.
