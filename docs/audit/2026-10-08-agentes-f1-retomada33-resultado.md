# F1 — retomada33: resultado e autorização seguinte

Retomada do H1 autorizada por Rodrigo com “pode retomar”. Produto alterado somente na classe `text-white` do H1. Harness passou a capturar antes do Axe, rolar até Clara e executar a matriz inteira em uma execução, sem retries/exclusões.

## Prova executada

- Snapshot `20261008-033024-532a5b7b-652b87a602-0f4fb67c`; SHA256 `652b87a6027f7e0d7bc862f82b942de816a6b03c5b59bbcca9b39b08332fc716`.
- HEAD `532a5b7beb56902d2a0168013a3e8b657ba31488`, branch `docs/agentes-ia-prd`, 322 entradas dirty preservadas. Duas réplicas verificadas antes e depois; consistentes.
- Dependências offline isoladas M2: main job `m2-a8263a064e60437eba8be5b507da8347`, Playwright job `m2-db33d7f0399744f5a86f7411cae749cf`, ambos exit0. Aviso Husky sem .git esperado no snapshot; não é erro de produto.
- Navegador real job `m2-fe4ecfad391d451dac4367f29b318e38`, exit1: 28 combinações planejadas, **8 PASS, 17 FAIL, 3 SKIP intencionais**, zero retries. Desktop/claro sete PASS; desktop/escuro só viewer PASS; celular seis FAIL em cada tema. Repetições das mutações nos outros três projetos dispensadas.
- H1 do vazio legível e passou o cenário desktop/claro com Axe. Falhas restantes distintas: mobile menu sem nome acessível; CTA azul11 com branco sem contraste no escuro; eyebrow/descrição do hero usam tokens que ficam escuros no escuro. Não são 17 causas independentes.
- Captura de mutação inteiramente branca: PASS prova contrato de escrita/payload mas não renderização após o último reload. RCA separada identifica ausência de condição positiva de tela pronta. Não inferir crash de produto.
- 65 artefatos completos copiados com SHA256 conferido: 30 capturas nomeadas, 17 contexts, 17 screenshots de falha e log. Diretório local ignorado `.codex/preview/agents/screenshots/retomada33/`; nenhuma captura branca aceita.
- Sem listeners das portas próprias59720–59723 após cleanup; banco sintético preservado. Nenhuma produção/provedor pago/worker real.

## Parada e nova orientação

Depois do resultado, a sessão informou a parada das alterações e reuniu as causas. Rodrigo respondeu **“continue”**. Isso foi tratado como retomada restrita às causas recém-encontradas da primeira tela, com uma única validação completa posterior. Não autoriza F2, nova revisão geral, PR/push/merge/fila/deploy/produção.

Ownership da correção seguinte: técnica/cores/menu por r9_tecnica; sincronização da captura por registrar_decisoes; root integração, snapshot, validação e auditoria. Capturas reais por r9_produto e root. Sem reverter trabalho de outros.

Resultado posterior ainda pendente. O resultado33 permanece FAIL; não apresentar como CI ou aceite global. A suíte224 de snapshot32 é histórica e não substitui esta matriz.
