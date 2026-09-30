# Integração de importação, proteção de envio e traduções — #779

Registro de 29/09/2026, com parte das validações após 00h UTC de 30/09. Base: `56f6e69232c5cb8ac6ee25e0a7ebeb513fa9a168`. Branch isolada: `codex/779-email-campaigns-integration`.

## Escopo autorizado e decisões

Rodrigo autorizou implementar #764 e #765, incluir a pendência de tradução e tratar sobras de campanhas. Confirmou que reputação local deve ser diagnóstico, proteção global governa novos envios e supressão individual permanece. Merge/deploy foram autorizados condicionados a implementação, review e testes verdes. Segredos, chamadas autenticadas/pagas, IAM e alterações de configuração de produção não foram executados nesta etapa.

A alegação sobre WhatsApp LID/JID foi retirada pelo próprio Rodrigo depois de verificar a configuração. Nenhum código de atributos foi alterado. Relacionamentos #776 já estava na main e não foi reimplementado.

A worktree original #764 foi preservada. Seus 35 arquivos foram incorporados a partir de snapshot consistente, excluindo configuração privada e regenerando apenas a mudança aditiva de esquema sobre a main atual.

## Resultado do produto

- #764: CSV aceita quatro separadores e os encodings brasileiros cobertos; XLSX examina as abas visíveis e até 100 candidatas a cabeçalho. E-mail obrigatório, nome opcional. Aliases conhecidos resolvem sem serviço externo; Jev versionado decide de/para desconhecido usando somente cabeçalhos, linha e perfis derivados. Nenhum destinatário ou nome de aba é enviado. A credencial fica cifrada, sem retorno ao HTML. Falhas externas preservam o arquivo e têm códigos seguros.
- #765: incidentes antigos, taxas e amostra locais não bloqueiam a conta. Histórico, flags e auditorias permanecem. O gate global reserva novos destinatários sob os locks existentes. Recupera admissão após duas amostras recentes, distintas e seguras, com histerese de cinco minutos; pausa manual permanece manual. Campanhas pausadas continuam exigindo Retomar. Hard bounce, spam, descadastro, higiene, importação ativa e claims ambíguos continuam protegidos.
- #772: repositório é fonte de verdade dos oito catálogos exclusivos. Crowdin os exclui; CI verifica exclusão, cobertura e parâmetros en/pt_BR e impede sobrescrita em sync automático. Português de Prospecção deixa de depender do arquivo inglês; a exceção histórica do inglês ainda em português foi documentada e acompanhada pela #780, sem alegar tradução completa em todos os idiomas.

## Review adversarial do implementador

Não substituir testes por contagens nem declarar review independente. Os dois agentes de implementação ficaram indisponíveis por limite da conta; não houve review independente adicional; não houve downgrade de modelo. A análise abaixo foi feita pelo implementador, conferindo código e contratos OSS/Enterprise, concorrência, privacidade, credenciais e estados operacionais.

| Achado | Correção e evidência |
| --- | --- |
| Timeout de transporte falhava no cálculo de retry sem resposta HTTP; 429 era absorvido pelo intervalo de erros 4xx | Corrigido cliente; timeout e 429 finais exercitados com três tentativas no job, código sanitizado e sem corpo externo |
| Resposta Jev fora do contrato podia selecionar uma coluna inválida | Modelo e tipos obrigatórios, números finitos entre 0 e 1 e índices canônicos; evidência local na coluna escolhida continua obrigatória |
| Dois jobs podiam gravar metadados de resolução antes de saber qual concluiria | Gravação movida para a mesma transação de destinatários/issues/conclusão; falha da conclusão prova rollback do metadata e dos inserts |
| Janela de recuperação global podia sobreviver à ausência longa do monitor | Amostra anterior precisa continuar recente; teste de interrupção superior à freshness exige iniciar janela novamente |
| Formulário podia coagir arrays/objetos/números em chave/configuração | Tipos e booleanos validados na fronteira; request malformado retorna 422 sem gravar credencial |
| Teste síncrono de conexão podia repetir chamadas por mais que o timeout web de 15s | Uma tentativa limitada por timeout; retries ficam no job assíncrono |
| Erro de cabeçalho ainda dizia que nome era obrigatório e que só a primeira linha/aba servia | Orientação en/pt_BR corrigida para e-mail obrigatório, nome opcional e colunas repetidas |
| Configurações compartilhadas SuperAdmin/Enterprise poderiam sofrer regressão | Mantido encerramento da gravação no primeiro erro; baseline inclui Shopify Enterprise e ConfigLoader |
| Um arquivo com cabeçalho reconhecido e todos os endereços inválidos podia perder o relatório das linhas rejeitadas | Cabeçalho continua reconhecido; regressão confirma duas linhas inválidas e nenhum destinatário inserido |
| A presença de nome numa aba de exemplo podia superar a base principal contendo somente e-mail | Escolha do cabeçalho dentro da aba é separada da escolha da base; regressão seleciona a base maior, com nome opcional |
| Uma sequência inicial de endereços inválidos podia promover uma linha de contato a cabeçalho enviado ao Jev | Candidata estrutural inicial é preservada por tabela; regressão com 120 linhas confirma cabeçalho original e todos os registros preservados |

A revisão do implementador corrigiu os achados de código acima. O preflight posterior identificou uma decisão de release pendente: o serviço está saudável, mas suas taxas são publicadas de forma esparsa; a exigência atual de ponto recente bloqueia após inatividade. Rodrigo foi consultado sobre usar consulta atual + última taxa oficial ou manter esse bloqueio. Não há sinal verde para release até resolver essa decisão, revisar a regra e repetir os gates afetados. Esta análise não é afirmação de ausência absoluta de regressões nem substitui review externo.

## Validação local

Runtime separado: Ruby 3.4.4, Node 24, PostgreSQL UTF-8 com pgvector e Redis próprios. Banco limpo; ambiente sem credenciais de provedores; WebMock impede rede nos testes. Fixtures e screenshots são sintéticos, sem dados de clientes.

| Gate | Resultado final local |
| --- | --- |
| RSpec EE, seleção cumulativa de 101 arquivos e baseline OSS/Enterprise | 1.028 exemplos, 0 falhas, 2 pendências legadas: undo de labels já em undoing e associação futura de Account; inclui as três regressões adicionais de seleção de cabeçalho/aba |
| Contratos puros, nove processos separados | 56 testes, 50.870 assertions, 0 falhas/erros |
| Vitest completo em UTC | 615 arquivos, 6.828 testes passando; após quatro casos adicionais da #765, painel focado com 62 testes passando |
| Copy de importação e mensagens | 215 testes focados passando depois da correção en/pt_BR |
| Locales de campanhas | 57 índices, 43 idiomas de runtime, 14.991 mensagens compiladas/renderizadas sem fallback |
| Overlay do fork | 8 catálogos, 15.732 mensagens compiladas; chaves e parâmetros obrigatórios cobertos |
| RuboCop | 51 arquivos alterados/novos, nenhuma infração |
| ESLint/Prettier | 5 arquivos frontend, 0 achados bloqueantes; seis warnings existentes de chaves dinâmicas; formatação aprovada |
| Regex | 59 arquivos de fonte/specs contra a base desta integração, nenhum regex novo; gate cumulativo de Relacionamentos também passou |
| Guia/Central | 169 fluxos/170 telas, nenhum fluxo sem explicação; 174 artigos/170 telas cobertas, alertas históricos fora do escopo preservados |
| Vite real em modo test | Build concluído; warnings existentes de tamanho de chunks/Browserslist |
| Upgrade de esquema | Schema da main → migration nova em PostgreSQL isolado; tabela criada e JSONB `{}` NOT NULL confirmado, sem alteração destrutiva |

A seleção do CI foi conferida depois de staging: corresponde exatamente aos 101 arquivos RSpec executados. Comandos: `bundle exec rspec --require spec_helper` com a seleção de `.github/scripts/email-protection-files.py rspec`; nove `bundle exec ruby` separados; `pnpm exec vitest run` completo e focado; `bundle exec rubocop --force-exclusion` nos arquivos alterados; wrapper ESLint de campanhas e `pnpm exec prettier --check`; `node scripts/check-email-protection-i18n.mjs`; `pnpm i18n:fork:check`; `pnpm relationships:check`; `pnpm guia:check`; `pnpm central:check`; `bundle exec vite build --mode test`; `node tests/qa/email-campaigns/run.mjs` com o headless-shell local. Cada saída foi lida antes de commit. O hook local reescreve Ruby automaticamente, inclusive esquema gerado, e encadeia stage/commit; para respeitar a regra do Rodrigo de ler resultados antes de commitar, a validação foi executada manualmente e o commit usa HUSKY=0. Os checks de PR permanecem ativos.

A execução ampla de frontend concluiu em UTC. A execução anterior em fuso local falhava em 19 expectativas de datas sem mudança nos componentes afetados.

Browser real: Chromium headless-shell 147.0.7727.15 correspondente ao Playwright instalado, componentes reais, VueRouter/Vuex/Pinia e CSS completo; HTTP sintético restrito a loopback. Resultado: 215 checagens, zero falhas e 153 screenshots, incluindo português, outros idiomas, RTL, desktop/mobile e interações. O Chrome completo local havia abortado antes de abrir a primeira página; foi substituído pelo binário headless da mesma instalação sem modificar assertions. Isso valida UI com fixtures, não um envio real nem a API Rails no navegador.

Após os três ajustes finais de seleção de cabeçalho/aba, a suíte cumulativa foi repetida em outro banco vazio: 1.028 exemplos, zero falhas, duas pendências legadas e nenhum erro fora dos exemplos. Os nove processos puros, lint Ruby e gate de regex também passaram novamente. O formato suportado exige cabeçalho; esta entrega não é um detector geral de dados pessoais em arquivos sem cabeçalho ou malformados. A prova de privacidade cobre o payload estrutural e os casos de seleção exercitados.

## Sobras inventariadas

- #438 e #443 estão mergeadas; heads completos #439, #440, #441 e #442 já são ancestrais da main, confirmados novamente por `git merge-base --is-ancestor`. Os quatro PRs foram fechados por cobertura integral; branches preservadas. Nenhum código foi reaplicado.
- #429 tem só uma auditoria histórica fora da main. Documento preservado nesta integração com nota contextual: timeout/importação síncrona antigos foram tratados pelas entregas assíncronas posteriores. PR e branch original preservados até o merge do documento no #781.
- #430, #432 e #444 já estão fechadas. #436 continua umbrella operacional; não fechar por inferência de cobertura técnica.
- #328 contém limpeza histórica de configuration_set de remetentes. O runtime já usa o default quando ausente, mas alteração de dados de produção exige escopo e aprovação próprios; nenhum backfill foi executado.

## Preflight de produção somente de leitura

Consultados somente imagem ativa e os flags de envio explicitamente permitidos em web/worker do Hub2You, via SSM. Nenhum valor de credencial foi solicitado/exposto, nenhum registro de cliente foi consultado e nenhum parâmetro foi alterado. Ambas as instâncias de aplicação usam a imagem `4ba863913d42141a358db95cf2f32a61924e7d59`, commit coberto pela base desta integração (a main seguinte só acrescentou a auditoria #776).

`EMAIL_CAMPAIGN_ENABLED=true`, região us-east-1; `EMAIL_REPUTATION_PROVIDER_MONITOR` e `EMAIL_REPUTATION_AWS_ACCOUNT_ID` estão ausentes. Portanto o monitor global está desligado pelo default atual. Ativá-lo e confirmar telemetria fresca é uma mudança operacional pendente, além do código. A credencial local do perfil default está inválida; a stack Autonom.ia não foi consultada por esse perfil e não deve ser considerada validada. Não alterar autenticação por conta própria.

Uma leitura direta com o perfil Hub2You confirmou SES SendingEnabled=true e EnforcementStatus=HEALTHY. As consultas globais CloudWatch de BounceRate e ComplaintRate não retornaram pontos nos últimos 15 minutos. Uma consulta de 24 horas retornou taxas oficiais de 1,21% e 0,01%, ambas abaixo dos limites, com último ponto às 13h46 de 29/09 em São Paulo. Dados ausentes na janela recente não provam taxas zero. A conta/região usadas pela aplicação precisam ser confirmadas antes de ativar o gate. A decisão sobre consulta atual + última taxa publicada permanece com Rodrigo; nenhum relaxamento foi aplicado enquanto a resposta está pendente.

## Gates de release e rollback

Merge na main dispara blue-green das duas stacks. Exigir CI verde no HEAD exato, review sem P1/P2 e confirmação operacional do monitor global na conta/região SES correta antes de merge. Sem observação global fresca, a troca de proteção ainda não tem sinal verde para produção. Não desabilitar flags antigas por escrita em banco nem retomar campanhas para testar.

Antes da migration de produção, seguir a política existente de snapshot manual do RDS. A migration adiciona `ai_provider_credentials` e `schema_resolution`, sem apagar dados. Implante web e workers na mesma versão e verifique saúde, versão, importações ativas e erros. TypeSafe permanece desligado até criptografia/configuração da chave e validação autenticada autorizadas; um GET de modelos não prova a qualidade de de/para em português.

Em falha, retornar ambas as stacks à imagem anterior pelo workflow blue-green e preservar o esquema aditivo. Drenar jobs novos antes de voltar ao leitor antigo; preservar arquivos, eventos, supressões, histórico e chave. Desligar Jev é rollback específico do fallback. Bloqueio manual global só mediante autorização operacional, sem apagar estado.

Runbooks: [importação](../email-campaigns/intelligent-import.md), [proteção global](../email-campaigns/reputation.md), [traduções](../i18n/fork-translations.md), [gates de deploy](../production-deploy-gates.md).

Fontes primárias conferidas: [API TypeSafe](https://docs.typesafe.ai/api), [modelo versionado](https://docs.typesafe.ai/models), [alarmes globais SES](https://docs.aws.amazon.com/ses/latest/dg/reputationdashboard-cloudwatch-alarm.html), [formato oficial ignore do Crowdin CLI](https://github.com/crowdin/crowdin-cli/blob/main/tests/e2e/fixtures/ignore/alt-configs/ignore.yml). Não houve chamada autenticada ao TypeSafe nesta integração.
