# #1172 — convite confiável e onboarding assistido mais rápido (Frente B)

Data: 09/10/2026. Branch `fix/1172-convite-confiavel`, empilhada sobre a #1163 (`8866352eff`).

## Causa raiz

- **Erro falso no convite.** `waitForInviteOutcome` disputava a resposta com um prazo de 5 s. Dentro desse prazo precisavam
  caber a permissão do Rails (ida e volta VPS→SSM→Rails) e o POST à Meta. O resultado era montado no `catch` antes de as
  tarefas da rota terminarem, então saía `write_started=false` com o convite enviado, e o Rails liberava a trava.
- **Lentidão em produção (60–100 s).** Vem quase toda do transporte antigo da VPS: cada chamada abre SSM/SSH e um Ruby
  novo, cerca de 23 s. Quem corrige isso é a #1163 (canal persistente e página aquecida), que ainda não foi instalada.
- **A "janela cega de 120 s" não existe.** O manager renova a sessão na hora (`session-manager.mjs`, `break` seguido de
  refresh). Esse item saiu do escopo.

## Decisões

| Item | Mudança | Liga quando |
|---|---|---|
| B1a | Permissão pedida antes do clique. A rota não tem `await` até marcar a escrita. `closeInviteGate` roda antes de ler `write_started`. Esperas limitadas pelo orçamento do manager (reserva de 35 s para publicar a conclusão). Classe da resposta registrada | Instalação na VPS |
| B1b | O Rails confere o claim de novo depois do `claim!` e libera, fecha e libera outra vez no caminho em que nada foi escrito | Deploy do Rails |
| B1c | `invite_not_sent`, emitido só pelo Rails depois de provar a liberação; a tela continua em "ausente" | Deploy do Rails |
| B1d | Depois de `invite_unknown`, a tela confere o status uma única vez | Deploy do Rails |
| B2 | A busca devolve o status apenas do @ exato | Flag `INSTAGRAM_TESTER_SEARCH_STATUS_ENABLED` (padrão off) |
| B3 | O convite reutiliza a página aquecida; se nada foi escrito, a página é invalidada | Flag `INSTAGRAM_TESTER_WARM_INVITE_ENABLED` (padrão off; depende de piloto real) |
| B4 | Consulta da tela a cada 250 ms | Deploy do Rails |
| B5 | Tempo por fase em ms, em listas fechadas, sem dado pessoal | Instalação na VPS |

Pendência que só a Meta real resolve: o formato de sucesso da resposta de convite (`payload.success === true`) nunca foi
observado. Qualquer outro formato vira `invite_unknown`, e o B1d mostra a verdade. O piloto registra a classe da resposta.

Desvio aceito: no caso de queda de conexão no meio do envio, o Chrome reenvia o POST por baixo da camada de rota (isso já
acontecia na base). O teste aceita 1 ou 2 POSTs no servidor e exige exatamente uma requisição da página.

## Validação local (HEAD do PR)

| Suíte | Resultado | Base |
|---|---|---|
| node --test | 445/446 (1 falha de ambiente: RubyJWT não instalado) | 403/404 |
| vitest (focal) | 125/125 | 104/104 |
| rspec (testers e publisher) | 264/0 | 226/0 |
| rubocop | 38 arquivos, 0 ofensas | limpo |
| Chrome sem Meta: route-stress, ui-failures, warm-meta-page, proxy-failures, invite-outcome (16 casos), latency-benchmark | passaram | — |
| manager-lifecycle | falha só no macOS (`private_profile_required`); roda na CI Linux | igual |
| Python VPS env | 61 OK | — |
| lint de e-mail, prettier, `i18n:fork:check` | limpos | — |

Todos os harnesses informam `production_mutated=false` e `meta_called=false`.

## Processo

- Desenho, três críticas adversariais e desenho final.
- Implementação item a item com TDD e revisor independente; B1a e B3 tiveram uma rodada de correção cada, por achado real.
- Painel final com 4 lentes e uma rodada de correção (5 commits).
- Revisão do lead.

## Release (cada passo com 🟢 do Rodrigo)

1. #1163 na VPS como release própria. Ela é o rollback da #1172.
2. Rails a partir da `main` mergeada.
3. VPS #1172 com as duas flags desligadas.
4. Ligar `SEARCH_STATUS`.
5. Piloto Meta real em perfil de teste.
6. Ligar `WARM_INVITE`.

Rollback: primeiro as flags, depois a VPS e, só então, o Rails.
