# Instagram assistido — prova de operações no Chrome da VPS

## Escopo autorizado

Rodrigo autorizou em 07/10/2026 continuar o plano discutido: validar operações administrativas dentro do Chrome existente antes de integrar a plataforma. A primeira observação é somente leitura, sem convite, nova publicação de sessão, alteração de proxy, instalação de runtime ou deploy AWS. Perfil, sandbox, identidades e locks permanecem protegidos. A aprovação do plano não declara sucesso nem dispensa revisão da release.

Issue #995; branch `codex/995-browser-operations-20261007`, base `496258e375939e9c531e38a39128ea096397f676`. Continuidade documental anterior na PR #1124, commit `4f0907a186d926776fcf909d7cf52ecb5b88261a`: navegador Roles 200, Client Rails 400, causa específica ainda desconhecida. A PR #1112 já foi merged/instalada; não reinstalar as correções anteriores.

## Estado revalidado antes da observação

- 18:44 UTC: acesso SSH normal à VPS confirmado; release selecionada `2cc6b4fb6e275e26c04ae126c06ac1b4f0b63b26`. Oito units Instagram ativas/running, sem restarts automáticos registrados.
- Memória disponível aproximadamente 18 GiB; carga do host aproximadamente 7. Os limites dos managers continuam CPU 150%, MemoryHigh 1536 MiB, MemoryMax 2 GiB e TasksMax 256. Nenhum aumento proposto; n8n não foi alterado.
- 18:45 e 18:48 UTC: AWS das duas stacks executa `496258e375939e9c531e38a39128ea096397f676`, com sessão administrativa presente, ponteiro ativo e gestor saudável; contas restritas 1/18 preservadas. Isso é saúde/publicação, não comprovação de busca, OAuth ou caixa conectada.
- Diff da base vigente contra `383ed42f82659a2891ca59e506e9ea86e8002e1d`: nenhum delta nos scripts Instagram e serviços Instagram da aplicação.

## Responsabilidades e critérios

Íris revisa o contrato/controle de busca; Atlas revisa comunicação e concorrência; Nexo faz revisão independente. Root é o único executor de produção. O candidato local é diagnóstico, não release.

Primeira etapa: abrir somente a página Roles, exigir resposta 200 validada pelo observer existente e ler estrutura limitada do DOM. Nenhum clique/preenchimento. Saída somente com enums públicos de interface, contagens, flags e status/tamanhos; sem textos livres, IDs, HTML, valores de campo, cookies, headers ou respostas. Encontrar um controle não equivale a executar busca.

O runner pausa/drena somente manager Autonomia, exige exclusividade do perfil, lança uma unit temporária com limites e proteções equivalentes e só restaura o manager após encerramento/lock comprovados. Os sete outros serviços e os limites são comparados antes/depois. Fonte fixada por SHA-256, prazo global e recibo próprio.

Revisão inicial encontrou mismatch entre campos do candidato e do runner; corrigir e revisar o SHA final antes de executar. Nenhum diagnóstico executado até este checkpoint.

## Integração condicionada à prova

O Chrome headless já renova sessões na VPS. O canal publisher é iniciado pela VPS e não executa pedidos administrativos enviados pelo painel; não reutilizar a fila de reconexão humana como fila de operações. Implementação futura exige contrato separado para search/status/invite, entradas fixas, correlação/deadline, claim único e resultado sanitizado. Não transportar cookies para Rails nem expor URLs/JavaScript arbitrários.

Para busca/status, comprovar primeiro a ação natural e seu contrato; convite depende de seleção explícita e reconciliação de resultado incerto. OAuth/reautorização da caixa permanece no fluxo existente e é distinto da sessão administrativa. Release deve seguir PR, Project, revisão, aprovação, fila/MERGED e deploy/instalação com rollback separado por stack.

## Resultado

Pendente: observação estrutural revisada, busca real autorizada, integração, convite/OAuth e reconexão completa. Não encerrar #995 nem declarar conexão funcional.
