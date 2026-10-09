# F0 — integração local após autorização de retomada

Rodrigo autorizou prosseguir depois da parada final25. Conferência restrita às duas correções conhecidas, sem nova revisão geral: snapshot26 `520f4c0382924dfde59d2b1d15757c1855eddaf61541ad06694887a34a0a20f6`, Ruby 222 exemplos/zero falhas/zero pendentes; RuboCop 106 arquivos/zero infrações. As duas réplicas foram verificadas antes/depois. JS25 mantém 43 verdes, sem mudança nesses consumidores até o começo de F0. Parecer `revisoes/B2-retomada-conferencia26.md`.

Divisão: A extrai controles/locale D9; C integra foco/SidePanel/Audience; B implementa primeira lista e seus testes; root integra kit, token, rotas/retomada e prévia. F2–F7 mantêm leitores/componentes reais legados durante staging; nenhuma página vazia. Primeira aceitação permanece Seus agentes; aprovação visual do Rodrigo é requisito para avançar.

Token D4: inventário conferido, 18 usos em 12 arquivos do dashboard. Edição automática abrangente foi bloqueada por PreToolUse (hook chain failed closed), sem causa detalhada. Alternativa mais restrita: patch com somente as linhas verificadas dos 12 arquivos e `theme/colors.js`; token `n.navy` conserva `#0D2344`. Stops distintos de gradiente e página pública de Links/QR são preservados.

Formatos do Guia: check oficial26 encontrou os três artefatos fora de dia após as alterações de controller/BE05. Regenerar pelo gerador oficial, copiar bytes exatos e confirmar check; não editar JSON à mão. Snapshot26 de prova não pode ser alterado pelo gerador: sua saída será escrita em diretório temporário fora do snapshot usando `Autonomia::Guide::Formatos.gerados`.

Situação de navegador: IAB indisponível nesta retomada. A cópia publicada já foi percorrida no registro anterior; não declarar inspeção visual atual sem captura real. Não usar Chrome pessoal nem contornar recurso previamente negado. A validação local de produto usará navegador isolado e backend/banco sintéticos reais, sem payload de sucesso fabricado.

Sem novo commit, push, PR de implementação, merge, fila, deploy, produção ou novas leituras de produção. Os checks/capturas/revisões F0/F1 ainda não estão fechados.

## Primeira execução F0/F1 — snapshot28

Snapshot `20261007-211334-532a5b7b-8a94ac4e55-68a31aaa`, conteúdo `8a94ac4e5505e5ba169917423b74282fe80bfadc141a21ed966a02b5ac2e08ed`, ambas as réplicas verificadas antes da execução. Dependências locais instaladas no snapshot M2, sem copiar checkout ativo.

- Job JS `m2-034b666fe12743988500c79a5bcb3607`: 192 testes passaram, quatro falharam, zero pendentes; um arquivo adicional não carregou por uso de `ref` importado dentro de `vi.hoisted`. Relatório `/tmp/chat2you-agentes-frontend-inicial28.json`, SHA-256 `327800ab767e5337e85ddf8275dace6d30a3f590297f65aa6a587d1a1018c2f4`. Vitest contabiliza suites também por blocos; esses contadores não equivalem ao número de arquivos.
- Uma falha CampaignJourney é ambiente: faltou `TZ=UTC`, presente no script oficial `package.json:test`. O helper só mudou de import. Duas falhas SidePanel exigem investigação do ciclo de foco/transição; a quarta está na interpolação de canal no teste AgentRow. Não declarados como regressões resolvidas sem reexecução.
- Job ESLint `m2-22f7c86deaef462fb9ce730747981db3`: 83 arquivos, dez erros (nove formatação e um uso de prop no stub), 750 avisos; relatório `/tmp/chat2you-agentes-frontend-lint28.json`. Correções iniciais em andamento.
- Check oficial dos formatos do Guia `m2-1d5122de207649d9bf7395fc4dbbac00`: em dia, após copiar os três artefatos do gerador oficial26. Não houve edição manual desses artefatos.

Esta é a primeira execução dos testes escritos para F0/F1. O estado RED anterior era esperado por inspeção, não uma execução registrada. Integração inicial ainda aberta; a rodada formal normal F0/F1 não começou. A aceitação visual e a suíte de navegador com banco sintético continuam pendentes.
