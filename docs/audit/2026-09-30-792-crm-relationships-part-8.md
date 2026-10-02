# #792 — Parte 8: Nova oportunidade pela ficha do contato

## Autorização e escopo

Rodrigo aprovou a parte 7 e autorizou este incremento: abrir Nova oportunidade pela ficha do contato já com a pessoa selecionada, apresentar telas reais e parar para novo aceite. Base `01568e4aacb7ba7b1b12020cbe190451e14a1fb5`, branch `feat/792-crm-relacionamentos`, Issue #792 e PR #793 em rascunho. Sem autorização de merge/deploy. Nada alterado na AWS, nas credenciais, nas dependências ou no esquema de banco.

Referência: cenário M06 do HTML aprovado `chat2you-crm-relacionamentos.html`. O botão Nova oportunidade da ficha conduz ao CRM e seleciona o mesmo contato; não preenche um título comercial fictício nem cria uma cópia do cadastro.

## Implementação e experiência

`ContactOpportunityLink` insere a ação na barra nativa da ficha, preservando mensagem, chamada e menu existentes. Exige CRM global habilitado, permissão de visualizar CRM e de gerenciar oportunidades. O controle usa tokens/ícones nativos, alvo de 44px e indicação acessível de nova aba.

**Diferença intencional em relação à demonstração:** o CRM abre em outra aba. A ficha atual é um formulário editável com campos ainda não salvos; a nova aba preserva esse preenchimento e sua navegação. Não adicionamos uma segunda gravação implícita nem copiamos o rascunho da pessoa. O CRM consulta o cadastro confirmado no servidor. A ação tem ícone de abertura externa, `target="_blank"`, `rel="noopener noreferrer"` e descrição para tecnologia assistiva.

O endereço leva somente `new_contact_id`, dentro da conta atual. Nenhum nome, e-mail, telefone ou objeto cadastral é colocado na URL. `CrmOpportunityFromContact` valida a forma do ID antes da leitura, consulta contato/empresa por APIs nativas e espera um funil/etapa disponível. Contato indisponível gera erro com Tentar novamente/Cancelar; não é convertido silenciosamente em uma oportunidade avulsa. Link malformado ou misturado com `card_id` não abre criação contextual. Sem permissão, o carregador não consulta o contato.

Respostas de uma conta/seleção anterior são ignoradas pelo `useAbortableRequest`, incluindo a consulta subsequente de empresa. O contexto é consumido com `router.replace`; as demais chaves da URL são preservadas. Atualizar a página após cancelar não reabre uma criação antiga. Uma nova intenção não substitui um rascunho aberto sem passar pelo guard existente.

O formulário e o drawer existentes receberam somente `initialContact`. O contato inicial já confirmado não torna o formulário sujo; trocar/remover a pessoa, escolher sem vínculo ou editar dados comerciais torna. Atualizações de etapas não sobrescrevem uma escolha posterior de contato. Salvar usa a API de criação existente, com `contact_id`, sem escrever os dados da pessoa/empresa. O botão Voltar ao contato usa a confirmação de descarte já existente. Não se cria outro editor, rota, API ou modelo.

A largura permanece 40rem/640px no desktop e notebook; celular usa a largura disponível. O rodapé continua fixo. A criação contextual de empresa e a visão completa das oportunidades nas fichas não foram iniciadas neste incremento.

## Revisão e correções necessárias para o checkpoint

### Falha do CI da parte 7

O job `110059764189`, run `36765870218`, falhou em `opportunity_creation_spec.rb:20`, ao comparar timestamps de uma instância recém-criada com os mesmos timestamps lidos do PostgreSQL: nanossegundos em memória contra microssegundos persistidos. O snapshot agora usa `contact.reload.attributes` antes do teste, conservando a comparação integral posterior. Não foram removidos testes/asserções nem alterado comportamento de produção para satisfazer o teste. A bateria local equivalente à seleção backend do workflow foi reexecutada.

### Referência circular no botão Voltar

O primeiro roteiro de navegador passou pela criação contextual real, preservação da ficha, retorno e erro de contato indisponível. Ao recarregar a ficha durante o ensaio responsivo, surgiu `Cannot access 'BackButton' before initialization`, em `SettingsHeader.vue`. A inspeção confirmou que `BackButton.vue` importava estaticamente o roteador completo, que por sua vez importa as telas que usam `SettingsHeader`/`BackButton`. O ensaio coincidiu com a regeneração/HMR do mapa do Guia; não se afirma que isso, sozinho, prove falha equivalente em produção.

Foi removida a importação circular: `BackButton` agora obtém a instância via `useRouter()` no setup. Destino explícito, retorno de histórico, legenda e modo compacto permanecem iguais e ganharam quatro testes. O erro não foi filtrado do roteiro. O ambiente de teste foi estabilizado após a geração do Guia e os cenários foram repetidos. A alteração de suporte motivou também a execução da bateria frontend completa, além dos testes focados.

### Conferência de persistência

Na segunda execução, os 13 cenários de interação passaram, sem exceções JavaScript. O comparador separado de banco acusou diferença porque o snapshot inicial usava o gerador JSON padrão (datas textuais em UTC) e a leitura final usava JSON do ActiveSupport (ISO8601). A inspeção encontrou divergência somente no formato de `created_at`, `updated_at` e `last_activity_at`, tanto no contato quanto na empresa; com o mesmo gerador, não havia diferenças.

Para não aceitar uma comparação com perda de precisão, o preparo e o verificador passaram a ler os registros persistidos e serializar ambos em ISO8601 UTC com seis casas decimais. Um novo ensaio completo foi executado a partir desse baseline e passou, sem reescrever contatos/empresas durante a ação. Não foram removidos campos da comparação nem tratado erro de dados como sucesso.

## Ambiente e evidências

Somente banco local `chat2you_792_ui_test`, usuário administrador e usuário de papel somente leitura sintéticos. Requests RSpec em banco separado `chat2you_792_test`. Jobs/e-mails com adaptadores de teste e sem worker de entrega. App `http://127.0.0.1:3792`, Redis 6792. Browser plugin não disponível: Playwright/Chrome já instalados, login pela UI normal. Respostas de negócio não são simuladas no roteiro desta parte; solicitações externas são bloqueadas para isolamento.

As capturas finais foram feitas com o **bundle compilado de teste**, não com hot reload: servidor Vite 35792 parado, build final concluído e Rails local iniciado com `CI=true`, opção nativa do ViteRuby que desliga o proxy de desenvolvimento. O primeiro ensaio desse modo ainda solicitava `@vite/client` e recebia 500; o probe de login identificou as URLs e o ambiente local foi corrigido, sem modificar a aplicação para simular assets. O ensaio final verificou carregamento do painel em `/vite-test/assets/dashboard-q6SDYVNF.js`, ausência de `@vite/client` e executou todos os fluxos sobre o build real. Não se trata de deploy em produção.

O roteiro confere URL/título, conteúdo visível, ausência de overlay, exceções JavaScript, dimensões e ações. Capturas/hashes, manifesto e verificação direta de persistência ficam em `docs/relationships/screenshots/792-part8/`. Scripts e logs temporários em `.codex/792/part8-*`; autenticação e snapshots detalhados sintéticos não são publicados.

## Validação final

| Verificação | Resultado |
|---|---|
| Frontend completo, `pnpm test --maxWorkers=2 --minWorkers=2` | 7.043 testes em 631 arquivos aprovados, sem falhas. |
| Rechecagem final dos componentes afetados | 78 testes em cinco arquivos aprovados após a organização de macros exigida pelo lint; não somar aos 7.043. |
| Backend, seleção completa equivalente ao workflow de Relacionamentos | 482 exemplos: 478 aprovados, zero falhas e quatro suspensos antigos. |
| Navegador, parte 8 compilada | 14 verificações aprovadas (13 interações/contratos e prova de bundle), oito screenshots, nenhuma exceção JavaScript não tratada. |
| Regressão real do cadastro composto da parte 7, também no bundle compilado | 14 verificações aprovadas; inclui concorrência, rollback, reutilização e perda da resposta após gravação. |
| Banco após o roteiro contextual | 53 → 54 oportunidades; mantidos 36 contatos, 17 empresas, 33 mensagens e duas conversas. Mesmo contato/empresa e todos os campos/timestamps comparados com precisão de seis casas, sem alteração. |
| Banco após o roteiro de regressão seguinte | Oito oportunidades, sete pessoas e três empresas novas, exatamente o previsto pelo roteiro; nenhuma nova mensagem/conversa. Conferência separada da parte 8. |
| Build | `pnpm exec vite build --mode test` aprovado; avisos de chunks grandes mantidos e não mascarados. |
| Lint | 12 fontes/testes JS/Vue, zero bloqueadores e dez avisos de chaves dinâmicas já aceitos pela política. |

Os quatro suspensos são os três casos históricos de visibilidade do CRM (`cards_spec.rb:333,556,583`) e a associação legada de `Account` (`account_spec.rb:52`), incluída na bateria mais ampla. Nenhum teste foi suspenso neste incremento e nenhum deles conta como aprovado. A falha de comparação de timestamp do CI anterior foi corrigida e a seleção equivalente passou localmente.

Os 28 checks de navegador não significam cobertura de todos os navegadores ou conclusão da revisão independente. Foram validados desktop 1620×1000, notebook 1366×768 e celular 390×844 no Chrome. A conta somente leitura foi testada com autenticação e endpoint reais: ação ausente e criação recusada, inclusive por solicitação direta. Os 404 da consulta local de limites Enterprise, o contato propositalmente inexistente e os erros esperados de autorização/validação/rede permanecem nos manifestos; não houve exceção JavaScript não tratada nos roteiros finais.

Comandos adicionais: Prettier, RuboCop no spec alterado, `pnpm guia:check`, `pnpm central:check`, `pnpm i18n:fork:check`, `pnpm relationships:check` e `git diff --check`. O Guia contém 170 fluxos/170 telas e os oito catálogos do fork têm 16.174 mensagens conferidas. As fontes e os hashes das imagens são conferidos novamente antes e depois do commit.

A mudança não tem migração nem dependência nova. Os resultados locais não substituem o CI remoto do commit final: sua situação é consultada e comunicada separadamente.

## Limites e próximo aceite

A abertura contextual usa os cadastros confirmados e não salva alterações ainda em edição na aba original. Essa escolha é explícita, não sincronização de rascunhos entre abas. O botão Voltar ao contato abre a ficha canônica na aba do CRM; a aba original permanece intacta.

Próximo incremento proposto: listar as oportunidades vinculadas na ficha do contato; a ficha da empresa vem depois. Ainda faltam a integração completa das oportunidades com as fichas de empresa/contato, revisão transversal de permissões e escritores concorrentes, revisão independente e validação integral antes do pedido de merge. O teste local não certifica as integrações/automação da AWS. O futuro merge pode disparar workflows de outras stacks e requer autorização separada. Sem merge parcial para testar e sem deploy.
