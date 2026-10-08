# Candidato de redução de latência — testes antes de merge

Issue #995, PR #1155. Data: 2026-10-08. Merge, fila de merge e deploy permanecem suspensos. Nenhuma mudança instalada em produção, convite, DM ou chamada Meta nesta rodada.

## Objetivo e critério

Reduzir a busca e confirmação em dez vezes, sem aumentar CPU, timeouts ou TTLs. Os tempos históricos recuperados em `995-instagram-response-latency-audit-20261008.md` são HTTP recebido na AWS → publicação reconhecida na VPS. Metas: busca ≤8,097 s; primeira consulta de status ≤4,251 s; reconciliação pendente ≤4,502 s; confirmação aceita ≤5,103 s; convite ≤6,631 s. Espera humana por convite/login/2FA fica fora dessa comparação.

A etapa posterior ao aceite deve gerar diretamente a URL original de OAuth. Não deve abrir outra operação de navegador na VPS.

## Resultados medidos

| Comparação controlada | Antes, mediana | Candidato, mediana | Amostras e alcance |
| --- | ---: | ---: | --- |
| Busca no publisher com imagem OCI de produção em sandbox isolado | 21,181 s | 0,228 s | 3 cold / 6 warm; processo Rails e pipes locais; **92,8×** |
| Status no publisher com imagem OCI de produção em sandbox isolado | 23,638 s | 0,167 s | 3 cold / 6 warm; processo Rails e pipes locais; **141,5×** |
| Gerar URL OAuth após status aceito | — | 0,052 s | 6 warm; API Rails real, URL/estado original válido, nenhuma nova operação VPS |
| Consulta CURRENT na VPS: CLI → cliente SDK reaproveitado | 4,513 s | 0,155 s | 5 CLI / 20 SDK warm, leitor candidato real; **29,1×** |

A simulação do publisher usou a imagem OCI ativa `8589beb5504fe59a21ed907db9c1d434c6eec0e9`, overlays somente leitura, PostgreSQL e Redis TLS descartáveis. Nenhum dado de produção, segredo real, rede Meta ou OAuth externo. O banco sandbox é PG 18.6; RDS de produção 18.3. Todas as entidades Docker existentes ficaram idênticas após a limpeza.

A abertura inicial do publisher warm levou 5,184 s, medida separadamente. O filho Rails chegou a 268.440 KiB RSS; isso não é a memória agregada de aplicação/broker. Vinte leituras sem pedido tiveram mediana 1,148 ms e máximo 3,649 ms. O maior tempo warm de busca foi 887,280 ms; de status, 212,639 ms. Não estimar P99 com seis amostras.

O executor real do navegador também passou em 60 amostras de interface sintética: busca P50/P95 182/195 ms; status aceito 80/89 ms; convite com resultado incerto 365/386 ms. Isso valida o executor, não a latência externa da Meta. O fixture oferece a opção antes da resposta HTTP sintética; `typeahead_to_option_ms` permanece nulo, explicitando essa limitação.

## Trabalho removido e garantias

O candidato mantém um túnel SSM/SSH e um publisher Ruby residente por broker/stack, com framing limitado. Os pedidos continuam passando por objetos novos e pelo executor Rails em cada frame. Fechar, cancelar, perder conexão ou detectar rotação invalida o canal; nenhuma escrita ou frame é repetido automaticamente. O caminho one-shot permanece disponível para o contrato já existente.

CURRENT continua consultado antes de cada frame. Cinco leituras reais da CLI levaram 3,906–4,737 s, inviabilizando o objetivo de status em quatro segundos mesmo com Rails reaproveitado. O cliente SDK persistente passou em vinte leituras reais: P50 155,115 ms, P95 185,073 ms, máximo 214,684 ms. A inicialização levou 1,397 s. Não há cache de CURRENT ou retries automáticos. O valor precisa continuar comparado com o destino real.

O aceite já confirmado fornece comprovação assinada, com uso único e validade curta, vinculada à conta, usuário, instalação, aplicativo e seleção. A API revalida as permissões atuais e gera a URL original diretamente. Os testes anteriores rejeitaram comprovantes expirados, reutilizados e de outro escopo. O callback e a reautorização existente seguem o fluxo original.

A pausa do worker passou de 15 s para 1 s no candidato. O teste de ciclo comprova que um pedido disponível em t=999 ms é atendido em t=1000 ms, com um claim, uma execução e uma conclusão. Renovação, operação serial, desabilitação e cancelamento foram mantidos. A pausa continua sendo acrescida do tempo da consulta; não equivale a período total garantido de um segundo.

O teste de cadência do leitor usou o Node 18.19.1 atual da VPS, CPU 50% e memória 512 MiB. CPU média do processo Node por leitura warm: 23,280 ms; máximo 95,826 ms; RSS 68,715 MiB. Isso não inclui CPU de helpers de credenciais nem memória do publisher Rails. O SDK principal declara Node >=18, mas `util-locate-window` da closure declara Node >=20. Portanto o sucesso desse diagnóstico não estabelece suporte oficial da instalação em Node 18. A trava existente do instalador exige Node >=22.12 e permanece intacta; a divergência do runtime vivo precisa ser resolvida antes de instalação aprovada.

## Execuções e limites de evidência

- Canal/broker/STDIO: 9 + 72 + 21 testes realmente executados no snapshot M2 final; jobs `m2-70b601d9698f49058bfff1f67c05e611`, `m2-ef64217384904615a33557398818e3dd`, `m2-074a4a05554848e699ac738aba47ac54`. Planner excluiu M4 por disco insuficiente.
- Navegador, 60 amostras: M2 job `m2-f550a8586e894fcb9be706bfc3478c21`, ticket `m4-8658e517759e407aa203d0fe5a4ab958`, rc=0, 22,402 s.
- Leitor SDK/canal final: 14/14 no M2, job `m2-8dfb4bc7271d48cf8117e73b50d9c049`. Worker: 56/56 no M2, job `m2-356c8d0a16924e25826c7b3641f6d3cd`.
- Instalador: 59/59 no M2, job `m2-11f1464b8a344847b90a6738e9fc8b0d`, 7,629 s. Uma primeira execução sob `/Users/Shared` falhou no teste que rejeita diretórios ancestrais graváveis. A execução final usou projeção e TMPDIR privados, sem relaxar o guard, alterar permissões de Shared ou instalar dependências. Cleanup da projeção verificado; snapshot preservado.
- RuboCop do publisher Ruby: zero offenses, M2 job `m2-f773887e3a124422862f47ea75d6470b`. ESLint local não executou: árvore Node isolada sem `eslint-config-airbnb-base`, job `m2-2880c227a7cd4450b9d0d2238a482bb6`; não tratar como PASS. O workflow do PR cobre os novos módulos e precisa concluir antes de liberação. O hook local de commit também não inicia porque `.husky/_/husky.sh` não existe; não equivale a falha de código.
- Sandbox publisher: `.codex/publisher-latency-sandbox-attempt4.json`, passed, cleanup verificado. Três tentativas anteriores falharam na montagem do harness privado; não produziram medições válidas e também tiveram cleanup verificado. O alvo de um bind dentro do diretório read-only precisava existir antes da montagem.
- CURRENT CLI: `.codex/vps-current-latency-20261008.json`, passed; publisher vivo sem alteração; transient removida. O publisher vivo ainda usa quota temporária de CPU 200%; a medição isolada usou os 50% canônicos. Não houve ajuste do serviço vivo.

**Ainda não há prova de ganho de dez vezes na experiência completa com a Meta real.** As comparações publisher cold/warm incluem boot/processo Rails e transporte local por pipes. Excluem CURRENT, SSM/SSH, fila do manager e Meta. A leitura CURRENT é real, mas não publica operações. Não somar medianas de experimentos diferentes e apresentá-las como uma medição ponta a ponta.

## Revisão independente e publicação

Nexo: GREEN condicional para piloto observado. Não foram encontrados bloqueios funcionais/de segurança no candidato final. A cadência pode chegar perto de sessenta consultas por minuto por manager ativo; a medição não reproduz a carga completa Rails/Redis e SSM/SSH. Exigir observação de taxa, latência, erros, memória e renovação no piloto. Preservar a pausa anterior de 15 s como reversão simples; isso não reintroduz a operação extra após o aceite.

A instalação continua bloqueada enquanto a VPS estiver com Node 18: o instalador exige >=22.12. Esse pré-requisito precisa de plano e autorização de publicação. Não reduzir o gate ou instalar um pacote antigo para contornar o desvio. Novo fluxo e publisher Ruby também exigem publicação do Chat2You; esta não é apenas configuração VPS.

## Próxima decisão

Leitor SDK e cadência medidos; mudança de pausa validada no candidato; revisão e testes do instalador concluídos sem relaxar proteção de diretórios ou versão Node. Preservar os orçamentos de operação, locks, renovação e reconciliação de convite incerto. O teste completo com Meta real, transporte SSM/SSH e renderização do painel depende de canário após publicação aprovada. Só essa medição poderá confirmar as metas completas acima. Merge e deploy permanecem suspensos até aprovação explícita.
