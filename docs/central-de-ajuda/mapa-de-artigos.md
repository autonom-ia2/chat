# Mapa dos artigos — Central de Ajuda "Plataforma"

Storyboard da Fase 0: define quais artigos existem, antes de qualquer texto ser escrito.
Nenhum artigo foi redigido — apenas o mapa. Fonte de dados: `docs/central-de-ajuda/estudo/2026-09-08-apuracao.json` (284 assuntos), `docs/central-de-ajuda/cobertura.json`/`.md` (165 telas), `lib/operator_guide/porques.md` (164 fluxos já escritos no Guia da Plataforma), `config/onboarding/trilha.yml` (9 passos) e `app/javascript/dashboard/helper/guideRouteRegistry.js` (rotas válidas para "Me leve até lá").

**Total: 157 artigos em 19 capítulos.** (159 na primeira versão; ajuste de 22/09 no fim deste arquivo.)

## 00 — Comece por aqui (10 artigos)

- **00.01** — Seu primeiro acesso e a tela Primeiros passos. Entender como entrar pela primeira vez e para que serve a tela que guia a conta nova.
- **00.02** — Passo 1 — Seu perfil e seus avisos. Concluir o primeiro passo da trilha: identidade pessoal e notificações.
- **00.03** — Passo 2 — Conectar a chave da OpenAI. Concluir o passo que liga o CRM com IA, os agentes e o Guia da Plataforma.
- **00.04** — Passo 3 — Conectar um canal. Concluir o passo que faz a primeira conversa do cliente chegar ao painel.
- **00.05** — Passo 4 — Responder a primeira conversa. Concluir o passo que confirma que o atendimento está funcionando de ponta a ponta.
- **00.06** — Passo 5 — Montar o primeiro funil ⚠️ revisar. Concluir o passo que organiza o CRM e alimenta a IA do funil.
- **00.07** — Passo 6 — Convidar quem vai atender. Concluir o passo que dá acesso individual a cada pessoa do time.
- **00.08** — Passo 7 — Criar o agente de IA. Concluir o passo que coloca um agente de IA respondendo pelo WhatsApp ou como copiloto.
- **00.09** — Passo 8 — Preparar a primeira campanha. Concluir o passo mais arriscado da trilha: disparar sem derrubar o número.
- **00.10** — Passo 9 — Ajustar a conta ao seu jeito. Concluir o passo final: etiquetas e respostas prontas que organizam a operação.

## 01 — Mapa e vocabulário (7 artigos)

- **01.01** — O mapa do menu lateral: onde fica cada coisa. Dar ao leitor uma visão geral da barra lateral antes de entrar nos detalhes de cada tela.
- **01.02** — Os dois sentidos de 'Agentes' na plataforma. Distinguir Agentes-pessoas (capítulo 04) de Agentes de IA (capítulo 11) na primeira confusão que todo mundo tem.
- **01.03** — Os dois sentidos de 'Caixa de Entrada'. Distinguir 'Caixas de Entrada' (os canais, capítulo 07) de 'Caixa de Entrada' (a central de notificações, capítulo 08).
- **01.04** — Os copilotos da plataforma. Diferenciar o Copiloto do CRM (resumir/sugerir resposta) do 'Copiloto Autonom.ia' da conversa, que é o nome que aparece na tela (conversar com um agente interno).
- **01.05** — O Guia da Plataforma: pedir ajuda sem sair da tela. Apresentar o painel flutuante de ajuda contextual, presente em qualquer tela.
- **01.06** — Buscar tudo: a busca e a paleta de comandos. Usar o ícone de busca (ou tecla '/') e a busca de comandos do teclado para achar qualquer coisa rápido.
- **01.07** — Como usar a Central de Ajuda. Ensinar o leitor a navegar, buscar e encontrar artigos dentro desta própria Central de Ajuda.

## 02 — Configurações pessoais (8 artigos)

- **02.01** — Onde ficam suas configurações pessoais. Abrir o menu do próprio perfil e chegar em Configurações do Perfil sem procurar.
- **02.02** — Sua identidade: nome, nome de exibição e foto. Escolher como você aparece para o cliente e para o time.
- **02.03** — Seu e-mail, sua senha e o login único. Entender os dois jeitos de entrar na plataforma e por que trocar a senha local quase nunca faz efeito.
- **02.04** — Sua assinatura de mensagens. Escrever a assinatura e saber ligá-la ou desligá-la dentro da conversa.
- **02.05** — Como você escreve e como o painel aparece. Ajustar tecla de envio, idioma, tamanho da fonte e tema (claro, escuro ou do sistema).
- **02.06** — Sua disponibilidade e os avisos que você recebe. Escolher o próprio status (Online/Ocupado/Offline) e o que dispara e-mail, som ou notificação no navegador.
- **02.07** — Segurança da conta: sessões ativas e trocar de conta. Ver de onde a conta está aberta, desconectar o que não reconhece e trocar entre contas.
- **02.08** — Referência: token de acesso, atalhos e sair com segurança. Consultar o token pessoal de API, os atalhos de teclado, como sair e os limites de cada campo do perfil.

## 03 — Configurações da conta (4 artigos)

- **03.01** — Ajustar os dados gerais da conta. Ajustar nome da conta, idioma padrão, domínio, resolução automática de conversa e transcrição de áudio.
- **03.02** — Segurança da conta: SAML SSO. Explicar por que a tela Segurança existe e como ela não se confunde com o login único da plataforma.
- **03.03** — Auditoria: quem convidou quem e quem mudou o quê. Usar a Auditoria para rastrear convites e mudanças de papel na conta.
- **03.04** — Trazer contatos de outra ferramenta e acompanhar a importação. Subir uma base de outra ferramenta e acompanhar o que entrou e o que ficou de fora.

## 04 — Agentes (as pessoas do time) e Funções personalizadas (7 artigos)

- **04.01** — 'Agente' aqui é gente: a tela Agentes e como ler a lista. Entender que Configurações → Agentes trata dos usuários humanos e ler cada linha da lista.
- **04.02** — Convidar uma pessoa para o time. Preencher o convite: nome, função, caixas de entrada e (se for o caso) uma caixa WhatsApp API nova.
- **04.03** — O que acontece depois que você convida. Entender o prazo do convite, o link manual, o reconvite e o que o convidado vê ao entrar pela primeira vez.
- **04.04** — Editar, redefinir senha e definir horário (SLA) de um agente. Ajustar nome, papel e disponibilidade de um colega, redefinir a senha dele e montar o horário individual de SLA.
- **04.05** — Remover uma pessoa do time e o que cada papel vê. Remover um agente com segurança e consultar a tabela de referência do que Administrador e Agente enxergam.
- **04.06** — Criar, aplicar e editar uma função personalizada ⚠️ revisar. Montar uma função com o conjunto exato de permissões, aplicar a um agente e saber o que não mexer.
- **04.07** — A regra que mais confunde: papel não dá acesso à caixa. Entender que estar em Agentes não faz a pessoa enxergar conversas — o acesso vem da aba Agentes de cada caixa.

## 05 — Times e Atribuição de agentes (7 artigos)

- **05.01** — O que é um Time e a tela de Times. Entender quando vale criar um time e ler a lista com busca e contador.
- **05.02** — Criar um time. Criar um time do zero: nome, descrição, atribuição automática e as pessoas iniciais.
- **05.03** — Editar um time: detalhes e membros. Corrigir nome e descrição, ligar/desligar atribuição automática e atualizar quem está no time.
- **05.04** — Excluir um time sem perder conversa. Excluir um time com segurança, sabendo o que acontece com as conversas que estavam nele.
- **05.05** — Atribuir e ver conversas por time. Mandar (ou tirar) o time de uma conversa, em lote ou por atalho, e ver a fila do seu time.
- **05.06** — Usar o time em Automação, Macros e Relatórios. Montar regra e macro com o time e acompanhar o desempenho por time nos relatórios e no CRM.
- **05.07** — Escolher como as conversas são distribuídas: atribuição e capacidade. Abrir a tela-hub de Atribuição de Agentes e criar políticas de distribuição e de limite de conversas por pessoa.

## 06 — Integrações e a chave da OpenAI (7 artigos)

- **06.01** — Abrir Integrações e ler um cartão. Entender por que só o administrador vê o menu Integrações, o que cada selo do cartão significa e não confundir Agentes com OpenAI.
- **06.02** — Conectar a chave da OpenAI (CRM Kanban IA) ⚠️ revisar. Preencher o formulário da chave e entender o que acontece ao salvar.
- **06.03** — Tudo que essa chave liga — e o que passa a custar. Entender que uma única credencial alimenta CRM, Agentes de IA, Copiloto, Guia e e-mail, e quem paga por isso.
- **06.04** — Trocar a chave e o diagnóstico 'a IA parou'. Substituir a chave, entender a prioridade entre chave da conta e chave da plataforma, e seguir o roteiro de checagem.
- **06.05** — Webhooks e Painel de Aplicativos. Avisar outro sistema quando algo acontece e embutir uma tela própria dentro da conversa.
- **06.06** — n8n e integrações de terceiros. Automatizar o funil por fora com n8n e reconhecer Dialogflow, Tradutor do Google e Dyte.
- **06.07** — Conectar Slack, Linear, Notion e a loja Shopify. Levar as conversas para o Slack e ligar Linear, Notion e Shopify à conta.

## 07 — Caixas de entrada (todos os canais) e pesquisa de satisfação (11 artigos)

- **07.01** — WhatsApp Oficial ou WhatsApp API: qual caixa criar. Escolher entre os dois cartões de WhatsApp e reunir o que precisa ter em mãos antes de começar.
- **07.02** — Criar a caixa de WhatsApp Oficial: cadastro incorporado ou manual. Conectar o número pela Meta em poucos cliques, ou preencher os cinco campos manuais e concluir o webhook.
- **07.03** — Colocar atendentes e ler as abas da caixa. Escolher quem atende nessa caixa e saber, de bate-pronto, em qual aba está cada ajuste.
- **07.04** — Saúde da conta e aba Configuração. Interpretar os indicadores da Meta e usar os botões de manutenção: sincronizar modelos, trocar a chave, reconectar.
- **07.05** — A janela de 24 horas e o envio de modelos aprovados. Entender por que o campo de resposta trava e reabrir a conversa com um modelo aprovado.
- **07.06** — Horário de funcionamento, saudação e chamadas de voz. Definir dias e horas de atendimento da caixa, ligar a saudação automática e o recurso de chamadas.
- **07.07** — A lista de caixas de entrada já criadas. Ver todas as caixas da conta num só lugar, distinta do assistente de criação e da configuração de uma caixa.
- **07.08** — Criar uma caixa de WhatsApp API (QR Code / WAHA). Conectar o WhatsApp não oficial lendo um QR Code — o canal mais usado desta stack.
- **07.09** — Criar uma caixa de e-mail ou de site (chat ao vivo). Configurar IMAP/SMTP para a caixa de e-mail e instalar o widget do site.
- **07.10** — Criar uma caixa dos outros canais. Conectar Instagram, Facebook, SMS, Telegram, API própria, Line ou TikTok.
- **07.11** — Ligar a pesquisa de satisfação (CSAT) na caixa. Habilitar a pesquisa de CSAT — sem isso, o relatório do capítulo 14 fica vazio para sempre.

## 08 — Conversas (inclui Chamadas) (15 artigos)

- **08.01** — Abrir a tela de Conversas: áreas, cards e layout. Entender as três áreas da tela, ler um card sem abrir a conversa e alternar o layout — inclui iniciar uma conversa do zero.
- **08.02** — Escolher a fila certa: Minhas, Não atribuídas, Todos e Não atendidas. Escolher entre as abas de responsável e a fila de resgate de conversas não atendidas.
- **08.03** — Filtrar, ordenar e ver por canal, time ou etiqueta. Trocar o status exibido, ordenar a fila e sair da visão geral para um canal, time ou etiqueta específicos.
- **08.04** — Menções, Participantes e a Caixa de Entrada (notificações). Achar conversas em que você foi mencionado ou que acompanha, e entender a central de notificações homônima.
- **08.05** — Cabeçalho, resposta e assinatura na conversa. Ler o cabeçalho da conversa aberta, escrever a resposta e controlar se a assinatura entra automaticamente.
- **08.06** — Quando o produto bloqueia a resposta. Reconhecer o bloqueio da janela de 24h e de caixas de API, e saber a saída (modelo ou nota privada).
- **08.07** — Nota privada, @menção e resposta pronta pelo teclado. Registrar um recado interno, chamar um colega com @ e inserir resposta pronta com '/'.
- **08.08** — Anexar arquivo e gravar áudio. Enviar arquivo, imagem ou áudio gravado na hora, respeitando o limite de tamanho do canal.
- **08.09** — Atribuir, assumir da IA, resolver e adiar a conversa. Passar a conversa para a pessoa ou time certo, assumir de um agente de IA, resolver, deixar pendente ou adiar.
- **08.10** — Prioridade, etiquetas, participantes e macro na conversa. Marcar a prioridade, etiquetar, entrar como participante e rodar uma macro na conversa aberta.
- **08.11** — Ações rápidas: botão direito, seleção em massa, filtros avançados e pastas. Agir sem abrir a conversa, selecionar várias de uma vez, montar um filtro avançado e salvá-lo como pasta.
- **08.12** — Buscar contato, conversa ou mensagem. Achar uma conversa antiga pelo número, e-mail, telefone ou trecho de mensagem.
- **08.13** — Usar o Copiloto na conversa. Resumir, sugerir resposta e conversar com um agente interno sem sair do atendimento.
- **08.14** — Referência: limites por canal e atalhos de teclado. Consultar o limite de caracteres de cada canal e os atalhos que aceleram o atendimento.
- **08.15** — Ver o histórico de chamadas e ouvir gravações. Abrir o painel de chamadas de voz recebidas e feitas pelo número oficial, e ouvir as gravações.

## 09 — Contatos e Empresas (10 artigos)

- **09.01** — Onde ficam os contatos e como ler a lista ⚠️ revisar. Diferenciar Todos os Contatos, Ativo, Segmentos e Marcado com, e navegar entre páginas.
- **09.02** — Buscar e filtrar contatos, salvar segmento. Achar um contato específico, montar um filtro com várias condições e salvá-lo como segmento fixo.
- **09.03** — Criar e editar um contato. Cadastrar um contato do zero e depois corrigir dados, trocar ou remover a foto.
- **09.04** — Etiquetas, bloqueio e notas do contato. Etiquetar, bloquear um contato indesejado e registrar notas internas na ficha.
- **09.05** — Histórico de conversas e mídia do contato. Consultar as conversas passadas e encontrar rapidamente uma foto, comprovante ou PDF já enviado.
- **09.06** — Preencher atributos personalizados na ficha do contato. Preencher na ficha os campos próprios da conta e entender os campos sw_ que a IA preenche sozinha. Criar o campo fica no 12.05.
- **09.07** — Ações em massa, importar/exportar CSV e Base Campanha. Selecionar vários contatos de uma vez, importar ou exportar por CSV, e subir uma base de campanha em lotes.
- **09.08** — Mesclar e excluir contatos. Juntar dois cadastros duplicados sabendo qual sobrevive, e excluir um contato de vez.
- **09.09** — Empresas: cadastro, edição e vínculo com contatos. Cadastrar e editar uma empresa, e usar as abas de Atributos, Contatos, Histórico e Notas.
- **09.10** — Referência: todos os campos de um contato. Consultar a lista completa de campos, o que é obrigatório e por quais dá para buscar, filtrar e ordenar.

## 10 — CRM (16 artigos)

- **10.01** — O menu CRM e criar o primeiro funil ⚠️ revisar. Saber qual das seis telas do CRM abrir, criar o funil, a meta mensal, ligar caixas e as automações do estágio.
- **10.02** — Ler o quadro Kanban e criar um card na mão. Interpretar colunas, contadores e selos do card, e registrar uma oportunidade que não nasceu de conversa.
- **10.03** — Mover card, a gaveta e a timeline. Arrastar entre etapas, abrir as cinco abas da gaveta e reconstituir o histórico na timeline.
- **10.04** — Ganhar, perder, reabrir e arquivar. Fechar o card com valor no ganho ou motivo na perda, reabrir quando preciso, e arquivar o que saiu do fluxo.
- **10.05** — Follow-up manual e automático. Agendar um lembrete ou snooze, configurar envio automático e resolver o aviso de follow-up vencido.
- **10.06** — Filtrar o quadro e trabalhar na Visão Lista. Montar a visão que precisa, trocar para a lista, editar direto na célula e salvar visualizações.
- **10.07** — IA do funil: ligar, critérios e extração de campos. Ligar a IA do funil, escrever os critérios de cada etapa e deixar a IA preencher campos personalizados.
- **10.08** — Aceitar a sugestão da IA e o lembrete de retorno. Resolver a sugestão de estágio pendente no card e ligar o callback automático quando o cliente pede retorno.
- **10.09** — Follow-up automático da IA. Configurar toques, intervalos e janela silenciosa, e acompanhar o ciclo no card.
- **10.10** — Handoff da IA: conceito, gatilho, destino e por etapa. Escolher entre 'Direto' e 'Convite', escrever o gatilho, o destino e personalizar por etapa do funil.
- **10.11** — Calendário do CRM e agendar reunião. Navegar no calendário, criar lembrete rápido e agendar reunião pelo card, com convite e link de vídeo.
- **10.12** — Origem do lead e conversões para Meta e Google Ads. Ler o selo de origem do card e ligar o envio de conversões para Meta Ads e Google Ads.
- **10.13** — Dashboard do CRM: KPIs e seções. Ler os números do funil no período certo e usar os blocos para achar gargalo e avaliar a IA.
- **10.14** — Gestão de IA do CRM: quanto está custando. Acompanhar o gasto de IA por período e por recurso, entender a 'Economia automática' e baixar o relatório de uso.
- **10.15** — SLA do CRM: políticas e calendários. Criar a política de tempo de resposta e resolução, e o calendário de atendimento que ela usa para contar o tempo.
- **10.16** — Trabalhar o CRM na conversa e tokens de integração. Criar ou reaproveitar um card sem sair da conversa, e gerar um token para um sistema externo acessar a API do CRM.

## 11 — Agentes de IA e Robôs (12 artigos)

- **11.01** — Onde ficam os agentes de IA e como ler Meus agentes. Abrir o menu Agentes (os agentes de IA) e interpretar um card: nome, estado, canais e botões.
- **11.02** — Decidir externo ou interno, com base ou sem base. Escolher se o agente fala com o cliente ou só ajuda a equipe, se aprende com documentos, e o ponto de partida.
- **11.03** — Enviar a base de conhecimento e a entrevista do Construtor. Subir os materiais iniciais e conduzir a conversa que monta o agente, anexando arquivos e links.
- **11.04** — Ler o parecer de cada material. Interpretar Pronto, Revisar e Falha ao ler, e consultar formatos e limites aceitos.
- **11.05** — Fechar a construção e revisar o agente. Encerrar a entrevista no momento certo e conferir primeira mensagem, perguntas e materiais antes de publicar.
- **11.06** — Publicar um agente externo ou interno. Conectar o agente a uma caixa para atender de verdade, ou ativar como copiloto da equipe.
- **11.07** — O painel do agente: abas e estados. Circular pelas abas do agente, entender Rascunho/Ativo/Pausado e testar sem risco.
- **11.08** — Aba Conhecimento e aba Canais. Manter a base do agente viva depois de publicado, e conectar/desconectar caixas de entrada.
- **11.09** — Aba Desempenho e configurações rápidas. Ler as métricas de 7/30 dias e mudar imagem, atuação, mensagens e tom sem refazer o agente.
- **11.10** — Quando o agente chama um humano e como ajustar a instrução. Configurar a transferência e o limite de confiança, e escolher entre ajustar com IA ou escrever a instrução.
- **11.11** — Pausar, reativar, apagar e usar como copiloto. Tirar o agente do ar, colocá-lo de volta, removê-lo em definitivo, ou usar o interno como copiloto na conversa.
- **11.12** — Robôs (integração por webhook): o terceiro 'agente' da plataforma. Reconhecer os Robôs, ligados em todas as contas, e não confundir com as pessoas do time nem com os agentes de IA.

## 12 — Automação, Macros, Etiquetas, Respostas prontas e Atributos (5 artigos)

- **12.01** — Criar uma regra de Automação do zero. Montar uma regra completa: evento, condições e ações — do zero, não só a condição de time.
- **12.02** — Criar e editar uma Macro. Montar um conjunto de ações prontas (etiquetar, atribuir, resolver, mandar mensagem) para rodar com um clique.
- **12.03** — Criar e organizar Etiquetas. Criar uma etiqueta, escolher a cor, editar e excluir — usada em conversa, contato e relatório.
- **12.04** — Criar e editar Respostas Prontas. Criar, editar e apagar uma resposta pronta. O uso com '/' dentro da conversa fica no 08.07.
- **12.05** — Atributos personalizados: contato e conversa. Criar um campo próprio de contato ou de conversa na mesma tela de Atributos Personalizados.

## 13 — Campanhas (12 artigos)

- **13.01** — Os cinco tipos de campanha: qual usar. Reconhecer e-mail, WhatsApp Oficial, WhatsApp API, Chat ao vivo e SMS, e escolher o certo para o objetivo.
- **13.02** — Criar uma campanha de WhatsApp Oficial. Disparar um modelo aprovado pela Meta para um público por etiquetas, com data e hora marcadas.
- **13.03** — Criar e acompanhar uma campanha de WhatsApp API. Montar e agendar um disparo pelo WhatsApp não oficial, e acompanhar, pausar ou cancelar no meio do envio.
- **13.04** — Importar, confirmar e desfazer uma base de campanha. Subir uma planilha de nome + celular, validar, confirmar em lotes e desfazer quando precisar.
- **13.05** — Adicionar e verificar um domínio de envio de e-mail. Cadastrar o domínio próprio e conferir o DNS (DKIM, SPF, DMARC) até ele verificar.
- **13.06** — Criar a campanha de e-mail e escolher como montar. Abrir a campanha preenchendo remetente e lista, e decidir entre IA, modelo pronto ou começar do zero.
- **13.07** — Criar o e-mail com IA e montar no editor. Escrever um briefing para a IA montar o e-mail, e ajustar blocos, cor e link no editor.
- **13.08** — Placeholders, teste e modelos de e-mail. Personalizar com os dados da planilha, enviar um teste antes de disparar, e usar/salvar modelos.
- **13.09** — Destinatários, envio e gestão da campanha de e-mail. Gerenciar destinatários, enviar ou agendar, e pausar/retomar/duplicar/excluir uma campanha já criada.
- **13.10** — Ler os indicadores em Gestão de campanhas. Entender os sete números do topo (enviados, entregues, abertos, clicados, descadastros, bounces, spam).
- **13.11** — Analisar uma campanha e usar links rastreáveis. Ver a linha do tempo e os cliques por link de uma campanha, e criar link/QR rastreável por vendedor ou loja.
- **13.12** — Ver o resultado de uma campanha de WhatsApp Oficial. Ler entregues x lidas x ignoradas de uma campanha de WhatsApp Oficial já disparada.

## 14 — Relatórios (10 artigos)

- **14.01** — Onde ficam os relatórios e quem consegue abrir. Encontrar o menu Relatórios e entender por que um atendente comum não vê esse menu.
- **14.02** — Visão geral: números ao vivo, status, calor e tabelas. Ler os quatro números em tempo real, o status do time, os mapas de calor e as tabelas por agente e por time.
- **14.03** — Escolher o período e agrupar por dia, semana ou mês. Usar os atalhos de data, agrupar o gráfico e entender a chave 'Horários de funcionamento'.
- **14.04** — Relatório de Conversas: os sete gráficos e a seta de tendência. Navegar os sete blocos do relatório de Conversas e interpretar a comparação com o período anterior.
- **14.05** — Referência: o que cada métrica realmente conta. Consultar a definição de cada métrica para parar de comparar números que medem coisas diferentes.
- **14.06** — Visão Geral de Agentes, Caixa de Entrada e Time. Comparar o time na tabela, abrir o detalhe de um agente, de uma caixa e de um time.
- **14.07** — Visão Geral das Etiquetas. Usar o relatório por etiqueta para medir assunto/motivo de contato, sabendo que a soma nunca bate.
- **14.08** — CSAT: indicadores, filtros e tabela. Ler os três indicadores de satisfação e filtrar as respostas por agente, caixa, time e nota.
- **14.09** — Relatórios do Bot e de SLA. Ler as métricas de robô (Agent Bots) e a taxa de acerto/violações de SLA.
- **14.10** — Baixar, compartilhar e o que fazer com telas vazias. Exportar qualquer relatório em CSV, compartilhar pelo link e distinguir 'sem dado' de erro de verdade.

## 15 — Cotação de seguros (3 artigos)

- **15.01** — Entrar na área de Cotação e ligar a conta da corretora. Abrir a área de Cotação e conectar a conta da corretora para ver o que dá para cotar.
- **15.02** — Criar o agente que cota com o cliente no WhatsApp. Montar o agente de IA especializado em cotação de seguros.
- **15.03** — Como o cliente recebe os valores da cotação. Entender a jornada completa no WhatsApp: comparativo em PDF, recusa de seguradora e o que o cliente vê.

## 16 — Prospecção (4 artigos)

- **16.01** — Montar e rodar uma busca de leads. Configurar termo, localização, área e limite, e executar a primeira busca.
- **16.02** — Trabalhar os resultados: enriquecer, contato, card, CSV. Transformar um resultado de busca em contato, card do CRM ou planilha.
- **16.03** — Listas de leads e público de campanha. Organizar leads em listas e gerar um público etiquetado para usar numa campanha existente.
- **16.04** — Configurações da Prospecção. Consultar o que precisa estar configurado para a Prospecção funcionar: chaves do Google, enriquecimento e score.

## 17 — Financeiro (2 artigos)

- **17.01** — Ver o plano contratado e quanto está sendo cobrado. Abrir a tela de Assinatura e entender o plano e o valor cobrado.
- **17.02** — Conferir faturas emitidas e o que já foi pago. Abrir a tela de Faturas e conferir o histórico de cobrança.

## 18 — Entenda os conceitos (7 artigos)

- **18.01** — A janela de 24 horas do WhatsApp. Explicar por que existe a janela de 24 horas e o que ela trava no atendimento e nas campanhas.
- **18.02** — Disparo em massa e o risco de bloqueio do número. Explicar por que disparar fora da janela de 24 horas ou em volume alto pode derrubar o número do WhatsApp.
- **18.03** — O que custa quando a IA responde. Explicar quem paga, por qual modelo, e o que dispara consumo sem ninguém clicar em nada.
- **18.04** — API oficial x API não oficial do WhatsApp: o que muda de verdade. Explicar a diferença entre WhatsApp Oficial (Cloud API da Meta) e WhatsApp API (WAHA/QR Code).
- **18.05** — A descrição da etapa é instrução para a IA, não só um rótulo. Explicar que o texto de cada etapa do funil é lido pela IA para decidir quando mover um card.
- **18.06** — Não use o agente de IA no número pessoal. Explicar por que o agente de IA precisa de um número separado do WhatsApp pessoal de quem atende.
- **18.07** — Login único (SSO) e por que a senha local quase nunca vale. Explicar que a entrada na plataforma é pelo login único, com redirecionamento automático, e onde a senha local ainda funciona.

## Fora da Central

51 telas ficam de fora, com justificativa (Captain desligado, a Cobrança nativa, que só existe em instalação CLOUD, telas de sistema, redirecionamentos puros, rotas-casca de agrupamento, variantes técnicas da mesma tela, e o editor de Portais da Central de Ajuda — decisão de produto desta tarefa).

- `account_suspended`
  — Tela de sistema (conta suspensa) — não é jornada de produto. Já listada como fora no Guia da Plataforma (lib/operator_guide/porques.md, bloco _fora_do_guia).

- `no_accounts`
  — Tela de sistema (usuário sem conta vinculada) — não é jornada de produto. Já listada como fora no Guia (porques.md).

- `labels_wrapper`
  — Redirecionamento puro (settings/labels/labels.routes.js), sem componente próprio; sempre encaminha para labels_list. Já listada como fora no Guia.

- `settings_home`
  — Redirecionamento puro (settings/settings.routes.js) — decide a primeira tela de Configurações conforme papel/permissão do usuário, sem UI própria.

- `profile_settings`
  — Rota-casca de layout (component: SettingsWrapper, settings/profile/profile.routes.js) sem path próprio; o conteúdo real está em profile_settings_index e profile_settings_mfa.

- `agent_reports`
  — Rota-casca de agrupamento (settings/reports/reports.routes.js) sem path/componente próprio; o conteúdo real está em agent_reports_index e agent_reports_show.

- `inbox_reports`
  — Rota-casca de agrupamento sem path/componente próprio; o conteúdo real está em inbox_reports_index e inbox_reports_show.

- `label_reports`
  — Rota-casca de agrupamento sem path/componente próprio; o conteúdo real está em label_reports_index e label_reports_show.

- `team_reports`
  — Rota-casca de agrupamento sem path/componente próprio; o conteúdo real está em team_reports_index e team_reports_show.

- `campaigns_one_off_index`
  — Redirecionamento puro (campaigns.routes.js), sem componente — sempre encaminha para campaigns_sms_index.

- `campaigns_ongoing_index`
  — Redirecionamento puro (campaigns.routes.js), sem componente — sempre encaminha para campaigns_livechat_index.

- `autonomia_prospecting_settings`
  — Redirecionamento puro (autonomia.routes.js), sem componente — sempre encaminha para settings_prospecting_index (mesma tela).

- `autonomia_insurance`
  — Redirecionamento puro (autonomia.routes.js), sem componente — sempre encaminha para autonomia_insurance_connections (mesma tela).

- `contacts_edit_label`
  — Mesma tela de contacts_edit (componente ContactManageView); variante de rota alcançada a partir de Contatos > Etiquetas, sem UI própria.

- `contacts_edit_segment`
  — Mesma tela de contacts_edit (componente ContactManageView); variante de rota alcançada a partir de Contatos > Segmentos, sem UI própria.

- `conversation_through_inbox`
  — Mesma tela de inbox_conversation (componente ConversationView com uma conversa aberta); variante de rota alcançada a partir de uma caixa específica, sem UI própria.

- `conversation_through_mentions`
  — Mesma tela de inbox_conversation; variante de rota alcançada a partir de Menções, sem UI própria.

- `conversation_through_participating`
  — Mesma tela de inbox_conversation; variante de rota alcançada a partir de Participantes, sem UI própria.

- `conversation_through_unattended`
  — Mesma tela de inbox_conversation; variante de rota alcançada a partir de Não atendidas, sem UI própria.

- `conversations_through_folders`
  — Mesma tela de inbox_conversation; variante de rota alcançada a partir de uma Pasta salva, sem UI própria.

- `conversations_through_label`
  — Mesma tela de inbox_conversation; variante de rota alcançada a partir de uma Etiqueta, sem UI própria.

- `conversations_through_team`
  — Mesma tela de inbox_conversation; variante de rota alcançada a partir de um Time, sem UI própria.

- `captain_assistants_create_index`, `captain_assistants_documents_index`, `captain_assistants_faq_suggestions`, `captain_assistants_guardrails_index`, `captain_assistants_guidelines_index`, `captain_assistants_inboxes_index`, `captain_assistants_index`, `captain_assistants_overview_index`, `captain_assistants_playground_index`, `captain_assistants_responses_index`, `captain_assistants_scenarios_index`, `captain_assistants_settings_audience_index`, `captain_assistants_settings_index`, `captain_assistants_settings_schedule_index`, `captain_assistants_settings_system_index`, `captain_settings_index`, `captain_tools_index`
  — Recurso nativo do Chatwoot ("Captain"), desligado por padrão nesta instalação (config/features.yml: captain_integration=false, captain_integration_v2=false). O Guia da Plataforma já marca as rotas captain_ como "recurso que esta instalação não usa" (lib/operator_guide/porques.md:1646). O Chat2You tem sistema próprio de Agentes de IA (capítulo 11) que cobre esse espaço — incluir Captain confundiria o usuário com dois produtos de IA conversacional.

- `billing_settings_index`
  — Tela 'Cobrança' nativa: só aparece em instalação CLOUD (`billing.routes.js:26`). As duas stacks não são CLOUD (`ChatwootApp.chatwoot_cloud?` = false, conferido em produção em 22/09/2026): o cliente nunca a vê.

- `portals_index`, `portals_new`, `portals_settings_index`, `portals_locales_index`, `portals_categories_index`, `portals_articles_index`, `portals_articles_new`, `portals_articles_edit`, `portals_categories_articles_index`, `portals_categories_articles_new`, `portals_categories_articles_edit`
  — Decisão de produto (instrução da tarefa): o editor de portais da Central de Ajuda sai do escopo — a Central é nossa, só leitura para o cliente final. cobertura.json classificava esta rota como 'lacuna' (conteúdo faltando), mas a decisão tomada foi não criar capítulo de Central de Ajuda/Portais; criamos apenas 1 artigo 'Como usar a Central de Ajuda' no capítulo 01.

## Prova de cobertura

| Item | Total | Cobertos | Pendentes |
|---|---|---|---|
| Assuntos do estudo (284, exceto obsoletos que ainda fazem sentido — esses entraram com `revisar: true`) | 284 | 284 | 0 |
| Telas cobertas ou em lacuna (`cobertura.json`) que precisam de artigo | 126 | 115 usadas diretamente + 11 reclassificadas para 'fora' (Portais, decisão de produto) | 0 |
| Funcionalidades sem tela própria (`cobertura.json` → `funcionalidades_sem_tela`) | 11 | 11 | 0 |

**Todos os 284 assuntos do estudo aparecem em pelo menos um artigo.** Os 4 assuntos marcados `obsoletos` no estudo (02.16, 07.3, 08.4, 04.7) ainda fazem sentido com o comportamento novo e entraram normalmente, com `revisar: true` no artigo e nota explicando o que mudou.

**Todas as 165 telas do roteador estão contempladas**: as 82 `coberta` e as 44 `lacuna` aparecem em pelo menos um artigo (via `rotas`), as 39 `fora` do próprio `cobertura.json` seguem fora, e as 11 telas de Portais (`portals_*`), que `cobertura.json` marcava como `lacuna`, foram deliberadamente movidas para `fora` nesta Fase 0 por decisão de produto: o editor de portais sai do escopo, a Central é nossa e só de leitura, e o único artigo sobre o tema é '01.07 — Como usar a Central de Ajuda'.

### Funcionalidades sem tela própria — onde cada uma foi coberta
- **Menu do perfil na barra lateral (status Online/Ocupado/Offline, tema claro/escuro, atalhos de teclado, encerrar sessão, marcar offline automático)**
- **Guia da Plataforma (painel flutuante de ajuda contextual da Autonom.ia, presente em qualquer tela)**
- **Handoff automático da IA para humano na conversa (o agente de IA chama alguém e o comportamento visível no atendimento)**
- **Jornada de cotação de seguros no WhatsApp (o agente de IA cotando com o cliente, comparativo em PDF, recusa de seguradora)**
- **Notificações por e-mail e push: o que cada evento realmente dispara (além da tela de preferências)**
- **Automações (Configurações → Automação): criar uma regra do zero**
- **Convite e ciclo de vida do agente (papel de pessoa, não de robô)**
- **Primeiros passos / onboarding da conta (primeiro acesso, tela 'Seus detalhes', tela Primeiros Passos como porta de entrada)**
- **Busca de comandos / paleta de comandos (Cmd/Ctrl+K, atalho de teclado em qualquer tela)**
- **Trocar de conta / criar nova conta (seletor de contas no topo da barra lateral)**
- **Iniciar uma conversa do zero (botão de compor, ao lado da busca)**

Todas as 11 estão cobertas: o menu do perfil e o convite de agente já tinham assunto no estudo (capítulos 02 e 04); Guia da Plataforma, busca de comandos e Como usar a Central ficam no capítulo 01; Primeiros passos abre o capítulo 00; trocar de conta fica no capítulo 02; iniciar conversa do zero abre o capítulo 08; Automações do zero e Cotação de seguros ganharam artigo e capítulo próprios (12 e 15); Handoff automático já estava coberto nos capítulos 08, 10 e 11.

## Conferência feita depois do mapa (22/09/2026)

Conferido por script, contra o código (`guideRouteRegistry.js`, `guideHighlightRegistry.js` e o roteador):

- **159 artigos**, ids únicos; **126/126 telas** a cobrir e **284/284 assuntos** do estudo em algum artigo; nenhuma rota inválida; nada de Captain.
- **Botão "Me leve até lá":** o mapa original deixava 84 artigos sem botão, porque só punha o botão no primeiro artigo de cada tela. Corrigido: **144 de 159** artigos passaram a ter botão (hoje **142 de 157**, depois do ajuste abaixo). Quando a tela é de UM registro (um contato, um agente, uma campanha, uma conversa), o botão leva à lista de onde ele se escolhe. Os 15 sem botão são vocabulário (01), conceitos (18), a referência de métricas (14.05) e 08.11.
- **Destaques:** 8 dos 9 destaques propostos não existiam no código (`sidebar-*`, `integration-crm-kanban-ai`) e foram removidos. Destaque só vale se estiver em `guideHighlightRegistry.js`.
- **Captain:** fora da Central por decisão do Rodrigo; desligado nas 21 contas das duas stacks (conferido em produção).
- **Editor de portais (`portals_*`):** fora; a Central é só leitura. Entra um artigo "Como usar a Central de Ajuda" no capítulo 01.

## Ajuste de 22/09/2026, antes da aprovação

Conferido contra o código e contra produção (só leitura, as duas stacks):

- **17.03 saiu.** A tela Cobrança nativa só existe em instalação CLOUD, e nenhuma das stacks é.
- **06.05 fundiu no 10.14.** Gestão de IA é uma tela só, e ela fica no menu CRM
  (`Sidebar.vue:953-955`). O capítulo 06 foi renumerado (06.06-06.08 viraram 06.05-06.07).
- **09.06 x 12.05:** criar o campo fica no 12.05; o 09.06 ficou só com preencher na ficha e os
  campos `sw_`.
- **02.07:** a verificação em duas etapas **está ligada** nas duas stacks
  (`Chatwoot.mfa_enabled?` = true). O mapa dizia "hoje indisponível".
- **Marca fora do texto:** 02.03, 03.02, 11.01, 11.12 e 18.07 falavam em Chat2You, Autonom.ia ou
  Chatwoot. O 01.04 cita "Copiloto Autonom.ia" entre aspas porque é o rótulo que aparece na tela.
- **Referências erradas:** 12.04 citava um "06.14" que não existe; a nota do Captain dizia
  "capítulo 09" para os agentes de IA, que são o 11.
- **Total:** 157 artigos, 142 com botão, 51 telas fora.
- **Campo `requer` (decisão do Rodrigo):** cada artigo do `.json` diz o recurso de que depende,
  tirado do portão da tela do botão. 88 artigos dependem de um recurso; 69 valem para todos. A
  tela de leitura e o Guia escondem o artigo das contas que não têm o recurso.
- **Botões corrigidos no ensaio do capítulo 05:** 04.07, 07.04, 07.06 e 07.11 apontavam para
  `settings_home`, que é só redirecionamento e está fora da Central; agora levam à lista de
  caixas de entrada (`settings_inbox_list`). O 05.03 leva à lista de times.
