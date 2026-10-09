# Checagem independente limitada — F0 produto/UX e testes

**Escopo:** checagem do mesmo bloco corretivo, sem nova revisão normal. O alvo é
`docs/agentes-ia-redesign/design/F0-mapeamento.md`, SHA-256
`3dd44e652b1f14deefb8a071b1cf5db9c8cd2e7a8e3685c418c7e3be3d1978e4` (245 linhas),
confrontado com `docs/audit/2026-10-07-agentes-f0-desenho-decisoes.md`, o PRD e
`aceite-telas-reais.md`.

Não executei testes, build, navegador, banco, produção ou qualquer código de
produto. Não alterei o desenho nem o código.

## Resultado

**PARADA — há erros residuais concretos no contrato da matriz de telas e na
navegação de retorno.** Os demais pontos dos nove achados originais foram
conferidos e estão fechados no desenho; estes residuais exigem causa raiz e a
correção/final prevista pelo processo antes de qualquer implementação F0.

## Pontos fechados

| Achado original | Resultado | Evidência no F0 |
|---|---|---|
| F0-TEST-01 — API local sem fachada | Fechado | O desenho proíbe mock/stub/página vazia (`:16`), restringe `page.route` a falha/atraso nomeado (`:184`) e exige GET/reload após escrita (`:197`, `:220`). |
| F0-TEST-02 — identidade, permissão e persistência | Fechado | Fixtures com editor, viewer, administrador, SuperAdmin e conta B (`:187-197`), autenticação local real, IDs/cleanup e pós-condição por GET/reload. |
| F0-ROUTE-01 — retomada da thread | Fechado | Entrada/resolver backend escopado, validação de conta/agente/thread e bloqueio sem leitor real, sem `start` (`:134-145`). |
| F0-UX-01 — barra da jornada | Fechado | Quatro itens em `AgentSteps`; Pronto é conclusão fora da barra, conforme PRD e `kit.js` (`:48-53`, `:80-90`). Não há quinta etapa residual. |
| F0-TEST-04 — axe | Fechado como gate planejado | Dependência, helper, loopback, tema/viewport e bloqueio quando ausentes estão explícitos (`:175-185`, `:241`). A execução continua corretamente bloqueada até a dependência/configuração existirem. |
| F0-D4-01 — n-navy | Fechado | Inventário de 18 usos em 12 caminhos, classificação e prova de grep/token (`:92-113`). |
| F0-DOC-01 — Guia/Central | Fechado | Cadeia rota → `porques.md` → gerados → Central e comandos oficiais, sem edição manual dos gerados (`:222-233`). |
| F0-UX-02 — lifecycle do SidePanel | Fechado | afterEnter/afterLeave, foco, Escape, scroll lock, retorno e matriz dos consumidores reais (`:66-78`). |

## Residuais

### F0-CHECK-01 — alta — a matriz de 14 famílias ainda não é rastreável a uma spec e omite estados obrigatórios

**Prova:** a seção 8 fornece apenas `Família`, `Fixture/percurso real`,
`Leitor e persistência` e `Capturas` (`design/F0-mapeamento.md:199-220`).
Ela não liga cada linha a arquivo/caso de teste executável; a seção 7 nomeia
config/helper (`:175-185`), mas não o spec de telas reais previsto pelo PRD
(`PRD.md:1181-1185`). Mais grave, a linha F06 enumera somente
`thinking,send-error,slow,many` (`F0-mapeamento.md:210`), enquanto o aceite
exige também **Não salvou** e **Ainda respondendo**, com contratos diferentes
(`aceite-telas-reais.md:90-96`; `PRD.md:964-974`). “Erro”/`failed` não prova
o 422 com `error_fields` de “Não salvou”, e `processing`/demora não prova o
409 e o bloqueio do campo de “Ainda respondendo”.

O mesmo buraco deixa outras variantes sem nome próprio na matriz: F09 não
explicita a falha ao ligar nem o editor sem administrador, embora sejam alvos
distintos do aceite (`aceite-telas-reais.md:115-121`), e F13 não explicita o
código vencido (`:147-153`). Isso impede saber se a captura é a tela real do
estado ou apenas uma captura genérica da família.

**Causa:** a correção transformou a lista anterior em uma tabela de famílias,
mas parou no nível de família; não cruzou cada variante normativa com um caso
executável, leitor, pós-condição e captura identificável.

**Efeito:** um spec futuro pode produzir as quatro combinações de uma família e
ainda omitir estados exigidos pelo aceite, sem que o gate detecte a ausência; a
afirmação “14 famílias completas” fica não auditável.

**Correção mínima:** acrescentar à matriz o arquivo/spec e o identificador do
caso de cada linha, e enumerar todas as variantes normativas como capturas e
pós-condições separadas. No mínimo, F06 precisa incluir Não salvou e Ainda
respondendo com seus leitores/efeitos próprios; F09 e F13 precisam explicitar
as variantes acima. A correção deve continuar no desenho/teste local, sem
fabricar sucesso por `page.route`.

### F0-CHECK-02 — média — F11 promete captura de Ferramentas sem a fixture SuperAdmin da própria linha

**Prova:** o aceite exige a aba Ferramentas para o administrador da plataforma
(`aceite-telas-reais.md:131-137`; `PRD.md:1034-1038`). O F0 define a fixture
`super_admin` e diz que ela confere Ferramentas (`F0-mapeamento.md:189-195`),
mas a linha que deveria executar/capturar esse cenário lista somente
`editor_a, viewer_a, account_admin_a` e inclui `tools` nas capturas
(`F0-mapeamento.md:215`). A lista geral de fixtures não substitui o ator do
percurso da linha; a matriz não prova que `tools` está visível apenas para
SuperAdmin, nem que editor/viewer recebem a recusa.

**Causa:** o ator correto foi registrado no catálogo geral, mas não foi ligado
à linha de execução visual que contém a tela restrita.

**Efeito:** a captura `F11@tools` pode ser impossível, ser feita com a sessão
errada ou passar sem verificar a regra de permissão do painel.

**Correção mínima:** incluir `super_admin` no percurso de F11 e declarar nessa
linha a leitura positiva para SuperAdmin e a ausência/recusa para os perfis sem
essa permissão; manter a dispensa da aba para a Lia.

### F0-CHECK-03 — média — Conte fica inacessível justamente quando a pessoa precisa voltar para alterar antes de ligar

**Prova:** na tabela de etapas, Conte é marcado como acessível somente quando o
backend indica E1/E2 (`F0-mapeamento.md:82-90`). O PRD exige que, no Teste,
“Quero mudar algo” volte ao Conte sem perder nada (`PRD.md:995-996`), e que
qualquer mudança antes de ir ao ar invalide o teste atual e retorne à condição
de novo teste (`PRD.md:446-455`; `aceite-telas-reais.md:40-42`). Isso inclui
E3/E4; a tabela do F0 não descreve esse retorno nem libera Conte nesses estados.
O texto genérico “caminho de saída em qualquer estado”
(`F0-mapeamento.md:161-167`) trata de sair e guardar o rascunho, não do
retorno para editar a conversa.

**Causa:** `reachable` foi ligado apenas ao estado de entrada do Construtor,
sem incluir a transição de alteração que invalida o teste antes do ar.

**Efeito:** a barra/roteamento pode bloquear a ação “Quero mudar algo” em E3/E4
ou abrir um Conte sem contrato de thread, quebrando a jornada de correção para
uma pessoa leiga e a regra de teste válido atual.

**Correção mínima:** registrar Conte como retorno permitido a partir de Teste
nos estados E3/E4 quando a pessoa pedir alteração; declarar que a alteração
preserva thread/dados, invalida o teste atual e leva ao estado/ação de testar
novamente. Não liberar o avanço para Ligue até o novo teste válido.

## Conclusão

A checagem confirma os fechamentos de fachada/API local, fixtures gerais,
retomada, barra de quatro itens, axe planejado, lifecycle, n-navy e
Guia/Central. Os três residuais acima são concretos e bloqueiam a aprovação do
desenho F0. Conforme a regra desta checagem, não fiz correção nem iniciei nova
rodada; é necessário registrar a causa raiz, corrigir e executar somente a
revisão final autorizada.
