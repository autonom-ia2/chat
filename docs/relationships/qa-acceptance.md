# QA e aceite — Relacionamentos / Issue #757 / PR #760

## Fonte do estado de liberação

A PR #760 reúne implementação, revisão e gates. **Este documento não autoriza merge,
deploy ou ativação em contas reais.** A aprovação de Rodrigo e o sucesso dos checks no
SHA efetivamente revisado continuam obrigatórios. Registros anteriores de agentes são
históricos; não substituem os resultados abaixo nem o status atual da PR.

Base funcional: `8396d7255e097ba79507a22081701eb41ddb6ce5`.
O SHA candidato é o HEAD da PR #760; os checks e o relatório da imagem registram o SHA exato. O snapshot de frontend `cad28d3772` foi mantido. Os deltas posteriores corrigem o conversor nativo, o teste do mapa de flags e a organização do extractor legado para cumprir o lint estrito, sem mudar suas regras.
Worktree exclusivo: `chat2you-757-relacionamentos`, branch `feat/757-relacionamentos`.

## Ambiente e isolamento

- Ruby 3.4.4, pnpm 10.2.0, Node 24; dependências fixadas pelo repositório.
- PostgreSQL dedicado em loopback, porta 55757, bancos `relationships_757_test` e
  `relationships_757_e2e`; Redis dedicado em 56757, DBs separados para specs/browser.
- App E2E em `http://127.0.0.1:34757`; Vite em 35757; nenhuma requisição de produção.
- Dados fictícios, contas/admin/agente próprios, contatos e arquivos sintéticos.
  Login usa a autenticação normal. Mensageria e notificações ficam no adapter de teste;
  somente o job de preview é executado localmente para comprovar thumbnails reais.
- Playwright regular: Browser plugin não listado nesta sessão. Saídas, imagens e dados
  de acesso permanecem no diretório local ignorado `.codex/relationships/`.
- Nenhuma credencial, dado de cliente, log de produção ou screenshot real é versionado.

## Evidências executadas

| Gate                                  | Evidência local concluída                                                                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Frontend completo                     | 6.771 testes aprovados, zero falhas/pendentes; `approved-candidate-vitest.json`.                                                            |
| Backend integrado + contratos antigos | 471 exemplos: 470 aprovados, zero falhas, uma quarentena preexistente; `resume-expanded-rspec.json`.                                        |
| Conversores nativos                   | 18 exemplos aprovados; PNG/JPEG/WebP/PDF/vídeo, limites mantidos, sem upscale, formatos disfarçados/corruptos e fallback.                   |
| Fluxos reais no navegador             | 14/14 na retomada consolidada `resume-final-browser.log`, com backend real e sem alterar os timeouts.                                       |
| Responsividade                        | 390, 1.024 e 1.630 px; light/dark, modal, foco, cancelamento e retorno.                                                                     |
| Lint estrito                          | 54 arquivos, zero bloqueios; somente 13 avisos de chaves dinâmicas que o gate existente permite.                                            |
| Lint Ruby cumulativo                  | 44 arquivos alterados inspecionados, zero infrações; `resume-all-rubocop.log`.                                                              |
| AST sem regex nova                    | Fontes/testes/scripts alterados analisados por AST; nenhum novo padrão ou matcher.                                                          |
| Revisão independente                  | `release-review.md`, `native-renderer-review.md` e `lint-delta-review.md`: nenhum P0/P1/P2 demonstrável restante; condicionado ao CI final. |
| Build/Guia/Central                    | Build Vite executado; Guia/Central conferidos com os geradores próprios.                                                                    |

Os totais identificam rodadas concluídas, não uma promessa de inexistência de bugs.
A imagem Linux é um gate separado: aprovação local do macOS não comprova limites ou
bibliotecas da imagem de produção. Consultar a execução atual de `relationships.yml`.

## Cenários de navegador

1. Login pela interface real e abertura de contato.
2. Home Relacionamentos com três destinos; links antigos, Todos/Ativos/Etiquetas.
3. Criação pelo modal, descrição obrigatória, chave automática não exposta na tela,
   salvamento do valor, confirmação e persistência após recarregar.
4. Valores existentes; zero, falso e data de calendário sem deslocamento de dia.
5. Configuração global dentro do accordion real; seleção vazia distinta de legado;
   restauração do padrão, preservando Resolver e compositor.
6. Rascunho preservado em erro transitório ao recuperar foco; Cancelar não cria definição.
7. Atributo de Empresa permanece na Empresa, sem copiar valor para o Contato.
8. Busca de mídia além da primeira página, agrupamento e retorno com filtro preservado.
9. Agente sem gestão e conversas restritas; ausência de nomes/contagens/preview indevidos.
10. Modal e campos em três larguras; foco retorna ao botão; tema escuro.
11. Thumbnail autorizado real, não placeholder contado como conversão aprovada.

O teste de login e o de criação são independentes, ambos com o limite original de
30 segundos. A sincronização espera respostas reais, não sleeps arbitrários.
Não foram aumentados timeouts ou removidas asserções para esconder falhas.

## Matriz de compatibilidade do backend

Os specs cobrem configuração/definição transacionais, revisão e conflito explícito,
valores por chave, definição alterada concorrentemente, papéis, conta/entidade erradas,
locks com importadores/CRM/widget, identificação/mesclagem e preservação de chaves.
Também cobrem autorização antes de nomes/contagens, paginação, busca, notas permitidas,
URL original com expiração, reautorização após desvincular contato, derivado inválido,
contenção de fila, recuperação de falha transitória e limpeza de upload parcial.

O contrato de uma API externa legada sem versão continua last-write-wins. Não é possível
adivinhar intenção de um payload completo antigo sem uma base de comparação. O protocolo
novo usa comparação/revisão e os escritores internos alterados mesclam sob lock.

## Performance

O teste usa 1.000 ocorrências em 50 contatos e 20 amostras por tamanho de página, com
rota aquecida. Limiar declarado antes da medição: p95 inferior a 500 ms e diferença de
no máximo duas consultas SQL ao dobrar a página. Conversão de preview não faz parte da
listagem. Os números locais não são previsão de latência em produção. A tabela registra a rodada ampliada desta retomada, com carga concorrente da máquina, sem selecionar apenas a medição mais rápida.

| Página | p95 local | Máximo de SQL | Amostras |
| ------ | --------: | ------------: | -------: |
| 25     | 472.37 ms |            14 |       20 |
| 50     | 446.52 ms |            14 |       20 |

## Reexecução

Usar somente o ambiente isolado documentado. Preparar fixtures sintéticas antes do
Playwright e passar `RELATIONSHIPS_TEST_URL`, `RELATIONSHIPS_TEST_FIXTURE`, conta/contato
e credenciais de teste por ambiente. O config recusa host que não seja loopback.
Não copiar credenciais para documentação ou usar conta 16 real como fixture.

```sh
pnpm relationships:check
pnpm test --maxWorkers=2 --minWorkers=2
bundle exec rspec spec/services/relationships spec/requests/relationships spec/enterprise/services/relationships spec/enterprise/requests/relationships spec/enterprise/jobs/relationships
bundle exec rspec spec/relationships_unit --options /dev/null
pnpm --dir tests/playwright exec playwright test --config=relationships.config.ts
pnpm guia:check
pnpm central:check
```

Contratos antigos adicionais estão na seleção ampliada de 30 arquivos do relatório integrado.
O workflow independente executa regressão sem depender do workflow antigo manualmente
desabilitado. A imagem final é construída apenas no runner descartável, sem push de
imagem, AWS ou deploy, e testada com rede desligada e limites de recursos.

## Ocorrências resolvidas e avisos

O navegador identificou o uso inicial do axios não autenticado; os novos callers passaram
a usar o cliente de sessão/apiHost existente. A revisão encontrou escritores legados e
respostas antigas que podiam sobrescrever valores; foram corrigidos com testes reais.
O gate de CI identificou resolução de parser/listagem de dependências e warnings estritos;
foram corrigidos sem relaxar o verificador. O diagnóstico da imagem exata no run36584352561
confirmou `Vips::Error: out of memory` no filho de imagem. O bootstrap de Ruby/Gems
foi eliminado desse filho: JPEG/PNG/WebP usam o FFmpeg já empregado para vídeos, com
demuxers explícitos, assinatura real, sem upscale e os mesmos limites de512MiB/15s.
Somente o check da imagem final no SHA candidato certifica a execução em Alpine.

O teste fechado do mapa de flags foi expandido para os três novos bits, sem alterar
nenhum identificador antigo nem trocar igualdade exata por inclusão parcial. Outro
teste comprova opt-in e independência. A quarentena de `Account has_many
autonomia_account_links` já existia na base e continua explicitamente não aprovada;
nenhum teste foi colocado em skip nesta entrega.

Sourcemap ausente de uma dependência, Browserslist e depreciações Rails/Rack foram
registrados. O endpoint `/enterprise/api/v1/accounts/.../limits` retorna404 no harness
local também na base. Isso não é tratado como teste da funcionalidade nem escondido.

A ausência de P0/P1/P2 conhecidos e os checks verdes são critérios de aprovação, não
uma garantia absoluta. Nenhum gate vermelho deve ser contornado ou substituído por
um build verde isolado.

### Fechamento do lint cumulativo na retomada

O run36588125727 passou os testes de backend, mas bloqueou no RuboCop cumulativo:
cinco infrações no extractor legado tocado para coordenar gravações e uma no diagnóstico
do smoke. A correção compacta a classe, extrai o processamento de cada item mantendo o
lock e a ordem, elimina um ramo idêntico ao fallback e usa `$stderr`. Não alteramos
limites, exclusões ou configurações dos verificadores para liberar a PR.

Doze casos de coerção foram acrescentados; a seleção ampliada passou com471 exemplos
(470 aprovados e a mesma quarentena anterior). A revisão independente comparou71 cenários
nas duas versões, com resultados, gravações e sequência de locks idênticos. O gate da
imagem e o lint remoto precisam estar verdes no HEAD final antes da aprovação.
