# F1 — primeira captura real e única revisão normal

Produto local real, sem payload de sucesso fabricado, conta/banco/usuários sintéticos `.invalid`. Snapshot29 `7aa776cd83245ee24807ba5bbbdad508e2e93c472db1615501846f7ef96bfd6e`; servidor Rails/Vite no M2, PostgreSQL/Redis próprios nas portas 59722/59723, sem Sidekiq worker e sem chamada de IA paga. Chromium isolado Playwright 1.59.1, sem Chrome pessoal. Captura desktop 1440×1080 inicial, não aprovada, em `.codex/preview/agents/screenshots/initial29-1440-light.png` (ignorada), SHA-256 `03125b9057da57897f74dfb0464f71b8ff175e2f2e37258cd708e01fc61e5bc2`; bytes copiados e verificados do M2, imagem lida pelo coordenador.

## Preparação local: causas e correções conhecidas

- Bash 3.2 com `set -u` recusou expansão de arrays vazios. Guard por quantidade nos loops de réplicas/filhos; mantém validações de branch/SHA/checksum.
- PostgreSQL não abriu porque o socket sob o caminho longo do snapshot ultrapassou 103 bytes. Todos os clientes já usam TCP loopback; runner desliga socket Unix somente deste cluster (`unix_socket_directories=`), conforme documentação oficial PostgreSQL 16: https://www.postgresql.org/docs/16/runtime-config-connection.html.
- Seed chamava `Agent#material_projection`, inexistente. Usa `TestDigest.for_agent` oficial e `Source#material_projection` para capturar material antes da alteração. Nenhuma alteração em modelos para acomodar fixture.
- Redis ficou órfão após matar o subshell do helper, mantendo o lock de workspace. PID 33754 escutava exclusivamente 127.0.0.1:59723 e `CONFIG GET dir` confirmou o diretório do runtime deste snapshot. Encerrado somente esse Redis com `SHUTDOWN NOSAVE`; runner agora usa `exec env -i` nos filhos persistentes. No fim do job seguinte não havia listener nessa porta. Nenhum serviço compartilhado foi encerrado, lock removido à força ou infraestrutura alterada.
- Manifesto tinha `pauseConversation: null` nas contas sem conversa, enquanto o contrato permite ausência. Seed agora omite os campos opcionais nulos; tipos obrigatórios e permissões permanecem reais. Viewer usa CustomRole só ver, editor CustomRole ver/gerenciar, admin papel administrador; SuperAdmin sintético separado.

## Execução real e resultado

Job `m2-eab92a23101049fba529a9353e6de969`: conta com agentes abriu e respondeu GET real. Título, cartões reais, estados/resumo, alvos de 44 px e ausência de overflow horizontal passaram antes da checagem Axe. O teste terminou vermelho em Axe: `button-name`, `color-contrast`, `html-has-lang`, `meta-viewport`, `role-img-alt`. Não afirmar que a tela passou, nem usar a captura de falha como aceite.

Contraste dentro da F1: texto pequeno slate-10 no branco/cinza, branco em brand, pills teal/blue/amber-11 sobre fundo-3 e switch blue-11 ficaram abaixo de 4.5. Correção na mesma rodada normal: tons existentes 11/12, preservando matiz e tokens, sem CSS próprio. Falhas adicionais do shell compartilhado (botão sem nome, avatar de usuário, pesquisa, idioma/zoom e aviso de fuso) exigem diagnóstico pontual; não desativar regras Axe para encobri-las.

R1 única formal dividida em três pareceres: `F0-F1-R1-tecnica.md` (dez achados da lista), `F0-F1-R1-rotas-foco.md` (leitor duplicado e Sidebar ativa) e `F0-F1-R1-produto.md` (duas lacunas de prova de componentes). A primeira captura real complementa essa mesma R1; não constitui outra revisão geral. Correção em um bloco, seguida de confirmação limitada; residual exige parada/causa raiz antes da passagem final e novo erro exige retorno ao Rodrigo.

## Prova anterior de integração JS, distinta do navegador

Snapshot30 `8087c05a474b66d3778a42d5b39a70dbee7802e6033d029fc434368ea18e4fa3`, duas réplicas verificadas antes/depois. Correção do vazamento de wrappers confirmou-se no job `m2-71e500da4e64409e8fa84c9d80943521`: 33 arquivos, 199 testes verdes, zero falhas/pendentes/erros externos, exit 0. Relatório `/tmp/chat2you-agentes-frontend-f1-leak-final30.json`, SHA-256 `b5e45e25287d7d43916c79b1ebfc30100663790cacfcbb55f5f6a7f64fae6e36`. Lint30 deixou uma formatação de import em SidePanel.spec, já formatada localmente; reexecução ainda pendente. Isso não substitui a validação posterior das correções R1.

Primeira tela Seus agentes ainda sem aceite de Rodrigo. F2–F7 continuam sem entrega visual. Sem commit/push/PR de implementação, merge, fila, deploy, produção ou novas consultas de produção.
