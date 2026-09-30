# Implementação de Relacionamentos — #785 — 30/09/2026

## Autorização e escopo

Rodrigo aprovou a proposta e autorizou implementar. Depois pediu seis capturas reais antes de merge/deploy. Esta frente usa a issue #785, a branch codex/785-relationships-mockups e o PR #786 já existentes, em worktree separada. Base main: 29109e6d078b8cc5f115076a284777b25a3f57dd. Aprovação antiga de campanhas não autoriza liberar esta alteração.

Entrega: dashboard arredondado nas listas de contatos/empresas; cantos suaves nos itens; lateral 37rem (592px), +32,14% contra 28rem (448px); ações depois da identificação; Notas ao abrir contato e Contatos ao abrir empresa; mídias compartilhadas nos dois contextos, com miniaturas 96px. Abaixo de 1280px o painel sobrepõe o formulário. Links explícitos para mídias continuam válidos.

## Decisões e revisão

Inclusão via componentes em components-next/Relationships e slots opcionais nos layouts existentes. Não copiar páginas inteiras, alterar contratos de gravação ou usar CSS próprio. Tamanho anterior preservado fora do layout de Relacionamentos. Formulários e fluxos de envio/chamada continuam nos componentes existentes; bloquear contato e excluir empresa ficam em Mais ações. Exclusão mantém confirmação e permissão administrativa.

O dashboard precisa de agregados reais: endpoints de leitura contacts/summary e companies/summary, com autorização igual ao índice de cada entidade. Uma consulta agregada por tela sobre a base inteira da conta, independente de filtros e paginação. Contatos usam o mesmo resolved_contacts do índice. Novos usa created_at; atividade usa last_activity_at; janela móvel dos 30 dias anteriores à leitura. Empresa nunca ativa entra em “sem atividade” somente quando criada há mais de 30 dias. Com contatos usa contacts_count. Consulta ao abrir a lista, sem promessa de atualização em tempo real.

Mídias: extrair a apresentação e leitura da empresa para RelationshipMedia e MediaQuery, preservando CompanyMedia/CompanyMediaQuery como adaptadores compatíveis. Acrescentar leitura de mídias do contato no overlay Enterprise, sem alterar attachments antigo. Contato limita aos próprios registros; empresa limita aos seus contatos da mesma conta. Ambos usam o filtro de permissão de conversas e autorização adicional no arquivo, URLs temporárias de um minuto e resposta privada/no-store. O gate anterior de mídias é preservado. Contatos sem o gate mantêm a galeria anterior.

Revisão manual dos contratos, comparação da extração com o código anterior, permissões, troca de conta/registro e respostas atrasadas. Ao trocar de contato, formulário e rascunho de notas são remontados pelo ID; abas voltam ao padrão. O watcher compara accountId/contactId individualmente: mudar apenas o filtro/página das mídias não recarrega a ficha nem perde a lista expandida. Esse ajuste veio da aceitação de paginação no navegador. Leitura legada acompanha a troca de registro/gate. Não houve revisão independente por outro agente nesta etapa.

## Evidência local

Ambiente descartável, sem dados de clientes: PostgreSQL chat2you_785_test em loopback, Rails 37851, Vite 37852, Redis DB14, Overmind/socket exclusivo. Setup privado em .codex. Sem chamadas pagas, envio de mensagens, chamadas telefônicas, migração, segredos ou produção. Fixtures e autenticação sintética nunca entram no Git.

- `TZ=UTC pnpm test --maxWorkers=2 --minWorkers=2`: 615 arquivos e 6.832 testes passando antes do ajuste final do watcher; depois dele foram repetidos os 125 testes relevantes e a aceitação no navegador. A suíte completa no SHA final fica para o CI.
- Reexecução dos testes existentes de Relacionamentos, CompanyDetailView e ContactOptOut após os últimos ajustes: 15 arquivos, 125 testes passando. Expectativas existentes do padrão de empresa foram atualizadas de Histórico para Contatos.
- RSpec existente (CompanyMediaQuery, CompanyMedia, Delivery, ContactsController, CompaniesController): 107 exemplos, zero falhas. Ruby 3.4.4 via rbenv. A primeira execução encontrou erro de autoload na posição do módulo compartilhado; corrigido movendo para enterprise/app/controllers/relationships; reexecução verde.
- Script privado de aceitação da API, com 13 verificações: agregados contatos 55/7/22/18 e empresas 29/3/10/16; busca/página independentes; mídia antiga localizada fora da primeira página; paginação de 27 arquivos; parâmetro inválido 422; JPEG e original autorizados; outro contato/conta negados; agente sem acesso à conversa não vê arquivo/contagem; gate desligado retorna 403.
- Chrome real sobre Rails/Vite: 24 estados em 1630, 1280, 1024 e 390px, zero exceções JavaScript e nenhum overflow horizontal de página. Lateral desktop medida 592px; imagens carregadas e medidas 96px em ambos os contextos. Ações desktop contidas e alinhadas; painel mobile fecha com Escape.
- Aceitação adicional no navegador após corrigir o watcher: seis verificações passando, incluindo troca de contato sem carregar rascunho anterior, busca de arquivo antigo, página 2 com os dois arquivos restantes de 27, retorno à lista curta e confirmação de exclusão cancelável. Nenhuma exclusão/envio/chamada foi executada.
- Seis capturas reais em docs/relationships/screenshots/785, com dados fictícios e componentes da aplicação. As imagens em mockups/785 continuam sendo a proposta ilustrativa.
- ESLint dos 21 arquivos frontend tocados: zero erros, 147 avisos (principalmente catálogo i18n/dynamic keys); RuboCop dos 11 arquivos Ruby: zero infrações.
- Fork i18n: oito catálogos, 15.768 mensagens compiladas, cobertura en/pt_BR. Gate AST sem regex nova passou; sua base histórica inclui alterações anteriores.
- Guia: 169 fluxos, 170 telas, zero telas sem explicação, arquivos gerados sem mudança. Central: 174 artigos/170 telas, check passou com avisos preexistentes sobre referências/linhas. `git diff --check` passou.

Comandos Ruby sempre depois de `eval "$(rbenv init -)"`; não encadear teste e commit. Hook Husky local incompleto; validações executadas manualmente e desativação de hook restrita ao comando de commit/push, sem configuração global.

## Limites e liberação

O ambiente macOS não tem libvips disponível. Para validar entrega visual foi anexada prévia JPEG sintética pronta, gerada a partir de asset de teste do repositório. Isso comprova leitura e apresentação, não a conversão nativa. A conversão e a imagem Linux final continuam exigindo os jobs do workflow Relationships no SHA do PR; resultados antigos do PR de mockups não valem para esta implementação.

Há 404 no endpoint de limites Enterprise da instalação local sem billing; não são leituras de resumo/mídia e não houve alteração desse endpoint. Não afirmar ausência absoluta de regressão, equivalência com produção, cobertura de todos os dispositivos ou compatibilidade automática com futuras versões. Conferência nesta etapa usa tema claro e estados descritos.

Sem merge/deploy. Liberação depende da conferência visual do Rodrigo, revisão, CI verde no SHA final e autorização explícita de merge/deploy. Não há migração ou mudança de infraestrutura; rollback é a imagem anterior da aplicação. Smoke após liberação: listas/agregados da conta, abas padrão, mídias permitidas/negadas, painel móvel e edição normal. Compatibilidade com upstream requer revisar apenas os encaixes opcionais e as novas leituras após upgrade.

## Correção visual após a primeira entrega

Rodrigo apontou diferença entre o dashboard implementado e o mockup aprovado, além de aparência inadequada do último item das abas. Esta revisão mantém a mesma issue, branch e PR, ainda sem merge/deploy.

O resumo recupera a composição da proposta: título fora da faixa, cantos 3xl, destaque azul suave no total, números maiores, ícones circulares e descrições abaixo dos valores. Usa tokens existentes da instalação, sem cores novas, gráficos inventados ou mudanças nas consultas. Itens de lista ganham avatares circulares de 48px e sombra discreta.

RelationshipTabs acrescenta cabeçalho Acompanhamento, abas de pelo menos 44px e distribuição equilibrada. No desktop as cinco abas ficam na mesma linha; em largura menor podem se distribuir em linhas completas, sem truncar rótulos. O componente fica restrito ao layout de Relacionamentos, mantendo TabBar nos demais contextos. Inclui estado selecionado, associação ao painel e navegação por setas/Home/End. Notas e Contatos continuam como padrões.

Enviar mensagem, Chamada e Mais ações têm alturas consistentes; Chamada e Mais ações usam contorno. No celular, o conjunto usa grade planejada, com Enviar mensagem na primeira linha e nome visível em Mais ações. A abertura da lateral deixa de animar a largura do contêiner somente em Relacionamentos: o painel continua deslizando, com largura estável, evitando comprimir as abas durante a entrada. Lateral de 592px e miniaturas de 96px são preservadas.

O CI anterior apontou três avisos bloqueantes: separador de datas sem i18n, ordem de atributos e fechamento do elemento time. Corrigidos sem alterar regra de negócio. O mesmo gate estrito foi executado localmente sobre os 22 arquivos frontend acumulados: zero achados bloqueantes, 13 avisos permitidos de chaves dinâmicas. Prettier passou em todos. Fork i18n compilou 15.786 mensagens dos oito catálogos. Gate AST passou em 267 arquivos, contra a base histórica do script.

Testes existentes repetidos na revisão final: 15 arquivos e 125 testes passaram. A primeira execução sem TZ=UTC encontrou uma expectativa de data dependente do fuso; reexecutada no ambiente UTC documentado pelo teste, sem alterar seu código. Comando: `TZ=UTC pnpm exec vitest run app/javascript/dashboard/components-next/Contacts app/javascript/dashboard/components-next/Companies app/javascript/dashboard/components-next/Relationships app/javascript/dashboard/routes/dashboard/contacts app/javascript/dashboard/routes/dashboard/companies app/javascript/dashboard/routes/dashboard/relationships`.

Os slots do cabeçalho e painel recebem contexto opcional desktop/mobile, permitindo IDs distintos nas duas apresentações e associação correta das abas ao conteúdo. A revisão manual verificou compatibilidade com os consumidores anteriores, que ignoram essa informação.

A aceitação de navegação rápida identificou uma consulta a contacts/undefined/contactable_inboxes: o carregamento da ficha lia os parâmetros novamente depois de aguardar outra consulta, quando a rota já havia mudado. fetchActiveContact agora captura o ID inicialmente e só busca caixas contatáveis se conta e contato continuam sendo os mesmos. Não há coerção de ID, retry ou alteração no contrato da API.

Navegador: nova rodada de 24 estados em quatro larguras, sem exceções JavaScript, miniaturas carregadas de 96px e painel desktop de 592px. Depois dos ajustes finais das ações, dez estados adicionais passaram: seis combinações contato/empresa em 1630, 1280 e 390px, mais quatro telas no tema escuro. Verificados rótulos inteiros, altura mínima 44px, cinco abas na mesma linha no desktop, Mesclar no último item, navegação por Home/End, IDs únicos e associação do painel. No contato a 390px, Enviar mensagem mede 342px na primeira linha; Chamada e Mais ações, 167px cada na segunda. Sem falhas HTTP nessas leituras, exceto o endpoint de limites Enterprise já descrito. Seis verificações de fluxos foram repetidas após a correção da troca de telas, com zero exceções; nenhuma mensagem/chamada/bloqueio/exclusão foi executada.

Durante as primeiras execuções, edição com HMR e três navegadores em paralelo produziram timeout e uma exceção de inicialização de BackButton. Os processos locais próprios foram reiniciados; as rodadas acima foram executadas em sequência, sem alteração desse componente e sem repetição da exceção. Esses resultados não são evidência de produção.

O workflow Relationships do commit anterior 64704b206fff40fad774ac9049bd1154844ca4fe concluiu regression e production-image-runtime com sucesso; a verificação de Email UI desse SHA falhou nos três avisos já corrigidos. O SHA desta revisão ainda requer sua própria execução de CI. Capturas da revisão final são da aplicação, em ambiente isolado, com dados fictícios, sem edição dos pixels. As animações são estabilizadas pelo navegador ao capturar, para não registrar um hover em transição.
