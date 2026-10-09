# Revisão final F0 pós-D7 — contrato

**Resultado: PASS nesta revisão final limitada.** Os três bloqueios do contrato pós-D7 foram corrigidos no
desenho. Isso não aprova implementação, telas reais, protótipo, merge, fila, deploy ou produção; o F0 permanece
DRAFT conforme o próprio alvo.

**Alvo:** `docs/agentes-ia-redesign/design/F0-mapeamento.md`, SHA-256
`10b95f401f5d28c59d8c33c95690abe356a0344e34348a4d93afbf1ccd28ce98`.

**Escopo:** única revisão final dos achados `F0-D7-01`, `F0-ROUTE-02` e `F0-D9-01`. Não reabri a revisão normal
anterior nem examinei outros contratos; não executei testes, build, navegador, banco, serviço, autenticação,
SSO ou produção.

## Fechamento dos três bloqueios

### F0-D7-01 — disposição do convite legado

**Fechado.** O F0 agora classifica `InviteConnectionPage` e `autonomia_invite_connection` como superfície global
preexistente de convite/onboarding, fora do redesign de Agentes, preservando menu de perfil, retorno de SSO,
recursos Rails, autenticação e permissões (`F0-mapeamento.md:152-154`). Ao mesmo tempo, fixa que o kit, a lista,
o Construtor, Ligue e o painel novos não importam nem apontam para essa superfície e não recebem `from`; o único
atalho do redesign é `settings_inbox_new` na área central (`:156`). Isso fecha a compatibilidade do onboarding
sem reintroduzir conexão, QR ou criação de caixa na jornada nova.

### F0-ROUTE-02 — E2m separado da retomada guiada

**Fechado.** A exceção manual agora está separada em todos os pontos relevantes: E2m ramifica antes de BE-05,
usa o painel legado nomeado e não chama `build_thread`, enquanto somente retomadas guiadas E1–E4 por editor
usam o leitor BE-05 (`F0-mapeamento.md:144-150,160-172`). A matriz distingue E2m, viewer e guided; a API manual
continua coberta separadamente pelo `422 manual_mode` (`:172`). A sequência F2 repete a separação e proíbe
`start`/job/thread no caminho manual (`:190-193`). O contrato deixou de exigir BE-05 para E2m.

### F0-D9-01 — ownership do foco e migração da gaveta

**Fechado.** A tabela D9 distingue baseline e API alvo: `useModalFocus({ container })` passa a devolver
`activate/deactivate` apenas para Tab/Shift+Tab, e o `SidePanel` fica como único dono de foco inicial, Escape,
gatilho, restauração e ciclo de fechamento (`F0-mapeamento.md:47-52,67-75`). A migração de `AudienceSidePanel`
ocorre no mesmo bloco, removendo a chamada antiga, preservando a API pública e emitindo `close` uma única vez em
`afterLeave`, depois da restauração do foco (`:73`). A ordem de extração registra essa exceção interna sem
reexport ou listener paralelo (`:77-82`). Não resta a ambiguidade entre contrato observável e ownership.

## Conclusão e limites

Não encontrei residual dentro dos três achados desta rodada. A checagem apenas confirma a consistência documental
da correção final; não transforma o STOP histórico anterior em aprovação retroativa, não valida o código e não
libera a implementação. F0 continua dependente dos gates e critérios já descritos no próprio documento.

## Validação

- SHA do alvo conferido antes da leitura: `10b95f401f5d28c59d8c33c95690abe356a0344e34348a4d93afbf1ccd28ce98`.
- Causa raiz pós-D7 e correção única comparadas com as linhas normativas do F0.
- Nenhuma alteração em `F0-mapeamento.md` ou no produto; nenhum teste, build, navegador, banco, serviço, auth,
  SSO, commit, push, PR, merge, deploy ou produção executado.
