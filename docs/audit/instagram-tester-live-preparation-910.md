> Registro histórico. Estado atual, ativação da tela, incidente 502 e pendências: [repasse atualizado](instagram-tester-handoff-910.md).

# Preparo operacional complementar — #910 / PR #913

03/10/2026. Código enviado: `952d7448d6f2a61480f57d0e96bbac835b9de7a4`.
Reprodução causal do CI: 46 exemplos/12 falhas antes; 46/0 depois da limpeza
explícita dos contatos do fixture legacy_interleaving. Revisão independente e
RuboCop do arquivo aprovaram. CI completo confirmado no commit acima: 22/22
checks SUCCESS, zero pendências/falhas. Shard 0: 2.311 exemplos, zero falhas, duas
pendências preexistentes; job `111318532281`, run `37162456183`. A revisão continua
separando esse resultado de homologação autenticada Meta.

Vínculos App pai/Business/nome vieram da captura enviada pelo Rodrigo; admin/doc_id
foram fornecidos diretamente por ele. Ambos overlays preparados com todos os
vínculos, automação OFF. Nenhum identificador privado ou credencial neste registro.

Hub2You: overlay SecureString v4, allowlist 18, coordenação TLS no próprio Redis da
stack. O dado protegido foi encaminhado em memória entre configurações da mesma
stack, sem imprimir/salvar arquivo intermediário ou mudar env base/credenciais.
Teste real PING autenticado com verificação de certificado passou no container
existente: comando SSM `22cc29aa-1709-4a5b-9f76-a80ac3ee94f8`, status Success/rc0.
Foi somente PING, sem escrever/listar dados. Não foi criado serviço ou custo novo.

Autonom.ia: overlay SecureString v3, OFF, allowlist vazia. Não recebeu credencial
do Redis Hub2You. Ativação conjunta ainda depende de coordenador comum e da
verificação do isolamento OAuth legado. Pilotar somente Hub2You/18 evita a
concorrência de duas instalações neste estágio.

Supervisor privado recebeu os vínculos fornecidos, porém continua inativo. Login
do navegador interno Codex não prova autenticação do perfil privado do gestor.
Operador deve concluir login legítimo no perfil dedicado e fechar sua janela;
o inicializador continua aguardando fechamento. Não houve chamada autenticada
Meta nesta rodada, publisher/renovação reais ou convite/OAuth/DM na conta 18.
Não houve merge/deploy. O rollback e os gates estão no relatório independente
e no runbook. Bloqueio anterior da ferramenta não foi contornado.

Veredito atualizado: gate de código/CI aprovado para revisão de publicação.
Ainda não pronto como onboarding operacional ativo: login/fechamento do perfil
dedicado, publicação/renovação real e autorização do futuro IP green permanecem
gates. PR aberto e Draft; sem merge/deploy. A janela do inicializador foi aberta
no nó M4 e permanece aguardando fechamento. Não é o navegador interno do Codex.

A pedido explícito do Rodrigo, o inicializador humano foi preparado e aberto no
nó M2, em perfil novo e privado, com Playwright 1.59.1 e Chrome já instalado.
Proxy público HTTPS no M2 retornou a saída esperada; FileVault ativo. O próprio
inicializador confirmou LOGIN_WINDOW_READY. Abriu somente a raiz pública Meta
Developers e aguarda login/fechamento feitos pelo operador. Não foram copiados
perfis, cookies ou chaves do M4, nem executados observador, publisher, Roles RPC,
merge ou deploy. A configuração do supervisor permanece no M4; este login no M2
ainda não prova publicação/renovação nem conclui a migração operacional.

Rodrigo informou login concluído e enviou captura do navegador autenticado.
Isso é evidência fornecida pelo operador, não homologação do publisher/renovação.
Os Chrome filhos dos inicializadores próprios foram encerrados com SIGTERM,
restrito ao processo principal filho do session-browser correspondente; nenhum
Chrome pessoal foi selecionado. Conferência por processos e lock, nos dois nós:
zero inicializadores, zero processos do perfil privado, nenhum lock remanescente.
A execução original no M4 terminou com exit 0. Não foram lidos cookies, senhas,
HARs ou conteúdos de perfil. CI reconsultado: SHA 952d7448d6, 22/22 SUCCESS, PR Draft.
M2 ainda não tem transporte publisher/AWS preparado; M4 permanece supervisor
preparado inativo. Nenhuma navegação autenticada automatizada, merge ou deploy.

Rodrigo autorizou explicitamente merge/deploy, corrigiu o escopo de ativação para
todas as contas de ambas stacks. PR #913 mergeado em 03/10/2026 às 21:12 BRT, SHA
2d493fe4a77aeb0912d2d8f27d6f802766cd465f. CI branch final: 22/22. Main pré-release
42e9559bbc626cd2cefb0c415c06f51fa15a89bd já estava saudável nas duas stacks; é o novo
ponto de rollback desta publicação, substituindo o ponto histórico 0abffb3. Revisão
de integração adicional: merge-tree rc0; relay de webhook usa rota diferente do
callback OAuth; sem bloqueador de código identificado. Deploys iniciados: Hub
37164225865, Autonom.ia 37164225880. Ainda não concluídos nem ativação real.
Cache coordenador comum privado não existe: as stacks têm VPCs/Redis distintos,
URL somente no Hub e allowlists ainda limitadas/vazias. Foi solicitada aprovação
para cache dedicado Valkey cache.t4g.micro (AWS Pricing API US East Virginia:
US$0.0128/h, estimado US$9.34/730h) e conexão privada, teto estimado US$15/mês.
Não houve criação de cache/peering ou ativação enquanto aprovação está pendente.
