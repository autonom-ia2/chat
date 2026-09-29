# Relacionamentos — plano aprovado (Issue #757)

Base: `8396d7255e097ba79507a22081701eb41ddb6ce5`. Repositório `autonom-ia2/chat`.
Origem: `Plano_Implementacao_Relacionamentos_Chat2You_v1.md`, aprovado por Rodrigo em 29/09/2026. SHA-256 do arquivo original: `c2a7cc3b418291fb0390727c4ea7f60b37c5fd4fd0d28f0d0fd23d959d201299`.
Esta versão operacional reúne os requisitos do documento aprovado. Não é autorização de merge ou deploy.

## Aditivo prevalente — retomada

A regra de 29/09 proíbe regex nova, inclusive normalizadores e motores. As menções abaixo
à regex são histórico do plano, substituídas pelo contrato em attributes-and-visibility.md:
nenhum campo de regras no modal/endpoint novo; metadados legados intocados e valores
com validação histórica editados pelo caminho legado, rejeitados no endpoint novo.

## Autorização e limites

Rodrigo autorizou implementar todo o plano, revisar e testar. Não autorizou merge, deploy, ativação produtiva, escrita em dados reais, alteração de secrets/auth/billing/infraestrutura. Não tocar outras worktrees nem o checkout principal, que tem mudanças de outras tarefas. Nenhuma regressão conhecida e nenhum gate obrigatório bloqueado pode ser declarado pronto para release. Usar dados sintéticos em ambiente de teste isolado. O Project obrigatório é Autonom.ia Dev, https://github.com/users/autonom-ia/projects/3. O conector retornou 404 durante a abertura da Issue #757; manter Project update pendente com os sete campos até recuperar acesso.

## Decisões funcionais

- Um item Relacionamentos no menu esquerdo, sem os três subitens fixos. Home com três cards objetivos: Contatos, Empresas, Atributos personalizados. Sem métricas fictícias. Cotação, CRM, Conversas, Caixa de Entrada e Configurações continuam independentes.
- Remover somente as entradas soltas de Contatos/Empresas e o acesso a Atributos em Configurações quando a nova navegação estiver habilitada. Preservar URLs, nomes de rotas, deep links, favoritos, pesquisa global, integrações, filtros, importação/exportação e ações. Todos/Ativos/Segmentos/Etiquetas continuam acessíveis dentro da área de Contatos por seletor compacto de visão. Breadcrumb de volta para Relacionamentos sem impor passagem pela home.
- A home e os controles respeitam permissões atuais. Companies indisponível impede novas ações/rotas de Empresa, também no servidor. Conta sem acesso não ganha acesso pela home.
- Global significa por conta, não entre clientes/instalações. Definição e apresentação são compartilhadas; valores permanecem no Contato/Empresa. Ocultar não apaga, não copia e não é restrição de sigilo.
- A lateral REAL de atendimento permanece: cabeçalho Contatos, foto/nome/dados/ações, accordions Ações da conversa, Macros, Informação da conversa, Atributos do contato, Notas e demais existentes. Não criar abas/cartões grandes, alterar largura, mensagens, lista, Resolver, CRM ou compositor. Captura real fornecida às 07:16:57 prevalece sobre mockups inexatos.
- Botão compacto Configurar campos dentro do CONTEÚDO aberto de Atributos do contato, abaixo do título; não aninhar botões dentro do botão do accordion, não fechar a seção ao clicar.

## REL-00 — baseline

Antes das alterações: inventariar contratos e permissões em core e enterprise, registrar SHAs e diferenças locais sem tocar outras tarefas; rodar testes relevantes do baseline, capturar tela real de teste na largura de referência (~1630x930), mobile e viewport menor. Registrar falhas legadas sem escondê-las. Confirmar Node 24 / pnpm 10 / Ruby 3.4.4 / PostgreSQL vector / Redis isolados. Não dispensar specs Ruby por PATH incorreto. Confirmar gatilhos dos dois workflows de produção; feature/release branches não podem disparar produção.

## REL-01 — configuração por conta

Guardar a configuração em Account.settings, separada de valores. Estrutura pequena, versionada, com revisão de concorrência e superfícies explícitas. Preferir IDs de definições da própria conta; chaves permanecem estáveis nos valores. Reutilizar permissões de gestão de atributos (`attribute_manage`) no servidor; habilitação de módulos não pode ser concedida a perfis sem autorização administrativa.

Flags independentes por conta: atributos/apresentação, mídias de Empresa, nova navegação; inicialmente DESLIGADAS. Não criar plataforma genérica nem alterar contratos legados.

Superfícies: `contact_sidebar` (atendimento), `contact_details` (centro da ficha de Contato), `company_details` (centro da ficha de Empresa). Conversas não recebem nova política de apresentação nesta entrega. As abas completas Atributos continuam completas. Atributo de Empresa não é automaticamente exibido na conversa. Não adicionar toggle ambíguo que prometa isso.

Estados obrigatórios:
- Configuração ausente/modo legado: lateral igual ao atual; sem custom fields novos no centro.
- Modo personalizado com IDs vazios: NENHUM campo destacado; nunca voltar a todos por fallback de array vazio.
- Restaurar padrão: ato explícito por superfície.
- Novo atributo após seleção personalizada: só aparece quando escolhido.
- Definição removida: referência ignorada/limpa sem erro de tela.
- Companies desligado: ocultar controles/impedir ações, preservar dados.
- Falha de leitura: não usar dados de outra conta nem confundir erro com inexistência; permitir retry.

Validar shape/tipos/IDs/entidade/recurso na fronteira da API, negar referências cross-account e superfícies desconhecidas. Mesclar só o trecho alterado de settings, não substituir todo o JSON. Dois administradores precisam de revisão otimista/conflito explícito; sem last-write-wins silencioso. A ordenação individual JÁ EXISTENTE continua ordenando somente o conjunto autorizado globalmente; não criar nova preferência individual de visibilidade.

## REL-02 — editor compartilhado/contextual

Uma janela compartilhada em Central de Atributos, ficha Contato e ficha Empresa. Na ficha, contexto fixo da entidade. Ações Configurar campos e Criar atributo; configuração permite pesquisar definições, marcar superfície, editar definição e restaurar padrão. Criar/editar abre o mesmo modal e volta à ficha sem perder contexto.

Campos: Nome, Descrição, entidade, tipo, opções do tipo, locais de exibição, aviso Global nesta conta, Cancelar/Salvar. Descrição é obrigatória em novas definições do novo fluxo, preservando legados. Deve continuar disponível às integrações/IA autorizadas; não criar agente classificador, disparar modelos, OCR ou mudar o comportamento de consumidores de IA.

Reutilizar normalização atual para gerar chave SOMENTE AO CRIAR. Nome/descrição/visibilidade não regeneram a chave. Não transformar job_title em cargo nem apagar valores. Colisão de chave/nome dá orientação, não sobrescrita. Informação técnica somente leitura pode mostrar a chave; não exigir preenchimento manual. Preservar regex/regex cue e opções de listas. Sem tipos novos moeda/percentual. Alteração destrutiva de tipo/modelo/chave não entra no novo editor; manter gestão legada existente sem remoção silenciosa.

Criação/edição de definição e escolha de apresentação devem salvar atomicamente; cancelar não deixa cadastro parcial. Validar revisão da configuração e edição concorrente da definição. Falha mantém rascunho e não anuncia sucesso. Retry não cria duplicata. Refetch/invalidação entre superfícies e troca de conta previsíveis.

Cargo/CEO: testar compatibilidade com fixture job_title e valores existentes; não regularizar conta real nem afirmar que CEO estava salvo sem consulta autorizada.

## REL-03 — fichas e lateral

Adicionar Campos personalizados no centro das fichas antes das seções finais/destrutivas, mantendo dados nativos, botões, redes sociais, etiquetas, mensagens ativas e abas existentes. Campos de Empresa pertencem só à Empresa.

Cada campo tem rótulo, descrição acessível, valor e edição apropriada ao tipo. Salvar por confirmação explícita do campo, separado de Atualizar contato/empresa. Somente anunciar Salvo após confirmação real. Falha mantém rascunho. Enviar alterações parciais para não apagar campos ocultos/outras edições. Troca de contato/empresa/conta ignora respostas antigas. Campos 0/false não são vazios. Datas date-only não podem mudar de dia por fuso. Número vazio não vira zero. Validar lista/link/regex sem executar código.

Na lateral: inserir somente Configurar campos e filtro de definição. Manter layout compacto, descrição, edição, Mostrar mais/menos, drag order e rolagem. Não tocar AccordionItem global. Gestão de definição/layout difere da permissão de atualizar valor do contato. Controles sem permissão não aparecem e API também nega. Abas completas nas fichas continuam funcionando.

## REL-04 — mídias de Empresa

Nova funcionalidade ADITIVA sob Companies; não mudar contrato/consulta/layout de mídias de Contato. Agregar anexos das conversas dos contatos com vínculo REAL company_id atual; nunca company_name textual nem inferência por participante de grupo. Incluir recebidos e enviados preservando ocorrência/origem. Contato relacionado é o contato da conversa; enviado por é autor real (agente/contato etc.). Não confundir.

Vínculo atual: contato reassociado leva histórico permitido à nova empresa, sai da anterior. Não é arquivo corporativo permanente. Não copiar originais, não upload direto, exclusão em massa, envio ao CRM, busca no conteúdo/OCR.

Aba lateral compacta com busca por nome, filtros contato/tipo/período, lista recente thumb+nome+contato e Visualizar tudo. Sem carrossel automático. Ampliada com tabela, agrupamento por contato, paginação e filtro preservado na volta. Ações visualizar, baixar original, abrir contato, ir à mensagem/conversa autorizada. Não espremer tabela larga em sidebar nem inventar Mensagens/etiquetas corporativas.

API adicional com consulta agregada e autorizada antes de contar/serializar. Busca por nome em TODO acervo permitido, inclusive além da primeira página. Filtros combináveis no servidor. Paginação e ordem determinística por data+ID; agrupamento por contato também deve funcionar além da página. Evitar N+1/loop por contato/browser fanout e somente primeira página de anexos. Período por início/fim do dia no fuso da conta (sem assumir fuso pelo nome ou usuário). Não deduplicar por nome/bytes, só remover duplicação de JOIN preservando ocorrências.

Isolamento por conta/empresa/conversa em listagem, contagem, nome, download e preview. Nenhuma contagem/metadata restrita pode vazar. Revalidar autorização ao abrir/obter preview. Sem URLs públicas permanentes novas; URLs de storage, quando necessárias, com validade curta. Cache sem compartilhar dados filtrados entre usuários. Não baixar anexos reais em testes.

## REL-05 — previews

Imagem thumb real; PDF primeira página; vídeo frame de capa, quando representáveis; áudio ícone neutro/duração somente se conhecida; demais ícone e nome. Thumb NÃO substitui nome/busca. Arquivo criptografado/corrompido/grande/codec incompatível => fallback sem quebrar lista/original autorizado.

O baseline Attachment.thumb_url só representa imagens; PDF/vídeo demandam implementação e validação das dependências da imagem runtime. Extensão específica de Empresas, sem alterar thumb_url global desnecessariamente. Usar dependências existentes quando disponíveis. Não transmitir arquivos a provedor externo. Processar sob demanda fora da requisição de página, com limite de tamanho/tempo/concorrência, cache, job idempotente e fila não crítica. Nenhuma conversão em massa no deploy. Limitar subprocessos, não executar conteúdo ativo nem permitir protocolos de rede arbitrários. Derivados são aceitáveis; original único.

## REL-06 — navegação

Home e menu aditivos gated por conta. Preservar Todos/Ativos/Segmentos/Etiquetas mediante seletor local das views existentes. Preservar nomes/URLs antigos em vez de rewrite generalizado. Breadcrumb e active-state corretos. Mobile/menu recolhido/teclado/voltar/avançar/troca de conta. Atributos de Conversa seguem disponíveis na Central. Atualizar Guia/Central/README e registries pelos geradores (`guia:build`, `guia:check`), nunca editar arquivos gerados à mão.

## REL-07 — gates e revisão

Não basta mocks, CI, lint ou health. Executar testes unitários, componentes, integração/API/Ruby e E2E com CONTROLES REAIS + BACKEND ISOLADO. Fluxo mínimo: abrir modal, preencher, salvar, recarregar, verificar definição e valor. Comparar baseline vs extensão off vs on. Testar ao menos duas contas e dois papéis, falhas e concorrência.

Matriz obrigatória:
- NAV-01: home acessível conforme permissões; demais módulos preservados.
- NAV-02: URLs legadas funcionam sem redirect loop.
- NAV-03: Todos/Ativos/Segmentos/Etiquetas mantidos.
- ATT-01: configuração ausente conserva default.
- ATT-02: seleção vazia difere de ausente.
- ATT-03: configuração global afeta apenas a conta correta.
- ATT-04: não gestor não altera definição/layout via API.
- ATT-05: botão real abre modal e grava entidade correta.
- ATT-06: cancelar não cria parcial.
- ATT-07: renomear preserva chave/valores.
- ATT-08: visibilidade não apaga/copia valores.
- ATT-09: zero/false/lista/date-only/link/regex corretos.
- ATT-10: update parcial não apaga outros campos.
- ATT-11: concorrência/troca registro preservam contexto/rascunho.
- ATT-12: ficha e lateral atualizam valores consistentemente.
- ATT-13: descrição preservada no contrato autorizado.
- UI-01: layout/accordions/mensagens/Resolver/CRM/compositor preservados.
- UI-02: Configurar campos não fecha accordion/conversa.
- MED-01: só vínculos e acervo autorizado.
- MED-02: buscar além primeira página.
- MED-03: privado sem vazamento de metadata/thumb/count.
- MED-04: vínculo atual e original preservados ao mover/remover contato.
- MED-05: autor real separado de contato relacionado.
- MED-06: homônimos/arquivos repetidos preservam origens.
- MED-07: preview falha com fallback real.
- MED-08: origem correta e autorizada.
- MED-09: filtros/agrupamento + paginação de servidor.
- COMP-01: Companies off nega novas entradas/operações.
- REG-01: mídias Contato, histórico/notas/vínculos/atributos legados intactos.
- REG-02: CRM/Cotação/automações/pré-chat/campanhas/variáveis preservam contratos.
- ROL-01: flags off restauram experiência sem destruir dados.

Prettier/ESLint/build/guia/central, specs JS e Ruby obrigatórios. Não remover asserções para obter verde nem marcar bloqueios como pass. Usar captura antes/depois desktop ~1630x930, menor e mobile, light/dark/teclado/foco/scroll. Dados da captura real do usuário não devem ir ao repo público. Teste de performance com dados sintéticos, limites definidos antes (página de 25/50 limitada; sem preview síncrono; sem N+1) e medição de queries/latência. Revisão adversarial independente após implementação; corrigir achados antes de ready.

## Publicação futura / rollback

Esta execução para ANTES de merge/deploy. Os dois workflows disparam em main; não tocar nem disparar ambos. Feature flag não impede atualizar infraestrutura/binário em outra stack. Nova aprovação precisa especificar Hub2You/Autonom.ia, SHA e janela. Não reutilizar autorização da PR #756. Pré-release: homologar conjunto, preparar flags off, instruções de piloto e rollback. Não gravar em conta 16 real.

Flags independentes desligam extensão e restauram legado com dados preservados. Rollback da aplicação pelo blue/green anterior, validar web/worker/SSO/filas. Apenas um degrau anterior por stack; não consumir com múltiplos deploys antes de aceite. Git revert não desfaz dados. Schema/índice, se necessário, exigirá justificativa, snapshot e plano específico. Não efetuar alterações de infraestrutura nesta fase.

## Documentação e entrega

Manter implementation-plan.md, attributes-and-visibility.md, company-media.md, qa-acceptance.md, rollout-rollback.md em docs/relationships, trilha em docs/audit, atualizar docs/companies_custom_attributes.md, README, Guia/Central e .env.example apenas se necessário. Nenhum segredo/dado real/prompt de clientes em logs/docs/fixtures.

Trabalho em commits pequenos REL-00..REL-06 e PRs sobre `release/757-relacionamentos`, sem merge na main. Não abrir PR final como ready sem gates completos. Estado real, métricas e limitações documentados. Project: Projeto Hub2You; Status conforme execução; Tipo Feature; Prioridade P2; Risco Médio; Próxima ação concreta; Ambiente Local até efetiva homologação.

## Fora de escopo

Cards CRM/funil/etapa, migração company_name do CRM, redesign atendimento, biblioteca corporativa permanente/upload direto, IA nova/OCR/busca no conteúdo, hierarchy/múltiplas empresas, permissões finas por campo, moeda/percentual, alteração produtiva de infraestrutura sem autorização.
