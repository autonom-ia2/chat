# F1 — retomada34: correções conhecidas e validação final local

Rodrigo respondeu “continue” após a sessão informar STOP33 e resultado8/17/3. Retomada restrita às causas identificadas, sem F2, PR/push/merge/fila/deploy/produção.

Aplicado por ownership: nome traduzido e aria-expanded no launcher mobile; dark:text-n-navy nos CTAs/confirm da primeira tela mantendo cores claras; text-white/90 no eyebrow/descrição/viewer do hero. Sem stylesheet global, alteração de permissão ou contrato de API. Harness aguarda GET scoped/HTTP/payload + heading/lista/estado/busy após reload final; mantém todas as asserções e Axe, agora também enquanto diálogos estão abertos. Sem sleeps, retries ou exclusões de regra.

Prettier e diff-check passaram. Próximo snapshot e matriz inteira única ainda pendentes. Se surgir erro residual na execução final, parar e retornar ao Rodrigo. Resultado33 preservado em sua auditoria (FAIL). Nenhuma captura aceita; F1 depende do aceite de Rodrigo e telas seguintes continuam pendentes.

## Resultado executado e parada visual

- Snapshot `20261008-034637-532a5b7b-5a476c9517-87a370f4`, SHA256 `5a476c951707b9e08ab702ac2d8dd62ad47657e13f25979d1cfc086d3be69a5a`, HEAD documental `532a5b7beb56902d2a0168013a3e8b657ba31488`.328 entradas dirty preservadas. Duas réplicas verificadas antes e depois, consistentes.
- Instalações offline isoladas M2 exit0: main `m2-c6168a97772642b2ad6d18256cc9cff1`; Playwright `m2-5dd156dcf3ca414d93ceaf083c47f506`. Avisos depreciação Node e Husky sem .git no snapshot esperados; nenhum runtime/global reinstalado.
- Matriz real job `m2-4823a14ae3d941a1acfa16ce553ea8d0`:28 planejados, **25 PASS,0 FAIL,3 SKIP intencionais**, exit0, duração1,6min, workers1/retries0. Claro/escuro1440/400, Axe serious/critical sem exclusões, inclusive diálogos abertos; pausa/religação/delete reais executados uma vez em fixtures sintéticas. Não é CI do PR.
- Log copiado SHA256 `29b6a1e445e30edbef7698ddf543ac6ee2fe74f579d924eb6bf642d9e8cff7a3`;33 PNGs nomeados + log copiados com SHA256 conferido, local `.codex/preview/agents/screenshots/retomada34/manifest-final.json`. Galeria nativa local `GALERIA.md` no mesmo diretório. Nenhuma captura branca34.
- Root leu todas as capturas400 em ambos os temas, as listas/vazio/mutação1440claro; r9_produto leu todos os desktop1440 claro/escuro e registrou nota separada. H1/eyebrow/descrição legíveis nos dois temas. Lista pós-delete renderizada com6 rascunhos, não branca. Diferença7→6 entre capturas esperada pela exclusão da fixture.
- Serviços próprios encerrados: nenhum listener59720–59723. Banco sintético preservado; nenhum worker de produção, provedor pago ou dado real.

### R34-VIS-01 — launcher cobre o aviso inferior no celular

Apesar do resultado automático verde, a leitura de `lista-real-lower-chromium-400-light.png` e `lista-real-lower-chromium-400-dark.png` mostra o launcher global sobre a porção esquerda do aviso final. Texto fica parcialmente coberto pelo botão de menu.

Causa: `MobileSidebarLauncher.vue:41-45` fixa o launcher em bottom4/start4 (alvo56px com wrapper), enquanto o conteúdo rolável de `AgentsListPage.vue:148,196` termina com `py-5` em400px, sem reservar a área ocupada pelo botão. Axe/overflow não verificam a sobreposição entre um controle flutuante e esse texto; o harness lower agora prova o fim da lista e expôs o problema visual.

Proposta mínima futura: reservar padding inferior suficiente no wrapper de conteúdo da F1 em larguras móveis (por exemplo, `pb-24 md:pb-7`), preservando o menu e a composição desktop. Validar screenshot e ausência de interseção entre `data-pause-notice` e launcher no fim da rolagem. **Não aplicado após o achado final.**

Sessão informou a parada e retorna a Rodrigo, sem nova correção ou rodada. F1 continua sem aceite visual global; F2–F7 e os grupos restantes do gate completo permanecem pendentes. Não houve novo commit/push/PR de implementação, merge, fila, deploy ou produção. Problema de ferramenta `Too many open files` intermitente após o teste foi recuperado para copiar/ler artefatos, sem intervenção em infraestrutura.

## Tracker

Issue1130 atualizada: https://github.com/autonom-ia2/chat/issues/1130#issuecomment-6054304179 . Não repetir a escrita de NextAction no Project neste turno: tentativas históricas terminaram INTERNAL e não produziram atualização verificada. Pendência de Project permanece explícita, sem elevar comentário de Issue a prova de campo atualizado. `git diff --check` passou após a documentação; arquivos de DB/migrations não foram alterados nesta retomada.
