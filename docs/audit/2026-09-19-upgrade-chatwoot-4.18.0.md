# Upgrade Chatwoot 4.17.1 → 4.18.0 (#474, PR #475)

Data: 2026-09-19. Branch `upgrade/chatwoot-4.18.0`, a partir da `main` em
`0ec0caf8fc`. Critério do dono: regressão zero no produto atual.

## Escopo

Merge da tag `v4.18.0`: 123 commits upstream e 3 migrations aditivas. Não houve
troca de Rails, Ruby ou Node. Os 27 conflitos foram resolvidos à mão e as
decisões estão na mensagem do commit `4df32fc8e8`. Commits de ajuste:

- `109b3df57a`: spec upstream `AutomationRuleForm.spec.js` sem Vuex;
- `39ca50cff4`: regressão da reautorização do WhatsApp.

## Medição prévia em produção (só leitura, psql via SSM, sessão `read_only`)

Números agregados, sem dado de cliente.

- **Backfill `ai_assignee`:** 0 linhas afetadas nas duas contas.
- **BSUID:** 2.178 `contact_inboxes` BSUID em caixas Cloud (hub2you) e 0
  conversas abertas neles. As 2.691 abertas estão no `contact_inbox` de
  telefone. A regra nova de reuso de conversa por identidade (#15175) não deixa
  conversa órfã hoje.
- **Integrações e regras:** Captain, Slack e Shopify sem uso. Automações ativas
  com condição de etiqueta: 0.
- **`audits`:** 21 MB.

## Decisões que revisaram a recomendação aprovada

Ambas mantêm o comportamento atual do fork.

1. **`FINISH_ONLY_WABA`, `FINISH_OBO_MIGRATION` e
   `FINISH_GRANT_ONLY_API_ACCESS` não são recusados na tela.** O
   `PhoneInfoService` da 4.18.0 usa o único número do WABA (ou o número já
   salvo da caixa, na reautorização) e falha com erro claro quando há
   ambiguidade. Recusar na tela quebraria o caso de número único, que funciona
   hoje.
2. **`HistorySyncService` sem condição de `is_coexistence`.** A Meta dá uma
   tentativa por onboarding numa janela de 24h. Um sinal ausente ou errado
   perderia o histórico do cliente de forma irreversível. O serviço já se
   limita a canais de embedded signup e a uma única requisição.

## Armadilhas silenciosas encontradas e corrigidas

- **`inbox_policy.rb`:** o auto-merge pôs `set_call_recording?` abaixo do
  `private`, o que daria 500. Foi movido para cima e usa `inbox_manage?`.
- **`conditions_filter_service.rb`:** o bloco do fork chamava
  `label_conditions?`, removido upstream. O `rescue` do `perform` engoliria o
  erro e as automações com etiqueta parariam sem aviso.
- **`db/schema.rb`:** as migrations upstream têm data anterior à versão do
  schema do fork, e o `schema:load` as marcou como aplicadas sem criar
  colunas. Foi confirmado num banco local e regenerado por `db:migrate` real.
- **Reautorização do WhatsApp:** mudança do upstream (#15462), achado ALTO do
  review. Ver `39ca50cff4`.

## Validação

- **RSpec completo, local**, baseline na `main` e no branch, 4 fatias
  round-robin como o `testes.yml`, banco e índice Redis por fatia:
  - baseline: 12.544 exemplos, 88 falhas, 127 pendentes;
  - branch: 13.282 exemplos, 35 falhas, 129 pendentes.
- **Comparação exemplo a exemplo**:
  - 9 "regressões": classe recarregada entre specs; passam isoladas, 75 de 75;
  - 74 ausentes: renomeados ou reescritos pelo upstream em arquivos que o fork
    não tocava, ou nomes com id aleatório (policies);
  - 0 testes do fork perdidos;
  - os 34 arquivos que falharam em alguma rodada passam juntos no branch:
    475 de 475.
- **As 88 falhas da `main`** são poluição entre specs e sobra de banco.
  `entrega_de_arquivo_spec.rb` falha por 2 blobs deixados por spec anterior e
  passa com banco novo (27 de 27).
- **Vitest completo:** baseline 5.127 de 5.127; branch 5.509 de 5.509 depois de
  `109b3df57a`.
- **Detector de perda de customização:** linhas adicionadas pelo fork desde
  4.17.1 cuja contagem cai no resultado. 2.345 arquivos, sem perda não
  intencional.
- **Varredura de visibilidade** de métodos Ruby alterados pelos dois lados: 38
  arquivos, 0 divergências.
- **Build de produção** `RAILS_ENV=production rake assets:precompile`, como o
  Dockerfile: ok.
- **Lint:** Rubocop limpo nos Ruby tocados. ESLint sem erros; 2 avisos
  falso-positivos de i18n, com as chaves conferidas em en e pt_BR.
- **Review adversarial (Opus):** aprovado com ressalvas. As correções de
  segurança dos commits `7d581dc8c4`, `aad2791b48`, `4218dc6793`,
  `b7d857d517`, `8b1e08fc66`, `f8e165519c` e `6efffc895e` estão idênticas ao
  upstream.
- **Prova inversa do `Reauthorize.spec.js`:** contra o `Reauthorize.vue`
  original da 4.18.0 falham os 3 testes da regressão e passam os outros 3.

## Bloqueios e limites

- **CI:** o workflow "Testes do fork" está `disabled_manually` desde
  2026-09-15, sem registro do motivo. A validação acima é local. Reativar é
  decisão do Rodrigo.
- **Não verificado:** se a Meta sempre envia o evento final na reautorização.
  O prazo de 10 s cobre o caso em que não envia.

## Fora do escopo, em issues próprias

- `autonomia/prospecting/website_scraper.rb`: proteção SSRF feita à mão (DNS
  rebinding, 100.64/10, IPv4 mapeado em IPv6). Trocar por `SafeFetch`.
- Saúde da suíte: poluição por recarga de classe e blobs fora de transação.
- Pré-existentes no fork, apontados pelo review:
  - loader do SSO de login pode ficar travado quando `authError` é limpo;
  - o prazo de 5 min do cadastro pode estourar num Coexistence longo.
