# #950 — entrega, critérios de aceite e evidências

Data: 04/10/2026. Branch: `feat/950-instagram-admin-panel`, empilhada sobre `fix/931-instagram-audit-blockers` / PR #937, base `11b41b10301fe25ce6fa38f7ff8e6ab00f2ab608`.

Escopo: painel operacional Instagram no Super Admin, metadados canônicos, pedido de reconexão pelo gestor dedicado e escolha do onboarding por conta. **Nenhum merge, deploy, alteração de infraestrutura, segredo ou dado produtivo foi executado nesta entrega.** A disponibilidade autenticada nas duas stacks não foi homologada por estes testes.

## Produto entregue

Settings → Instagram → **Abrir automação Instagram**, com acesso próprio no menu Settings. O formulário aceita cinco metadados não secretos e não altera os campos OAuth existentes. App pai Meta e Instagram App ID OAuth são identificadores diferentes. A nova página nunca devolve cookie, token, segredo, URL Redis, perfil de navegador ou resposta Meta bruta.

O diagnóstico separa configuração local, sessão armazenada, heartbeat do gestor, proxy/coordenação configurados e evidência remota ainda desconhecida. **Verificar saúde é leitura local**, não uma chamada de confirmação à Meta. A reconexão é uma solicitação tipada com ator e horários; só aparece concluída após publicação. Navegador/2FA dependem do operador na máquina dedicada, não no computador do cliente.

A flag nativa `instagram_assisted_onboarding` é ON por padrão para contas novas após sincronizar os defaults. OFF mantém OAuth direto sem chamadas ao tester. ON indisponível não muda silenciosamente para o legado. Reautorização existente continua direta, mas exige inbox explícita vinculada à conta/perfil e mantém permissões. Contas existentes têm rollout separado com dry-run e confirmação; OFF manual posterior é preservado por marcador atômico.

## Matriz de aceite do código

PASS LOCAL significa execução no ambiente exclusivo de teste, não liberação produtiva.

| Critério | Evidência | Resultado |
|---|---|---|
| Cinco metadados, origem BD/ENV/vazio e salvamento transacional | `metadata_spec`, `configuration_metadata_spec`, requests e browser | PASS LOCAL |
| Snapshot por operação; bootstrap do gestor usa os cinco registros persistidos | Ruby/Node e prova PostgreSQL com publicação concorrente | PASS LOCAL |
| SuperAdmin, CSRF e tipos de entrada; HTML inválido sem gravação parcial | Requests e navegador com login Devise real | PASS LOCAL |
| GET da nova página não cria instalação nem publica sessão | Requests e opt-out do widget somente nesta tela | PASS LOCAL |
| Saúde não confunde configuração/heartbeat com conexão Meta | `local_status_spec`, UI, horário independente no browser | PASS LOCAL |
| Pedido queued/running/operator_required/failed/succeeded | Controller, OperatorControl, publisher e browser | PASS LOCAL |
| Cliques/requisições concorrentes não substituem pedido ativo indevidamente | Redis real com duas conexões e CAS | PASS LOCAL |
| Publicação antiga/revisão alterada e pedido substituído não dão falso sucesso | SessionStore real, PG, Redis e revisão Atena | PASS LOCAL |
| stdout final e UTF-8 entre chunks preservados | 109 contratos Node e reproduções independentes | PASS LOCAL |
| Canal privado aceita apenas operações/envelopes tipados | Ruby, Node, forced-wrapper e revisão de segurança | PASS LOCAL |
| Invalidação por nome preserva valores/expiração de outras chaves | 37 casos de cache, incluindo Redis real | PASS LOCAL |
| Renomeações múltiplas, rollback/savepoint/create/destroy não deixam nomes obsoletos | Controle negativo reproduz o bug antigo; implementação corrigida passa | PASS LOCAL |
| Flag ON/OFF por conta, default e rollout sem religar OFF manual | ActiveRecord, request EE e boot OSS separado | PASS LOCAL |
| OFF não consulta tester; ON indisponível não contorna o assistido | Requests/Vitest e wizard inicial | PASS LOCAL |
| Reautorização preserva inbox, canal e identidade autorizada | Callback, seleção, replay, papéis customizados e browser | PASS LOCAL |
| Novo controle acessível em EE e OSS, label associado | Requests e browser; sem renumerar bits | PASS LOCAL |
| en/pt_BR, mobile/320px, foco, toque e contraste | 18 casos reais no navegador / 749 asserções | PASS LOCAL |
| Build, carregamento Rails, Guia e formatos gerados | Comandos oficiais do repositório | PASS LOCAL |
| Rollout das contas existentes, atualização do runtime e operação Meta real | Requer aprovação e homologação por stack | NÃO EXECUTADO |

## Baterias executadas pelo coordenador

| Bateria | Resultado | Limite |
|---|---|---|
| RSpec amplo selecionado | **613 exemplos, 0 falhas** | 54 arquivos; não a suíte inteira do monorepo |
| Flag em boot OSS independente | **11 exemplos, 0 falhas** | Processo com `DISABLE_ENTERPRISE=true` |
| Vitest | **158 testes, 0 falhas** | 151 em 11 arquivos + 7 em arquivo distinto de `useChannelConnect` |
| Contratos Node | **109 testes, 0 falhas/skip** | Sem Meta externa |
| Preparador Python | **25 testes, 0 falhas** | Capturas sintéticas, sem rede |
| Cache focal real | **37 exemplos, 0 falhas** | Incluídos no RSpec amplo; não somar novamente |
| Operador PG/Redis real | **7 exemplos, 0 falhas** | Incluídos no RSpec amplo; concorrência em conexões distintas |
| Browser Rails/ERB/Devise | **18 casos, 0 falhas; 749 asserções** | Serviços externos simulados; dados e sessão sintéticos |
| Assets | **Build forçado concluído** | Inclui as classes Tailwind do ERB; não apenas cache de build |
| Guia/i18n/formatos/autoload | **Aprovados** | 180 fluxos, 176 rotas; 17.422 mensagens; 506 ações |

## Revisões e falhas corrigidas

Subagentes contribuíram com frentes distintas: Lina (protocolo/runtime), Orion e Maya (painel/UI), Theo e Rhea (flag/rollout), Gauss (cache), Turing (Redis/PG real), Vega (browser), Clio (documentação) e Atena (segurança independente). Os nomes descrevem agentes Codex efetivamente executados; não significam cards nativos do ChatGPT.

Atena reprovou e depois revalidou: WATCH aninhado, assinatura de enqueue, contratos do wrapper, confirmação em `exit` antes do último stdout, UTF-8 repartido em chunks e ordem oposta de locks SQL. O parecer final aprovou o código no escopo. **Publicação da sessão e conclusão do pedido continuam sendo dois commits separados**; não há promessa de atomicidade conjunta. Resposta ambígua pode exigir reconciliação sem falso sucesso.

Gauss demonstrou que o Dirty de ActiveRecord mantém nome após rollback de savepoint. A implementação consulta o nome realmente persistido antes da escrita e invalida os nomes afetados após commit. O teste com código anterior falhou de propósito; a versão corrigida preservou inclusive `PEXPIRETIME` das chaves não afetadas. `GlobalConfig.clear_cache` sem argumentos conserva o caminho legado; a entrega não promete eliminação de toda varredura do repositório nem cache linearizável.

No navegador foram encontrados e corrigidos: helper não incluído, gravação indireta de instalação no GET, label da flag EE, layout móvel comprimido pela sidebar, data pt_BR sem tradução e contraste escuro. As falhas de boot/fixture, serialização de milissegundos no harness e SDK externo também foram registradas antes da rodada aprovada. Nenhum assert foi removido para esconder essas falhas; o SDK de suporte é explicitamente simulado somente no QA de páginas legadas.

As capturas aprovadas usam dados sintéticos. [Desktop](../assets/instagram-admin-950/desktop-identificadores.png), [mobile](../assets/instagram-admin-950/mobile-identificadores.png), [escuro](../assets/instagram-admin-950/desktop-escuro.png), [reconexão na fila](../assets/instagram-admin-950/reconexao-na-fila.png) e [publicação em teste](../assets/instagram-admin-950/reconexao-concluida.png). Hashes em `docs/assets/instagram-admin-950/manifest.json`.

## Reprodução e CI

Guia funcional: [painel](../instagram-admin-panel.md). Procedimentos e comandos: [runbook](../runbooks/instagram-admin-panel.md). O [job dedicado](../../.github/workflows/instagram-admin-integration.yml) usa PostgreSQL e Redis descartáveis nas portas de teste exigidas e não transforma ausência de resultado em sucesso. O workflow geral do fork não foi alterado para acomodar essas portas.

Os recibos locais completos estão em `tmp/950-integration/`: `rails-final-verified.log`, `oss-feature-verified.log`, `frontend-integrated.log`, `frontend-channel-connect.log`, `node-integrated.log`, `python-final.log`, `cache-real-final.log`, `operator-real-proof.log`, `validation-final.json` e `visual/results.json`. Scratch é ignorado pelo Git; fontes de testes e relatório final são versionados. O banco de browser contém somente fixtures e deve ser reconstruído antes de voltar a RSpec nesse ambiente exclusivo.

## Limites e gates de publicação

Não foram resolvidos por esta entrega: o HTTP 407 operacional anteriormente observado, configuração/autorização real do proxy, coordenação entre stacks, instalação do gestor no Mac ou primeira/segunda publicação autenticada na Meta. CI e browser local não comprovam OAuth/webhook/DM reais. A nova feature apenas fornece controle e diagnóstico para operar essa integração com menos comandos manuais.

A PR depende da #937. Mudanças Ruby, Node, forced-wrapper e waiter devem sair juntas em janela aprovada; versões misturadas são incompatíveis. Salvar os cinco metadados antes de iniciar o gestor é obrigatório. Default ON em contas existentes exige rollout explicitamente aprovado. Não apagar caixas, contatos, conversas, tokens, locks ou outcomes para liberar uma etapa.

O CI remoto deve ser conferido no SHA final da PR, separado destes recibos locais. Nenhum merge/deploy é autorizado por este documento. Zero regressão em produção não é uma garantia absoluta: a evidência cobre os casos executados e preserva os limites acima.

## Fechamento independente e lint

Maya examinou as capturas renderizadas de desktop, claro/escuro, mobile e 320px; a rodada adicional mostrou a flag da conta e os controles de saúde/reconexão no enquadramento. A revisão visual encerrou sem defeito concreto nas áreas examinadas. O manifesto final contém 426 fontes/artefatos conferidos; as 16 capturas correspondem aos estados sintéticos registrados. Título no tema escuro medido em 16,13:1; o teste exige 4,5:1 para o texto examinado e alvos mínimos de 44px.

RuboCop final: **49 arquivos, zero infrações**. ESLint: **23 arquivos, zero erros e 48 avisos de resolução de catálogos/chaves dinâmicas**, mantidos visíveis; a compilação en/pt_BR e as telas reais não mostraram traduções faltantes. Warnings de depreciação Rails, sourcemap de dependência, Browserslist e tamanho de chunk não foram convertidos em falsa ausência de avisos. Gitleaks do staged: **nenhum segredo encontrado**.

Os reviews aprovam o código/UI no escopo local, não substituem aprovação humana de merge, CI no novo SHA ou homologação externa. O commit/PR resultante vincula esses artefatos; nenhum resultado remoto futuro é declarado neste registro.
