# Inventário de mudanças de comportamento: Chatwoot v4.18.0 → v4.19.1

Issue autonom-ia2/chat#3119, épico #3118. Etapa 1 do upgrade.

Regra do dono: zero regressão. O upgrade traz o código do upstream, nunca o comportamento novo. Toda mudança de
comportamento em área que usamos é neutralizada por padrão.

Método: leitura de cada commit não-merge de `v4.18.0..v4.19.1` (`git show <sha>`, sem specs e traduções),
cruzada com `git diff --name-only v4.18.0 origin/main` (arquivos que o fork já mexeu). Trabalho só de leitura:
nenhum teste rodou, nenhum dado de produção foi consultado.

Ficaram de fora, como combinado, os dois "Bump version" e o "Update translations" (#16147). Esse último muda
cerca de 200 linhas de pt_BR já existentes (campaign, companies, conversation, automation e outros): veja "Riscos
de merge".

## 1. Resumo

179 commits classificados.

| Classe | Quantos | O que é |
|---|---|---|
| A | 51 | Sem mudança de comportamento: refactor, testes, docs, CI, deps, desempenho, correção de erro que só quebrava |
| B | 81 | Novo ou alterado, mas escondido para nós: flag desligada, só nuvem, ou área sem uso (Captain, Copilot, voz/Twilio, monitores, Stripe, Shopify, SAML, Slack) |
| C | 11 | Segurança que só recusa pedido forjado ou inválido |
| D | 36 | Muda algo que usamos |
| E | 0 | Segurança que muda fluxo legítimo. Os três conhecidos (#16574, #16461, #16525) são da 4.20 |

Os D que mais pesam, em ordem:

1. Campanhas WhatsApp (#15854, #16281, #15409): envio passa a ser em lotes por job, o gate troca de
   `whatsapp_campaign` para `campaigns`, cria `contact_inbox` por destinatário, job novo retoma campanha
   "parada". Bate de frente com o `oneoff_campaign_service` do fork e com o `CampaignJourney::StalledCampaignsJob`.
2. E-mail (#15871, #15746, #16103, #15830): o encadeamento de resposta passa a exigir o mesmo contato, a citação
   do e-mail anterior vai por padrão, o e-mail de continuidade sai em português, tabela markdown vira tabela HTML.
3. Passagem do robô (#15763): todo `bot_handoff` do fork passa a tocar alerta sonoro no painel. E o
   `bot_handoff!` upstream só age em conversa pendente, o oposto do #1377.
4. API de empresas (#16015): o tamanho de página muda de 25 para 50. Os componentes do CRM calculam páginas com 25
   fixo.
5. Tag HUMAN_AGENT no Messenger e no Instagram (#15932): robô fora de 24 h deixa de levar a tag. O fork já tem
   regra própria (`Meta::HumanAgentTag`).
6. `ruby_llm` 2.0 (#15983): o `Autonomia::Agents::EmbeddingService` usa RubyLLM direto.
7. `mobile_voice_push` (#16254): migration liga a flag em todas as contas.

Riscos de merge que não são comportamento upstream, mas quebram se passarem batidos:

- **Flags:** a 4.19.1 declara as 8 flags novas na `feature_flags_ext_1`, nas posições 8 a 15. O fork já ocupa 1 a
  63 dessa coluna. Elas têm de ir para a `ext_2`, posições 51 a 58.
- **Notificação:** o tipo `voice_call_missed: 9` colide com o `crm_followup_reminder: 9` do fork.
- **Empresas:** os arquivos que o fork customizou em `enterprise/` (controller, policy com permissão por função,
  model, views) foram movidos para `app/` pelo upstream (#15963).

## 2. Tabela completa

Ordem: do mais novo para o mais antigo (`git rev-list`).

| sha | PR | área | classe | o que muda |
|---|---|---|---|---|
| bc94917a74 | #16386 | infra | A | Node 24.22.1 em Dockerfile/CI. |
| 98a9ed710a | #16092 | robôs/caixa | D | Caixa não aceita dois provedores de robô (AgentBot, Dialogflow, Captain); vínculo com robô apagado deixa de contar como robô ativo. |
| 26ca43ba6f | #16385 | deps | A | crass 1.0.8. |
| 6a3d1ddef9 | #16374 | anúncios | B | Esconde anúncios nos 3 primeiros dias da conta; anúncios só existem na nuvem. |
| 7fe41fe037 | #15761 | Help Center | B | Evita artigo duplicado; slug ganha validação de formato e sufixo aleatório quando gerado. O Publicador grava slug próprio e compatível. |
| 5e507d4906 | #16105 | testes | A | Só spec. |
| bc51a6dd45 | #16247 | voz/Twilio | C | Recusa webhook de voz Twilio sem assinatura válida (Twilio sem uso). |
| 463bf9ddb8 | #16094 | Captain | B | Cota compartilhada entre chamadas de classificação. |
| e7e6ce2cf2 | #16367 | docs | A | AGENTS.md. |
| 42ef6125f5 | #16358 | voz | B | Avisos de voz gerados por áudio de chat. |
| cf60e459c9 | #16208 | Copilot | B | Copilot propõe mudanças com cartão de aprovação (flag copilot_workflows desligada). |
| 427e97d042 | #16093 | Copilot | B | Base do Copilot workflows; job de recuperação entra no agendador e fica ocioso sem execuções. |
| 12955f13ab | #16266 | Captain/IA | B | Troca modelos GPT-4 por gpt-6-luna e transcrição por gpt-transcribe; migration regrava modelos aposentados. Ver incertos (transcrição nativa). |
| 50ff77d41f | #16329 | voz | B | Horário de atendimento em chamadas de voz. |
| abf371d2c0 | #16350 | páginas públicas | A | Tira csrf_meta_tags do portal, pesquisa e widget; nenhum JS nosso lê o token. |
| a8487abf5c | #16347 | billing nuvem | B | Auto translate nos planos da nuvem. |
| 642205c5c8 | #16240 | SAML | B | URL de metadados do IdP (SAML desligado). |
| fb2a9f4b97 | #16318 | docs | A | Swagger. |
| 9499b69538 | #16281 | campanhas WhatsApp | D | Trava por campanha, cursor gravado e job que retoma campanha parada há 15 min; destinatário sem resultado conhecido é marcado e não reenviado. |
| 39314c979a | #16328 | voz/Twilio | B | Aceita chamada com número oculto; conversa ganha campo anonymous_caller (sempre false para nós). |
| 8006117055 | #16200 | atribuição | B | Texto da tela de políticas de atribuição quando o recurso está desligado. |
| fb8d3de93b | #16334 | billing nuvem | B | Stripe nos planos da nuvem. |
| 5a80844877 | GHSA | segurança (GHSA) | C | Automação e macro só anexam arquivos da própria regra/macro. |
| b69fccf1e6 | #16327 | segurança | C | access_token e pubsub_token do usuário só vão na resposta do próprio usuário. |
| afda727c34 | GHSA | segurança (GHSA) | C | Membros de caixa: recusa user_ids que não são da conta. |
| f0039f2668 | #15594 | portal público | B | Troca de idioma do portal mantém o artigo; nosso portal tem um idioma só. |
| 4fb7c05f95 | #16185 | busca | A | Cai para SQL quando o OpenSearch falha (busca avançada desligada). |
| dac03318c7 | #16304 | deps | A | Remove spring. |
| 7893c1e21f | #16326 | auto translate | B | Tradução automática em templates de e-mail (flag desligada). |
| 9e916a2d7a | #16320 | auto translate | B | Rótulo e brilho da tradução. |
| e952d75558 | #16298 | portal público | A | Esconde linha de autores quando todos foram apagados (antes quebrava). |
| f953bca130 | #16207 | WhatsApp UI | D | Modal de templates guarda o template escolhido ao fechar e reabrir na mesma caixa. |
| 5c2b3f78bd | #16182 | auto-resolver | A | Mínimo e cron configuráveis por ENV; padrões iguais (10 min, a cada 5 min). |
| 7a86dea8d0 | #16319 | Help Center | A | Índice em articles.category_id. |
| 2ffa9bb088 | #16317 | desempenho | A | Evento contact.merged sem tokens; ninguém lia. |
| ab70480485 | #16183 | busca | A | Janela de busca configurável por ENV; padrão segue 90 dias. |
| 96a38ac00d | #16312 | voz/WhatsApp chamadas | D | Mensagem de chamada não dispara saudação/fora do horário; caixa de resposta abre como nota quando a última mensagem é chamada. |
| 00960a09d1 | #15807 | etiquetas | D | Salvar conversa/contato só regrava etiquetas se a lista mudou (fim da perda silenciosa de etiqueta). |
| 081bd68ab2 | #16269 | WhatsApp UI | D | Texto da bolha de mensagem não suportada muda e ganha link para a Meta. |
| 61c9ef44af | #16301 | portal público | A | Logo do portal mantém o idioma atual (portal de um idioma). |
| 6fee46cf65 | #16297 | tradução | B | Escolha entre Captain e Google Translate; migration só toca contas com Google Translate (sem uso). |
| 972567d744 | #16299 | portal público | D | Prévia e busca do portal tiram a sintaxe de tabela do texto. |
| 7ab47e2ca1 | #16276 | auto translate | B | Mostra traduções no painel e widget (flag desligada). |
| d7bb320dd8 | #16292 | auto translate | B | Tradução automática ao enviar (flag desligada). |
| 4e6a4d3ad4 | #16279 | auto translate | B | Flag auto_translate e ajuste de conta. |
| 75cdd57ab4 | #16234 | UI contato | D | Painel de atributos vazio mostra estado vazio com link para criar (admin). |
| 292d8756ef | #16230 | Captain | B | Verificação de e-mail antes de ferramenta sensível. |
| 80bb9e05c4 | #16123 | conversas API | A | Responsável apagado aparece como sem responsável (antes quebrava a renderização). |
| 4009177f7e | #16071 | deps | A | Remove time_diff. |
| fbb90f753c | #15978 | e-mail IMAP | A | Busca IMAP concorrente não grava o mesmo e-mail duas vezes. |
| 96b13cc206 | #16272 | campanhas WhatsApp | D | Histórico de campanha na conversa inclui envios anteriores à primeira resposta (parte do #15854). |
| a0dfab9282 | #16244 | voz | B | Coleta de credenciais Twilio. |
| 128fdb7a07 | #16191 | widget teste | A | Página de teste do widget. |
| 00b13f7873 | #16253 | Stripe | B | Desconecta contas ao desinstalar o app Stripe. |
| 012bb8edb8 | #16226 | Captain | B | E-mail ao admin quando créditos do Captain acabam. |
| 8cd1193046 | #16270 | Super Admin | B | Diagnóstico de por que a chamada não toca o celular. |
| cacfdfdd5e | #16254 | voz/flags | D | mobile_voice_push nasce ligada e migration liga a flag em TODAS as contas; chamada WhatsApp pode tocar o celular do agente. |
| b8f9b13d5a | #16250 | voz/Twilio | C | Restringe download de gravação Twilio autenticado. |
| 40025f4d82 | #16184 | transcrição | B | Renomeia .oga para .ogg antes de transcrever. Ver incertos (transcrição nativa). |
| a9edf19573 | #16229 | Captain | B | Ajustes e e-mail de sessão nas ferramentas. |
| b425c054e0 | #16246 | Captain | B | Não envia texto de chamada de ferramenta como resposta. |
| ab0c81af87 | #16228 | Captain | B | Código de verificação por e-mail. |
| c4e5921fec | #16009 | voz | B | Encerra conferência Twilio. |
| 2afe6b87d4 | #16008 | voz/notificações | B | Tempo de toque e notificação de chamada perdida (novo tipo de notificação 9: colide com o fork, ver Neutralizar). |
| fe73102461 | #16007 | voz/push | B | Toca o celular em chamada recebida; cache de token FCM por processo. |
| 8732dc3ac8 | #16054 | Copilot | B | Histórico do Copilot. |
| 5e0afa9363 | #16078 | Captain/IA | B | Inferência OpenAI pela API Responses. |
| 5974756fe7 | #16126 | e-mail | A | Nome do remetente entre aspas quando tem vírgula etc. (RFC 5322); exibição igual. |
| 10b42fc25f | #16189 | Captain | B | Backfill de criptografia das credenciais de ferramentas. |
| ab72636f84 | #16188 | Captain | B | Criptografa credenciais das ferramentas. |
| e212425e7b | #15603 | Super Admin | B | Página de diagnóstico do usuário; sessão atualiza dados do navegador. |
| 807e9ed67a | #16196 | segurança nuvem | B | E-mails isentos da verificação de dispositivo (só nuvem). |
| f4bc89957b | #16162 | Super Admin | B | Busca de conta e usuário na barra de comandos. |
| e6c21b63de | #15988 | contatos/empresas | D | Formulário de contato troca o texto livre de empresa por seletor de Company; salvar pode criar Company a partir do nome antigo. |
| 07c668ec42 | #16180 | deps | A | axios 1.20.0. |
| cd1d7275a4 | #16086 | deps | A | markdown-it 14.3.1. |
| 9ff0886bf7 | #16160 | deps | A | dompurify 3.4.16. |
| 05a166a0d2 | #16148 | desempenho | A | Widget carrega contexto com menos consultas. |
| 3ad9b99d6b | #16154 | atribuição | A | Job da Atribuição V2 entra na fila depois do commit. |
| f5bbc04844 | #15983 | IA/deps | D | ruby_llm 1.x vira 2.0 e ai-agents 0.13; o EmbeddingService dos Agentes Autonom.ia usa RubyLLM direto. |
| 1c50944e61 | #16174 | UI | A | Texto da bolha em rem (igual no tamanho padrão). |
| b30060d18b | #16171 | Super Admin | A | Botões post_to passam a enviar POST. |
| 05ace44a82 | #16166 | deps | A | Pino temporário do ai-agents. |
| 5f840ea241 | #16119 | e-mail | D | Resposta de e-mail aceita assunto próprio; cabeçalho de e-mail da caixa de resposta ganha campo de assunto. |
| bc60ffc312 | #16056 | Captain/OpenAI | B | Remove sugestão de etiqueta antiga; migration limpa ajuste sem uso. |
| ab0182a9eb | #16102 | UI | A | Enter ignorado durante composição IME. |
| d79c052624 | #16095 | desempenho | A | Limite de atribuição por sorted set no Redis. |
| 5f21903a7b | #16143 | CI | A | Checagem de colisão de versão de migration. |
| f9cbacaa9e | #16131 | desempenho | A | Usuários online sem buscar a conta. |
| 225b2af051 | #15980 | Captain | B | Nova visão geral do Captain como padrão. |
| ccbda8b37f | #16137 | Super Admin | D | Redesenho completo do Super Admin (CSS, layout, navegação, helpers). |
| a296aa9191 | #16144 | empresas | B | Logo no enriquecimento e nota sem autor como Sistema (tela de Empresas escondida). |
| 52a6adedf8 | #16153 | Stripe | B | Log seguro de falha. |
| f1c9e4831b | #15765 | Stripe | B | Dados de cobrança Stripe na conversa (flag desligada). |
| af1e939467 | #16034 | Captain | B | Catálogo de ferramentas. |
| ed7b122d27 | #16141 | Slack | B | Avatares e rótulos no Slack. |
| b0559b0234 | #16140 | Slack | A | Refactor da verificação de assinatura. |
| 1202b5a2da | #16132 | monitores | B | Limites de chamadas dos monitores. |
| 12ce7b73cc | #13550 | Shopify/auth | B | Cadastro de lojista Shopify; caminhos de login só mudam com token Shopify. |
| 351c96a213 | #16015 | empresas API | D | API de empresas muda paginação (25 para 50 empresas, 15 para 25 pessoas, conversas e notas paginadas) e recusa rede social sem http(s). |
| 843385ff3a | #16103 | e-mail | D | E-mail de continuidade da conversa sai traduzido (pt_BR) em vez de inglês fixo. |
| 80086e5afa | #16104 | segurança | C | Criar conversa recusa assignee_id/team_id de fora da conta. |
| 170618b9b6 | #16098 | segurança | C | Atribuição em massa restrita à conta. |
| 480a8ae2e9 | #16084 | Shopify | B | Endurece conexão de loja. |
| 991741ac14 | #16082 | anúncios | B | Anúncios de recurso no painel (só nuvem). |
| 1f1146a8d8 | #16055 | monitores | B | Automação disparada por monitor. |
| 26ddaba230 | #16089 | contatos webhook | D | Payload de contato (webhook e tempo real) ganha contact_type. |
| c29e79ca00 | #16074 | UI conversa | D | Caixa de resposta pode ser recolhida em barra. |
| 66275a535c | #16077 | contatos | D | Contato vira lead ao ser criado pela API, importado ou ao abrir conversa (#16077). |
| 03702d176d | #16020 | e-mail IMAP | A | Ignora Reply-To vazio antes de normalizar remetente. |
| c7d000564e | #15871 | e-mail | D | Encaminhar e-mail; muda o encadeamento de respostas (busca por In-Reply-To passa a ser do mesmo contato), o retry de mensagem e o cast de private. |
| 481c6abf90 | #16079 | Super Admin | B | Log de início e fim de personificação. |
| 07921d55d5 | #16075 | billing nuvem | B | Monitores só em plano Business. |
| 097155a4af | #15961 | voz | B | Cancela perna Twilio. |
| 5d495bb919 | #15992 | Super Admin/segurança | C | Token de personificação gerado no clique e de uso único. |
| 5ac8d71537 | #15976 | Super Admin/auditoria | D | Personificação atribuída ao super admin; login e logout por personificação saem do log de auditoria da conta. |
| d09576cc08 | #16046 | e-mail UI/busca | D | Cabeçalho da conversa de e-mail mostra o assunto; busca de conversa também procura no assunto. |
| a851d63cf2 | #15998 | WhatsApp | D | Volta o botão de pedir dados de contato (antes desligado com available false fixo); campo some do JSON da conversa. |
| 8c80026a79 | #15997 | Captain | B | Instala ferramentas do GitHub. |
| 4ad74f2ab4 | #15996 | Captain | B | Serviço de instalação de manifest. |
| 8cf0b4e04f | #15995 | Captain | B | Cabeçalhos fixos nas ferramentas. |
| d4b54412a8 | #16060 | migration | A | Tira a FK de contact_inbox em campaign_recipients. |
| e2de952fad | #16030 | monitores | B | Modelos de monitor. |
| 178700dc2b | #16032 | Captain/automação | B | Condições Captain em automação (sem regra ativa). |
| ac7ee4cac5 | #16027 | macros UI | D | Barra de ações em massa ganha botão de macro (flag macros ligada). |
| e8cd72889c | #16031 | Captain | B | Rastreio Langfuse. |
| 35b6156333 | #16059 | deps | A | rack-proxy. |
| 0b7a26f449 | #15854 | campanhas WhatsApp | D | Envio em lotes de 100 por job, gate muda de whatsapp_campaign para campaigns, cria contact_inbox por destinatário e mostra histórico de campanha na conversa. |
| b8eb7766f2 | #16029 | CI | A | Notificação GHSA no Slack. |
| 0d17437200 | #16026 | billing nuvem | B | Monitores e classificador nos planos pagos. |
| f9cf455b06 | #15438 | caixa de resposta | D | Trava de resposta vale para qualquer dono IA (não só AgentBot); assumir usa a API de atribuição; auto-atribuição legada pula quando o mesmo save define responsável (#15438). |
| 37164f874e | #16028 | analytics | A | Eventos de sugestão. |
| cf90f4e51d | #16016 | monitores | B | Ícones de monitor. |
| 2cfe79ec1e | #16011 | monitores | B | Modelos comuns. |
| fcadd60492 | #16013 | segurança | B | Ajuste de 2FA obrigatório vai para a tela Segurança. |
| 1161aa651d | #16012 | monitores | B | Drill-down fica aberto ao atualizar. |
| 685abc72d9 | #15845 | Captain | B | Playground em worker. |
| fa57193fe0 | #16014 | automação UI | A | Formulário não quebra ao trocar evento. |
| 2a65bede33 | #15989 | Super Admin | B | Checagem de entrega de e-mail. |
| f052f667c4 | #15966 | monitores | B | Contratos de monitor; JSON da conta ganha reporting_timezone quando definido. |
| 367bfb35ca | #15877 | segurança | B | Ajuste de conta para exigir 2FA (nasce desligado). |
| 650e448d97 | #15985 | Captain | B | Fim do Captain V1. |
| cdfaa255dc | #15963 | empresas | A | Empresas saem do enterprise para o OSS (mesmo comportamento numa instalação enterprise). Risco de merge alto. |
| 0466fe91e5 | #15938 | UI conversa | D | Modo leitura ao abrir conversa anterior do contato (caixa de resposta escondida e barra para voltar). |
| af1969a731 | #15958 | voz/Twilio | B | Credenciais de API key Twilio. |
| 778fc6fa37 | #15965 | segurança | C | Escapa rótulo de menção e sanitiza diff de artigo. |
| e87cea84d2 | #15942 | docs | A | Bearer na documentação. |
| 359c4d4ce7 | #15932 | Messenger/Instagram | D | Tag HUMAN_AGENT só em resposta humana fora da janela de 24 h. |
| 70c69e5781 | #15964 | Captain | B | Sugestão de etiqueta e prioridade (flag captain_classifier desligada). |
| fe6e56372b | #15843 | filtros | D | Filtros de data por created_at/last_activity_at passam a usar o fuso do navegador. |
| 8aa1fafe20 | #15941 | API auth | D | Aceita Authorization: Bearer com token de API; Bearer passa a ter precedência sobre api_access_token. |
| e3b05e4d76 | #15950 | contatos | D | Conversas anteriores do contato ordenadas por última atividade, não por criação. |
| 3e31538510 | #15851 | auditoria | A | Credenciais fora do log de auditoria de canal. |
| 7b3c928bf1 | #15939 | segurança | C | Rack::Attack lê e-mail e mfa_token de corpo JSON. |
| 5cb3650a42 | #15820 | docs | A | .env.example. |
| 0acc3be540 | #15937 | textos | A | Mensagem de erro da verificação de dispositivo. |
| ef2c00a67e | #15830 | e-mail/markdown | D | Markdown com tabela vira tabela HTML em e-mail, widget e portal; editor de e-mail ganha tabela. |
| eec3e6d974 | #15900 | desempenho | A | Cache de config global. |
| b687420abb | #15746 | e-mail | D | Resposta de e-mail inclui a citação do e-mail anterior por padrão (antes era opção). |
| 9ae63601ce | #15701 | Captain | B | Ferramentas por assistente; migrations de backfill. |
| 5f37921810 | #15725 | Captain | B | Drill-down da visão geral. |
| 87b0808bef | #15763 | passagem de robô | D | Passagem do robô gera alerta sonoro e badge no painel; bot_handoff! só age em conversa pendente; payload de atribuição ganha campo assignment. |
| f7f7754511 | #15899 | Shopify | A | Leitura da flag sem efeito colateral. |
| e424b13f59 | #15897 | Super Admin | B | Chave da verificação de dispositivo no Super Admin. |
| 4a72230d59 | #15882 | docs | A | Swagger de times. |
| b96b4b3b8e | #15768 | filtros UI | A | Corrige comparação de tipos no filtro da lista. |
| a6a6f348eb | #15853 | Super Admin | B | Faixa no painel durante personificação. |
| 910f5e2f49 | #15879 | segurança nuvem | B | Verificação de dispositivo no login (só nuvem, desligada). |
| e0d297e5c2 | #15896 | Help Center | B | Editar slug do artigo (tela do Help Center sem uso). |
| 60759db42d | #15894 | analytics | A | Evento do banner de pagamento. |
| ac33331c42 | #15409 | campanhas WhatsApp | D | Criação de campanha WhatsApp em página cheia; API recusa editar campanha já iniciada; disparo ignora campanha com data futura. |
| 48df202e9d | #15874 | Super Admin | B | Mostra quem suspendeu a conta. |
| d96170acb1 | #15852 | billing nuvem | B | Avisos de pagamento na nuvem. |
| 91fe086381 | #14523 | filtros UI | A | Pré-carrega filtro da caixa. |
| 9d46d1dda9 | #15875 | widget | C | Widget não cria contato para robô de busca. |
| be992c33cd | #15856 | docs | A | .env.example. |
| 14c9dfddde | #15878 | UI | A | Corrige ordem de leitura da rota na lista. |
| e81273cc11 | #15841 | Messenger | D | Nome do contato do Messenger vem do campo name do Graph. |
| 4808f8f9c0 | #15832 | relatórios | B | Drill-down de relatório abre conversas no painel. |

## 3. Detalhe de cada D

Não há E na 4.19.1.

Convenção dos campos:

- **Fork mexeu?** diz se algum arquivo do commit aparece em `git diff --name-only v4.18.0 origin/main`.
- **Neutralizar** diz o que fazer no merge.
- **Spec** diz o teste que trava o comportamento atual. Os specs devem nascer na branch de upgrade **antes** do
  merge, verdes no código atual.

### Prioridade alta

#### D1. 0b7a26f449 #15854: campanhas WhatsApp em lotes, gate novo, histórico na conversa

- **O que muda:**
  - **Envio.** Antes, `Whatsapp::OneoffCampaignService#perform` processava o público inteiro numa execução e
    marcava `completed!`. Agora `perform` só enfileira `Campaigns::SendWhatsappBatchJob` (fila `low`). Cada job
    manda 100 contatos (`BATCH_SIZE = 100`, ordem por `contacts.id`) e enfileira o próximo. A campanha só vira
    `completed` no último lote.
  - **Gate.** Antes `whatsapp_campaign` (`campaign.rb:72`, `oneoff_campaign_service.rb:39`,
    `incoming_message_base_service.rb:12`). Agora `campaigns`. No fork, `campaigns` nasce ligada e
    `whatsapp_campaign` desligada: a liberação muda de conta para conta.
  - **Destinatário.** O enterprise cria o `CampaignRecipient` contato a contato (`find_or_create_by!`) e passa a
    gravar `contact_inbox` em cada um (`save_recipient_destination`, `enterprise/.../oneoff_campaign_service.rb:94`).
    Isso **cria** `ContactInbox` para quem nunca conversou na caixa.
  - **Histórico.** Novo histórico de campanha dentro da conversa WhatsApp (`CampaignHistoryController`,
    `useCampaignHistory.js`, `CampaignMessage.vue`): o agente passa a ver bolhas dos envios de campanha.
- **Exemplo.** Antes: campanha de 3.000 contatos sai num job só e fica "Concluída" ao fim. Depois: 30 jobs em
  sequência na fila `low`. A campanha fica em "Processando" enquanto a fila anda, e o fork tem um job que fecha
  campanha parada em processamento.
- **Quem é afetado:** quem dispara campanha WhatsApp, as automações de campanha do fork
  (`Autonomia::Automacao::PassoDeCampanha`, `CampaignJourney`) e os agentes que abrem conversa WhatsApp Cloud.
- **Arquivos:**
  - `app/services/whatsapp/oneoff_campaign_service.rb` (linhas 4, 8, 39)
  - `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb`
  - `app/jobs/campaigns/send_whatsapp_batch_job.rb` (novo)
  - `app/models/campaign.rb:72`
  - `enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb:12`
  - `enterprise/app/controllers/api/v1/accounts/conversations/campaign_history_controller.rb`
  - `MessagesView.vue`, `MessageList.vue`
- **Fork mexeu?** Sim, muito. `oneoff_campaign_service.rb` nas duas árvores (recusa e bloqueio relidos antes de
  cada envio #737/#2733, insert em lote #2686, público por etiqueta #2681). Também `MessagesView.vue`,
  `MessageList.vue`, `featureFlags.js` e `campaigns.routes.js`. O código do fork referencia `:whatsapp_campaign` em
  `passo_de_campanha.rb`, `whatsapp_campaign_creator.rb`, `whatsapp_dispatch_gate.rb` e
  `campaigns/analytics_controller.rb`.
- **Neutralizar:**
  - Manter o `perform` síncrono do fork.
  - Recusar `SendWhatsappBatchJob`/`perform_batch` como caminho de envio. O arquivo pode entrar sem uso.
  - Manter `feature_enabled?(:whatsapp_campaign)` nos três pontos e no `CampaignHistoryController`.
  - Recusar `save_recipient_destination`.
  - Esconder o histórico de campanha na conversa: `useCampaignHistory` com `enabled` falso, ou exigir
    `campaign_analytics`, que nasce desligada.
- **Spec:**
  - campanha WhatsApp com 150 contatos termina `completed` numa execução de `Whatsapp::OneoffCampaignService#perform`;
  - conta com `campaigns` ligada e `whatsapp_campaign` desligada não dispara;
  - nenhum `ContactInbox` novo é criado pelo disparo;
  - contato que recusou no meio do disparo é pulado (spec do fork existente).

#### D2. 9499b69538 #16281: retomada de campanha WhatsApp parada

- **O que muda.** Coluna `campaigns.whatsapp_cursor` e `campaign_recipients.send_attempted_at`. Trava Redis
  `WHATSAPP_CAMPAIGN_LOCK` por campanha. O `Campaigns::RecoverWhatsappCampaignsJob` roda a cada 5 min pelo
  `Enterprise::TriggerScheduledItemsJob` e reenfileira lotes de campanha em `processing` sem atualização há 15 min.
  Destinatário que já existia e segue `queued` ganha `error_message` "Send outcome unknown..." e não é reenviado.
- **Exemplo.** Antes: campanha travada em processamento é fechada pelo `CampaignJourney::StalledCampaignsJob` do
  fork (a cada 30 min). Depois: dois jobs disputam a mesma campanha. O upstream retoma o envio e o fork fecha.
- **Quem é afetado:** campanhas WhatsApp Cloud.
- **Arquivos:**
  - `enterprise/app/jobs/campaigns/recover_whatsapp_campaigns_job.rb`
  - `enterprise/app/jobs/enterprise/trigger_scheduled_items_job.rb:8`
  - `enterprise/app/models/enterprise/campaign.rb` (`before_update :initialize_whatsapp_cursor`)
  - `enterprise/.../oneoff_campaign_service.rb:17`
  - migration `20261016080629`
- **Fork mexeu?** Sim (`oneoff_campaign_service.rb`, `redis_keys.rb`).
- **Neutralizar:**
  - Tirar a linha `Campaigns::RecoverWhatsappCampaignsJob.perform_later` do `trigger_scheduled_items_job`.
  - Recusar o `before_update :initialize_whatsapp_cursor`.
  - Recusar a reescrita de `process_contacts`.
  - A migration pode entrar: só cria colunas vazias.
- **Spec:**
  - `Enterprise::TriggerScheduledItemsJob` não enfileira `Campaigns::RecoverWhatsappCampaignsJob`;
  - pôr a campanha em `processing` não grava `whatsapp_cursor`.

#### D3. ac33331c42 #15409: campanha WhatsApp em página cheia, API recusa editar campanha iniciada

- **O que muda:**
  - **UI.** O diálogo de criar e editar campanha WhatsApp vira página (`campaigns_whatsapp_new`,
    `campaigns_whatsapp_edit`).
  - **API.** `PATCH /campaigns/:id` de campanha one-off que não está `active` responde 422 "The campaign has
    already started" (antes atualizava). `find_by` vira `find_by!` (404).
  - **Disparo.** `Campaign#mark_processing!` ignora campanha com `scheduled_at` no futuro, mesmo que alguém chame
    `trigger!`.
- **Exemplo.** Antes: renomear uma campanha concluída pela API funcionava. Depois: 422.
- **Quem é afetado:** a tela de campanhas e qualquer código que chame `trigger!` antes da hora.
- **Arquivos:**
  - `app/controllers/api/v1/accounts/campaigns_controller.rb:13-20`
  - `app/models/campaign.rb:78`
  - `campaigns.routes.js`
  - `WhatsAppCampaignFormPage.vue`
  - `app/services/whatsapp/template_parameter_converter_service.rb` (aceita botão nil)
- **Fork mexeu?** Sim (`campaigns_controller.rb` com `authorize_send` #1898, `campaign.rb`, rotas e componentes de
  campanha).
- **Neutralizar:**
  - Manter as telas e rotas de campanha do fork.
  - Recusar o bloco `with_lock`/422 no `update`.
  - Recusar `|| scheduled_at > Time.current` no `mark_processing!`, ou provar que nenhum caminho do fork chama
    `trigger!` antes da hora.
  - O `find_by!` pode entrar (404 em vez de erro 500).
- **Spec:**
  - request spec de `PATCH` em campanha one-off `completed` devolve 200;
  - `trigger!` de campanha com `scheduled_at` futuro, se o fork depender disso.

#### D4. c7d000564e #15871: encaminhar e-mail, encadeamento e retry

- **O que muda (fora o botão de encaminhar):**
  - **Encadeamento.** `NewConversationStrategy#find_conversation_by_in_reply_to` buscava em
    `@account.conversations`. Agora busca em `@contact.conversations` (linha 78). O `Imap::ImapMailbox` passa a
    buscar por `in_reply_to` só nas conversas do mesmo contato (linha 64).
  - **Exemplo do encadeamento.** Antes: o cliente responde de outro endereço, ou um colega em cópia responde, com
    `In-Reply-To` da conversa → entra na conversa existente. Depois: abre conversa nova.
  - **Retry.** O `retry` de mensagem com falha deixava `content_attributes = {}`. Agora mantém
    (`messages_controller.rb:80-88`). O `external_error` continua sendo limpo pelo `StatusUpdateService`.
  - **`private`.** `MessageBuilder` faz `cast` do `private` (linha 10). `private: "false"` ou `"0"` em
    form-data/string criava nota privada. Agora cria mensagem pública.
  - **Assunto.** Mensagem encaminhada sai com assunto `Fwd:` e sem `References`. Afeta só o encaminhamento.
- **Quem é afetado:** caixas de e-mail (encadeamento), integrações que mandam `private` como string, e o reenvio
  de mensagem com falha.
- **Arquivos:**
  - `app/services/mailbox/conversation_finder_strategies/{new_conversation,in_reply_to,references}_strategy.rb`
  - `app/mailboxes/imap/imap_mailbox.rb:57-64,80`
  - `app/builders/messages/message_builder.rb:10,52`
  - `app/controllers/api/v1/accounts/conversations/messages_controller.rb:20-25,77-88`
  - `app/mailers/conversation_reply_mailer.rb`
  - `app/models/message.rb` (`forwarded?`, `not_forwarded`, `human_response?`)
- **Fork mexeu?** Sim (`message_builder.rb`, `messages_controller.rb` com caminho MCP, `Message.vue`,
  `ReplyBox.vue`, `Editor.vue`, specs de `imap_mailbox`).
- **Neutralizar:**
  - Manter `@account.conversations` na `NewConversationStrategy` e o `find_by` por `in_reply_to` na caixa inteira
    no IMAP. A exceção `!message.forwarded?` pode ficar, porque só vale para encaminhado.
  - Manter `retry_content_attributes` (zera `content_attributes` exceto pedido de contato WhatsApp).
  - O cast de `private` é correção: decidir com o dono (ver incertos). Por padrão, recusar.
  - Esconder a ação "Encaminhar" do menu de contexto se o fork não quiser o recurso.
- **Spec:**
  - e-mail de remetente B com `In-Reply-To` de conversa do contato A entra na conversa de A (estratégia nova
    conversa e IMAP);
  - `retry` deixa `content_attributes` vazio;
  - `POST messages` com `private: "false"` cria nota privada (comportamento atual).

#### D5. b687420abb #15746: citação do e-mail anterior vai por padrão

- **O que muda.** Antes: a resposta de e-mail só levava a citação se a opção (`quoted reply`, guardada por caixa
  em `ui_settings`) estivesse ligada. Depois: `shouldIncludeQuotedEmail` inclui sempre em canal de e-mail. O agente
  pode remover (com Ctrl+Z para desfazer).
- **Exemplo.** Agente com a opção desligada responde e o cliente recebe a resposta com o e-mail anterior citado
  embaixo.
- **Quem é afetado:** clientes que recebem e-mail das caixas de e-mail.
- **Arquivos:**
  - `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`
  - `QuotedEmailPreview.vue`
  - `helper/quotedEmailHelper.js`
  - `composables/useUISettings.js`
- **Fork mexeu?** Sim (`ReplyBox.vue`, `Editor.vue`, `ReplyBottomPanel.vue`). O fork tem citação própria
  (`ConversaCanal::CitacaoDoEmail`).
- **Neutralizar:** manter o `ReplyBox.vue` do fork. Recusar `shouldIncludeQuotedEmail` e o atalho `$mod+KeyZ`.
  Manter `quotedReplyPreference`.
- **Spec:** spec JS do ReplyBox: canal e-mail com a opção desligada não inclui citação no `content` enviado.

#### D6. 87b0808bef #15763: alerta na passagem do robô e `bot_handoff!` só em pendente

- **O que muda:**
  - **Alerta.** `ActionCableListener#conversation_bot_handoff` (linha 72) passa a transmitir
    `conversation.bot_handoff` aos membros da caixa. O painel (`actionCable.js:46`) espera 2,5 s e toca o alerta
    sonoro, põe badge no favicon e repete a cada 30 s.
  - **Exemplo do alerta.** Antes: robô passa a conversa (#1377, ela fica Aberta no nome do robô) e ninguém ouve
    nada além da notificação do fork. Depois: todos os agentes da caixa ouvem alerta.
  - **`bot_handoff!`.** `Conversation#bot_handoff!` upstream ganha `return false unless pending?`
    (`conversation.rb:187`). O fork tirou o `bot_handoff!` do `conversation.rb` e o reescreveu em
    `ConversationBotHandoff`. No merge, o método upstream volta em conflito e, se ganhar, a passagem não acontece
    em conversa Aberta, que é exatamente o caso do #1377.
  - **Atribuição.** `ASSIGNEE_CHANGED` ganha `assignment: {automatic, assignee_id, assignee_type, updated_at}` no
    payload em tempo real. É aditivo.
- **Quem é afetado:** todo agente das caixas com robô (n8n e espelhos dos Agentes Autonom.ia).
- **Arquivos:**
  - `app/listeners/action_cable_listener.rb:72,140`
  - `app/jobs/action_cable_broadcast_job.rb:31`
  - `app/javascript/dashboard/helper/actionCable.js`
  - `helper/AudioAlerts/DashboardAudioNotificationHelper.js`
  - `app/models/conversation.rb:184-197`
- **Fork mexeu?** Sim (`action_cable_listener.rb`, `actionCable.js`, `conversation.rb` e
  `concerns/conversation_bot_handoff.rb`).
- **Neutralizar:**
  - Manter o `bot_handoff!` do concern do fork e não reintroduzir o do `conversation.rb`.
  - Recusar `def conversation_bot_handoff` no listener e o handler `'conversation.bot_handoff'` no `actionCable.js`.
  - O campo `assignment` pode entrar, porque é aditivo.
- **Spec:**
  - `bot_handoff!` em conversa **open** com robô passa a conversa (spec do #1377, já existente: conferir que roda);
  - `ActionCableListener` não transmite `conversation.bot_handoff`.

#### D7. 351c96a213 #16015: API de empresas muda paginação e validação

- **O que muda:**
  - `GET /companies` e `search`: 25 → 50 por página (`companies_controller.rb:9`).
  - `GET /companies/:id/contacts`: 15 → 25 e aceita `q`.
  - `GET /companies/:id/conversations`: antes as 20 mais recentes; agora paginado, com ordenação de
    `Conversations::SortService` e contadores.
  - `GET /companies/:id/notes`: paginado a 20.
  - `create`/`update` recusam `social_profiles` sem `http(s)://`.
- **Exemplo.** `CrmOpportunityCompanyPicker.vue` e `CrmRelationshipCompanyForm.vue` calculam
  `page * 25 >= total` e `Math.ceil(total / 25)`. Com 50 por página, "Próxima" leva a páginas vazias ou repetidas.
- **Quem é afetado:** CRM (escolher empresa da oportunidade) e Relacionamentos (ficha de empresa:
  `empresaNoServidor.js` usa `listNotes`, `searchContacts`).
- **Arquivos:** `app/controllers/api/v1/accounts/companies_controller.rb` e `companies/{contacts,conversations,notes}_controller.rb`.
- **Fork mexeu?** Sim, nas versões `enterprise/` desses controllers (ver D-merge abaixo) e em `api/companies.js`.
- **Neutralizar:**
  - Manter `RESULTS_PER_PAGE = 25` (empresas) e `15` (pessoas).
  - Manter as conversas como "20 mais recentes por `last_activity_at`" e as notas sem paginação.
  - Recusar `validate_social_profiles`, ou conferir que o fork nunca manda rede sem `https`.
- **Spec:**
  - request spec: `GET /companies/search` devolve no máximo 25;
  - `GET /companies/:id/notes` devolve as 20 mais recentes;
  - `PATCH /companies/:id` com rede social sem esquema é aceito.

#### D8. 359c4d4ce7 #15932: tag HUMAN_AGENT só para humano fora de 24 h

- **O que muda.** Com `ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` / `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` ligados, o
  upstream passa a mandar a tag só se o remetente é `User` e a última mensagem do cliente tem mais de 24 h.
- **Exemplo.** Antes (upstream): robô respondendo depois de 30 h saía com HUMAN_AGENT. Depois: sai sem tag e a
  Meta recusa.
- **Quem é afetado:** robôs e agentes nas caixas Messenger e Instagram.
- **Arquivos:**
  - `app/services/facebook/human_agent_tag_helpers.rb` (novo)
  - `send_on_facebook_service.rb:100`
  - `instagram/send_on_instagram_service.rb:27`
  - `instagram/messenger/send_on_instagram_service.rb:34`
- **Fork mexeu?** Sim. O fork já decide a tag por `Meta::HumanAgentTag.apply?` (#2259) nesses três serviços.
- **Neutralizar:** manter a lógica do fork (`human_agent_tag?` → `Meta::HumanAgentTag`). Recusar o include de
  `Facebook::HumanAgentTagHelpers` e o `&& human_agent_tag_applicable?`.
- **Spec:** os specs do fork em `spec/services/facebook/send_on_facebook_service_spec.rb` e
  `spec/services/instagram/*` já travam. Conferir um caso de robô fora de 24 h.

#### D9. f5bbc04844 #15983: `ruby_llm` 2.0 e `ai-agents` 0.13

- **O que muda.** O Gemfile sai de `ruby_llm >= 1.14.1` + `ruby_llm-schema` para `ruby_llm ~> 2.0.0`, sem o
  schema. O `Autonomia::Agents::EmbeddingService` usa `RubyLLM.context`, `RubyLLM.embed` e as classes
  `RubyLLM::ServerError`, `ServiceUnavailableError`, `OverloadedError` e `RateLimitError`. Também depende dos
  prazos e repetições do RubyLLM (#2850). Qualquer mudança de API ou de padrão na 2.0 quebra ou altera o RAG dos
  Agentes Autonom.ia.
- **Quem é afetado:** os Agentes Autonom.ia (embeddings da base e da pergunta).
- **Arquivos:** `Gemfile`, `Gemfile.lock`, `config/initializers/ai_agents.rb`, serviços do Captain.
- **Fork mexeu?** Sim (`Gemfile`, `Gemfile.lock`). O `app/services/autonomia/agents/embedding_service.rb` é do fork.
- **Neutralizar.** Não dá para recusar a 2.0 sem recusar o código do Captain que depende dela. A ação é validar
  `EmbeddingService` contra a 2.0: nomes de erro, `context`, timeout e `max_retries`. Não verifiquei, porque a gem
  2.0 não está instalada localmente.
- **Spec:** spec do `EmbeddingService` com HTTP stubado (WebMock): devolve vetores, mapeia 5xx para `provedor` e
  429 para `limite_de_taxa`, respeita `prazo:` sem repetir. Rodar na CI com a 2.0.

#### D10. cacfdfdd5e #16254: `mobile_voice_push` ligada em todas as contas

- **O que muda.** A flag `mobile_voice_push` nasce `enabled: true` e `hidden: true`. A migration `20261014152259`
  grava `ACCOUNT_LEVEL_FEATURE_DEFAULTS` e faz `update_all` ligando o bit em **todas** as contas. Com ela, chamada
  recebida, inclusive pelo `Whatsapp::IncomingCallService` via `Voice::InboundCallBuilder.queue_ring` (#16008),
  manda push VoIP para os celulares dos agentes com o app atualizado. O Super Admin passa a esconder a flag e a
  preservá-la ao salvar.
- **Exemplo.** Antes: ligação WhatsApp aparece só no painel. Depois: o celular do agente pode tocar como ligação.
- **Quem é afetado:** agentes de caixas WhatsApp Cloud com chamadas. O uso é mínimo.
- **Arquivos:**
  - `config/features.yml`
  - `db/migrate/20261014152259_enable_mobile_voice_push_for_all_accounts.rb`
  - `app/helpers/super_admin/account_features_helper.rb`
  - `app/controllers/super_admin/accounts_controller.rb`
- **Fork mexeu?** Sim (`features.yml`, `account_features_helper.rb`, `accounts_controller.rb`).
- **Neutralizar:**
  - `mobile_voice_push` com `enabled: false` e coluna `feature_flags_ext_2`.
  - Migration com corpo vazio (manter a versão para não rodar depois).
  - O `hidden` pode ficar.
- **Spec:**
  - nenhuma conta ganha `feature_mobile_voice_push` depois de `db:migrate`;
  - o default em `ACCOUNT_LEVEL_FEATURE_DEFAULTS` é falso.

#### D11. 00960a09d1 #15807: etiqueta só é regravada se a lista mudou

- **O que muda.** O novo `Labelable::Persistence` lembra a lista de etiquetas lida e só deixa o
  acts-as-taggable-on regravar etiqueta ou cache se a lista mudou.
- **Exemplo.** Antes: worker A lê etiquetas `[]`, a automação põe "vip", e o worker A salva outro campo e apaga
  "vip" sem registro. Depois: "vip" fica. É correção de perda silenciosa.
- **Pegadinhas declaradas no próprio código:**
  - instância reaproveitada depois de rollback pode pular edição;
  - `dup` herda a lista lembrada;
  - "ler `label_list` e dar `save!`" já não preenche `cached_label_list`.
- **Quem é afetado:** tudo que grava etiqueta: CRM, campanhas por etiqueta, automações do fork, robôs.
- **Arquivos:**
  - `app/models/concerns/labelable/persistence.rb` (novo)
  - `app/models/concerns/labelable.rb:6`
  - `app/jobs/migration/conversation_batch_cache_label_job.rb`
- **Fork mexeu?** Não nos arquivos. O fork usa etiqueta em muitos serviços.
- **Neutralizar.** Por padrão, recusar o include (`labelable.rb:6`). Recomendo aceitar, porque é correção de
  perda de dado, mas só depois de rodar na CI toda a suíte do fork que mexe com etiqueta e de procurar no fork
  `label_list` lido e salvo sem mudança. Decisão do dono.
- **Spec.** Se recusar, nenhum. Se aceitar: salvar conversa com outro campo depois de outra instância pôr
  etiqueta mantém a etiqueta. E um caso do fork que reaproveita instância depois de rollback, se existir.

#### D12. ef2c00a67e #15830 e 972567d744 #16299: tabela markdown

- **O que muda:**
  - O CommonMarker liga a extensão `:table` no `Messages::MarkdownRendererService#render_html` (e-mail e widget,
    linha 45) e no `ChatwootMarkdownRenderer` (linhas 8, 15, 22: e-mail, mensagens, artigo do portal, texto puro
    do portal).
  - **Exemplo.** Antes: mensagem com `| a | b |\n|---|---|` chegava no e-mail como texto com barras. Depois: chega
    como tabela HTML com borda.
  - O artigo da Central de Ajuda com tabela passa a renderizar tabela.
  - A prévia e a busca do portal tiram a sintaxe de tabela.
  - O editor de e-mail ganha o botão "inserir tabela" (`constants/editor.js`).
- **Quem é afetado:** clientes de e-mail e do widget, leitores do portal público, agentes no editor de e-mail.
- **Arquivos:**
  - `app/services/messages/markdown_renderer_service.rb:45`
  - `lib/chatwoot_markdown_renderer.rb`
  - `lib/base_markdown_renderer.rb`
  - `shared/helpers/MessageFormatter.js`
  - `constants/editor.js`
- **Fork mexeu?** Sim (`markdown_renderer_service.rb` com `pele`/`automatico`, `Editor.vue`, specs).
- **Neutralizar.** Tirar `:table` das quatro chamadas `render_doc`, recusar `table`/`table_cell` no
  `BaseMarkdownRenderer` e recusar `insertTable` no menu de e-mail. Se o dono quiser tabela no portal, liberar só
  `render_article`.
- **Spec:**
  - `MarkdownRendererService.new("| a | b |\n|---|---|\n| 1 | 2 |", 'Channel::Email').render` não contém `<table`;
  - o mesmo em `ChatwootMarkdownRenderer#render_message` e `render_article`.

#### D13. 843385ff3a #16103: e-mail de continuidade traduzido

- **O que muda.** `email_reply`, `reply_with_summary` e `reply_without_summary` trocam texto inglês fixo por
  `I18n.t`.
- **Exemplo.** Antes: "Hi Maria, You have new messages on your conversation", "You", "Bot", "Attachments:",
  "Click here to rate". Depois, em conta pt_BR: "Olá, Maria,", "Você tem novas mensagens em sua conversa.",
  "Você", "Clique em aqui para avaliar a conversa.".
- **Quem é afetado:** clientes que recebem o e-mail de continuidade (widget e API sem e-mail próprio).
- **Arquivos:** `app/views/mailers/conversation_reply_mailer/{email_reply,reply_with_summary,reply_without_summary}.html.erb`
  e `config/locales/*.yml` (`conversations.reply.*`).
- **Fork mexeu?** Não nas views. O fork tem a chave `greeting` em pt_BR noutro contexto.
- **Neutralizar.** Manter as três views da 4.18 com texto fixo. Ou aceitar, decisão do dono: muda o idioma de
  e-mail que cliente recebe.
- **Spec:** mailer spec: `reply_with_summary` em conta `pt_BR` contém "You have new messages on your conversation".

#### D14. f9cf455b06 #15438: trava da caixa de resposta para qualquer dono IA

Na 4.19.1. Já identificado.

- **O que muda:**
  - A trava de resposta, que mostra nota e esconde o envio de template, valia para conversa **pendente** com
    `assignee_type == 'AgentBot'`. Passa a valer para qualquer `assignee_type` diferente de `User`, o que inclui
    `Captain::Assistant`.
  - O botão "assumir" passa a chamar `assignAgent` com `assigneeType: 'User'` e mudar o status só no store local.
    Antes chamava `toggleStatus` (open) e depois atribuía.
  - O `AutoAssignmentHandler#run_legacy_auto_assignment` pula quando o mesmo save define responsável (linha 18).
    Antes: reabrir e atribuir a alguém fora da caixa no mesmo save fazia a auto-atribuição trocar. Depois: mantém.
- **Quem é afetado:** agentes em conversas pendentes com robô. Pelo #1377 as nossas ficam Abertas, então o efeito
  na UI tende a zero. Afeta também a atribuição legada (V1).
- **Arquivos:**
  - `ReplyBox.vue`
  - `ReplyBoxBanner.vue`
  - `helper/agentHelper.js`
  - `app/models/concerns/auto_assignment_handler.rb:18`
- **Fork mexeu?** Sim (`ReplyBox.vue`, `ReplyBoxBanner.vue`, specs). O `auto_assignment_handler.rb` também
  aparece no diff do fork.
- **Neutralizar.** Manter `ReplyBox.vue` e `ReplyBoxBanner.vue` do fork. Recusar a linha 18 do
  `auto_assignment_handler.rb`.
- **Spec:**
  - JS: conversa **aberta** com `assignee_type: 'AgentBot'` deixa a caixa liberada;
  - model: reabrir conversa definindo `assignee_id` de usuário fora da caixa dispara a auto-atribuição V1.

#### D15. 66275a535c #16077: contato vira lead

Na 4.19.1. Já identificado.

- **O que muda.** O contato vira `lead`:
  - quando é criado pela API (`contacts_controller.rb:87`);
  - na importação (`DataImports::Importer`, `DataImport::ContactManager`);
  - quando abre conversa sendo `visitor` (`Conversation#mark_contact_as_lead`, `after_create`);
  - quando ganha `identifier` (`Contacts::SyncAttributes`).
  - No merge de contatos, fica o tipo mais alto.
- **Exemplo.** Contato visitante do widget que abre conversa passa de `visitor` para `lead`.
- **Quem é afetado:** contatos, filtros e relatórios por `contact_type`, CRM.
- **Fork mexeu?** Sim (`contact_merge_action.rb`, `contacts_controller.rb`, `conversation.rb`, `importer.rb`,
  `contact_manager.rb`).
- **Neutralizar.** Recusar o `merge(contact_type: :lead)` no `create`, o `after_create :mark_contact_as_lead`, a
  regra de `identifier` e as mudanças de `contact_type` no import e no merge.
- **Spec:**
  - `POST /contacts` sem dados de contato cria `visitor`;
  - criar conversa para contato `visitor` mantém `visitor`;
  - contato só com `identifier` continua `visitor`.

#### D16. 98a9ed710a #16092: um provedor de robô por caixa

Na 4.19.1. Já identificado.

- **O que muda:**
  - `AgentBotInbox`, `Integrations::Hook` (Dialogflow) e `CaptainInbox` ganham validação: com outro provedor
    ativo na caixa, salvar dá erro "bot_provider_conflict".
  - `external_bot_active?` passa a exigir que o AgentBot exista (`joins(:agent_bot)`). Vínculo de robô apagado
    deixa de deixar a conversa nova em pendente.
- **Exemplo.** Antes: ligar Captain numa caixa com AgentBot salvava. Depois: erro.
- **Quem é afetado:** configuração de robô nas caixas. Na prática só AgentBot é usado.
- **Arquivos:**
  - `app/models/agent_bot_inbox.rb:17,27`
  - `app/models/concerns/inbox_bot_status.rb:9-22`
  - `app/models/integrations/hook.rb`
  - `enterprise/app/models/captain_inbox.rb`
  - `BotConfiguration.vue`
- **Fork mexeu?** Sim (todos menos o `captain_inbox.rb`).
- **Neutralizar.** Recusar as três validações e manter `agent_bot_inbox&.active?` no `external_bot_active?`.
  Ou aceitar a validação, que não afeta quem só usa AgentBot, e recusar só a troca do `external_bot_active?`.
  Decisão do dono.
- **Spec:**
  - `AgentBotInbox` ativo salva numa caixa com hook Dialogflow ativo;
  - conversa nova em caixa com `AgentBotInbox` ativo nasce `pending` (ou o status que o fork define).

### Prioridade média

#### D17. e6c21b63de #15988: seletor de empresa no formulário de contato

- **O que muda.** Com a flag `companies` ligada (o fork liga para todas), o campo "Empresa" dos formulários de
  contato do Chatwoot vira `CompanySelector`, que busca e cria `Company`. Isso vale para `ContactForm.vue` da
  conversa e `ContactsForm.vue` da página de contatos. Ao salvar com `resolve_legacy_company=true`, o backend cria
  ou associa `Company` pelo nome livre antigo (`contacts_controller.rb:97`). Isso grava dado.
- **Exemplo.** Antes: editar o contato e digitar "Padaria X" só gravava o texto. Depois: cria a empresa
  "Padaria X" e liga o contato.
- **Quem é afetado:** agentes que editam contato pela barra da conversa.
- **Arquivos:**
  - `app/controllers/api/v1/accounts/contacts_controller.rb:92-100`
  - `app/services/contacts/company_association_service.rb`
  - `components-next/Companies/CompanySelector.vue`
  - formulários de contato
- **Fork mexeu?** Sim (`contacts_controller.rb`, `ContactsCard.vue`, `ContactDetails.vue`, `ContactsList.vue`,
  `ContactInfo.vue`).
- **Neutralizar.** Recusar o `CompanySelector` nos formulários (manter o texto livre) e o bloco
  `resolve_legacy_company`.
- **Spec:** `PATCH /contacts/:id` com `resolve_legacy_company: true` e `company_name` não cria `Company`.

#### D18. 0466fe91e5 #15938 e c29e79ca00 #16074: modo leitura e caixa recolhível

- **O que muda.**
  - **Modo leitura.** Abrir uma conversa anterior do contato (links "conversa anterior/seguinte") entra em modo
    leitura: a caixa de resposta some e aparece a barra "conversa antiga" com botão para a mais recente.
  - **Caixa recolhível.** A caixa de resposta pode ser recolhida em `CollapsedReplyBar` (atalhos Alt+R/Alt+N).
- **Quem é afetado:** agentes.
- **Arquivos:**
  - `MessagesView.vue`
  - `OlderConversationBar.vue`
  - `CollapsedReplyBar.vue`
  - `ContactConversationLink.vue`
  - `useContactConversationNavigation.js`
  - `ChatList.vue`
  - `ConversationView.vue`
  - `InboxView.vue`
- **Fork mexeu?** Sim (`MessagesView.vue`, `ChatList.vue`, `ConversationView.vue`, `ContactInfo.vue`,
  `ViewAllConversations.vue`).
- **Neutralizar.** Manter `MessagesView.vue` do fork. Recusar `OlderConversationBar`, `isReadingHistory` e
  `CollapsedReplyBar`.
- **Spec:** spec JS do `MessagesView`: navegar para conversa anterior mantém o ReplyBox montado.

#### D19. 5f840ea241 #16119 e d09576cc08 #16046: assunto do e-mail

- **O que muda.**
  - **Campo de assunto.** O cabeçalho de resposta de e-mail (`ReplyEmailHead.vue`) ganha campo de assunto. O
    `MessageBuilder` grava `content_attributes.email.subject` e o mailer usa esse assunto.
  - **Cabeçalho e busca.** O cabeçalho da conversa de e-mail mostra o assunto. A busca de conversas também
    procura no `mail_subject` (`search_service.rb:38`).
- **Exemplo.** Busca por "orçamento" passa a trazer conversas de e-mail cujo assunto tem "orçamento".
- **Quem é afetado:** agentes de e-mail e busca.
- **Fork mexeu?** Sim (`message_builder.rb`, `ReplyBox.vue`, `api/inbox/message.js`, `ConversationHeader.vue`,
  `search_service.rb`).
- **Neutralizar.** Recusar o campo de assunto no `ReplyEmailHead`, a linha do assunto no
  `ConversationHeader.vue` e o `OR ... mail_subject` na busca. O `params[:subject]` do builder pode entrar, porque
  sem o campo ninguém manda.
- **Spec:** busca de conversa pelo assunto de e-mail não encontra conversa sem outro casamento.

#### D20. a851d63cf2 #15998: botão de pedir dados de contato no WhatsApp

- **O que muda.** Na 4.18 o JSON da conversa trazia `contact_info_request: {available: false}` fixo, e o botão
  ficava desligado. A 4.19.1 remove o campo e cria `GET .../contact_info_request`. O botão
  `RequestContactInfoButton` volta a aparecer quando elegível.
- **Quem é afetado:** agentes WhatsApp Cloud e consumidores da API que leem `contact_info_request`.
- **Arquivos:**
  - `contact_info_requests_controller.rb`
  - `whatsapp/contact_info_request_eligibility_service.rb`
  - `_conversation.json.jbuilder`
  - `RequestContactInfoButton.vue`
  - `routes.rb`
- **Fork mexeu?** Sim (o fork mantém `contact_info_request` no partial, `actions.js`, `api/inbox/conversation.js`,
  `routes.rb`).
- **Neutralizar.** Manter o bloco estático no `_conversation.json.jbuilder` e não chamar o `show` no frontend
  (botão escondido).
- **Spec:** o JSON da conversa traz `contact_info_request.available == false`.

#### D21. 96a38ac00d #16312: chamada não dispara resposta automática

- **O que muda.** `MessageTemplates::HookExecutionService` sai cedo para `message.voice_call?` (linha 8): sem
  saudação, sem fora do horário. A caixa de resposta abre em nota quando a última mensagem é chamada.
- **Exemplo.** Ligação WhatsApp fora do horário: antes o cliente recebia a mensagem de ausência; depois não.
- **Quem é afetado:** caixas WhatsApp Cloud com chamadas. O uso é mínimo.
- **Fork mexeu?** Sim (`ReplyBox.vue`).
- **Neutralizar.** Recusar a linha 8 do `hook_execution_service.rb` e o `isVoiceCallConversation` do ReplyBox.
- **Spec:** mensagem `voice_call` recebida fora do horário dispara o template de ausência.

#### D22. 5ac8d71537 #15976: personificação some do log de auditoria

- **O que muda.**
  - Login e logout feitos por personificação do Super Admin não geram mais `sign_in`/`sign_out` no log de
    auditoria da conta (`enterprise/.../sessions_controller.rb:22,27`).
  - O token guarda `impersonated_by`.
  - `generate_sso_link_with_impersonation` passa a exigir o super admin como argumento.
- **Quem é afetado:** administradores que leem o log de auditoria, e o Super Admin customizado.
- **Fork mexeu?** Sim (`redis_keys.rb`). As views do Super Admin do fork podem chamar o método antigo.
- **Neutralizar.** Recusar os dois `unless`. O resto (atribuição ao super admin) pode entrar. Conferir chamadas a
  `generate_sso_link_with_impersonation` no fork.
- **Spec:** login por personificação cria `AuditLog` `sign_in`.

#### D23. 8aa1fafe20 #15941: Bearer com token de API e precedência

- **O que muda.** A API passa a aceitar `Authorization: Bearer <token de API>`. Com `Bearer` e `api_access_token`
  juntos, o Bearer ganha (`access_token_auth_helper.rb:14`).
- **Exemplo.** Antes: requisição com `api_access_token` válido e um `Authorization: Bearer xyz` de outro sistema
  (proxy, nó n8n) autenticava pelo header. Depois: 401.
- **Quem é afetado:** integrações e robôs que mandam os dois headers.
- **Fork mexeu?** Sim (`access_token_auth_helper.rb` com tokens de integração CRM/MCP, `base_controller.rb`,
  `rack_attack.rb`).
- **Neutralizar.** Inverter para `legacy_access_token || bearer_access_token`. Aceitar Bearer quando vier sozinho
  é só acréscimo.
- **Spec:** request com `api_access_token` válido e `Authorization: Bearer lixo` autentica.

#### D24. fe6e56372b #15843: filtro de data no fuso do navegador

- **O que muda.** O frontend manda `timezone` no filtro de data de `created_at`/`last_activity_at`. O
  `FilterService` compara no fuso dado, onde antes comparava a data em UTC. `CustomFiltersController` valida o fuso.
- **Exemplo.** Filtro "criada depois de 20/11": antes cortava em 20/11 00:00 UTC (21h do dia 19 no Brasil);
  depois corta em 20/11 00:00 do Brasil.
- **Quem é afetado:** filtros de conversa e contato, inclusive pastas salvas novas.
- **Fork mexeu?** Sim (`ChatList.vue`, `actions.js`, `getters.js`, `automationHelper.js`, `ContactListHeaderWrapper.vue`
  e os filter services do fork).
- **Neutralizar.** Recusar o `timezone` no `filterQueryGenerator.js` e o caminho `timezone_aware_*` no
  `FilterService` (manter `days_before_filter_query` da 4.18).
- **Spec:** filtro `created_at is_greater_than 2026-11-20` sem `timezone` compara em UTC (spec de
  `Conversations::FilterService`).

#### D25. e3b05e4d76 #15950: ordem das conversas anteriores do contato

- **O que muda.** `GET /contacts/:id/conversations` ordena por `last_activity_at desc`. Antes era `created_at desc`.
- **Quem é afetado:** a lista "conversas anteriores" na barra do contato e quem consome a API.
- **Fork mexeu?** Sim (o fork trocou `permitted_conversations` por `Contacts::ConversasLegiveis`; a linha de ordem
  é a do upstream).
- **Neutralizar:** recusar a linha 10 (manter `created_at: :desc, id: :desc`).
- **Spec:** contato com conversa antiga reaberta hoje: a lista vem na ordem de criação.

### Prioridade baixa: UI e payload

#### D26. 26ddaba230 #16089: contact_type no payload de contato

- **O que muda.** `Contact#webhook_data` e `push_event_data` ganham `contact_type` (`contact.rb:152,172`).
- **Exemplo.** O webhook `contact_updated` do n8n passa a trazer `"contact_type": "lead"`.
- **Quem é afetado:** robôs n8n e integrações que recebem webhook. O campo é aditivo.
- **Fork mexeu?** Sim (`contact.rb`).
- **Neutralizar:** recusar as duas linhas. Aceitar é seguro se nenhum consumidor valida schema fechado.
- **Spec:** o payload de `contact_created` tem exatamente as chaves atuais.

#### D27. e81273cc11 #15841: nome do contato Messenger

- **O que muda.** Usa `result['name']` do Graph antes de `first_name + last_name` (`facebook/message_builder.rb:136`).
- **Exemplo.** Perfil "Maria Clara Souza" com first/last "Maria"/"Souza": antes o contato novo era "Maria Souza";
  depois é "Maria Clara Souza".
- **Quem é afetado:** contatos novos da Página do Facebook.
- **Fork mexeu?** Sim (`message_builder.rb` do Facebook).
- **Neutralizar:** recusar a linha 136.
- **Spec:** perfil com `name` diferente de `first last` gera "first last".

#### D28. ccbda8b37f #16137: redesenho do Super Admin

- **O que muda.** CSS do administrate inteiro, layout, navegação e helpers (`ui_helper`, `features_helper`,
  `account_feature_icons.yml`, `command_bar_helper`). Junto vêm a barra de comandos (#16162) e a página de
  diagnóstico (#15603).
- **Quem é afetado:** quem opera o Super Admin (nós).
- **Fork mexeu?** Sim (`app_configs_controller.rb`, `account_features_helper.rb`, `features.yml` do Super Admin,
  `navigation_helper.rb`, `_woot.scss`, `layouts/super_admin/application.html.erb`, `accounts/show.html.erb` e
  outras views).
- **Neutralizar:** manter estilos e views do Super Admin do fork. Aceitar só os helpers necessários para o código
  novo compilar.
- **Spec:** request spec das telas do Super Admin customizadas pelo fork (200 e os elementos próprios).

#### D29. f953bca130 #16207: template WhatsApp fica selecionado

- **O que muda.** O modal de templates WhatsApp só limpa a seleção ao trocar de caixa. Antes limpava ao fechar.
- **Fork mexeu?** Sim (`WhatsappTemplates/Modal.vue`).
- **Neutralizar:** manter o `Modal.vue` do fork.
- **Spec:** spec JS: fechar e reabrir o modal volta à lista.

#### D30. 081bd68ab2 #16269: texto de mensagem não suportada no WhatsApp

- **O que muda.** A bolha ganha título e link para a página de dispositivos vinculados da Meta.
- **Fork mexeu?** Sim (`Unsupported.vue`).
- **Neutralizar:** manter o `Unsupported.vue` do fork.
- **Spec:** snapshot JS da bolha não suportada WhatsApp.

#### D31. 75cdd57ab4 #16234: atributos vazios na barra do contato

- **O que muda.** Estado vazio com link "criar atributo" para admin.
- **Fork mexeu?** Sim (`ContactPanel.vue`, `CustomAttributes.vue`).
- **Neutralizar:** manter os do fork.
- **Spec:** nenhum além do snapshot do painel.

#### D32. ac7ee4cac5 #16027: macro em massa

- **O que muda.** A barra de ações em massa ganha "Macro" quando a flag `macros` está ligada, e ela está ligada no
  fork.
- **Fork mexeu?** Não nesses arquivos.
- **Neutralizar:** recusar o `BulkMacroActions` no `conversationBulkActions/Index.vue`.
- **Spec:** spec JS: a barra em massa não mostra macro.

#### D33. 96b13cc206 #16272: histórico de campanha antes da primeira resposta

Parte do D1: cai junto se o histórico for escondido.

### D-merge: não é mudança de comportamento upstream, mas vira regressão se o merge for automático

- **M1. Flags na coluna errada.** A 4.19.1 põe 8 flags novas na `feature_flags_ext_1` (posições 8 a 15). No fork,
  essas posições são `relationships_attributes`, `relationships_company_media`, `relationships_navigation` e assim
  por diante, e a coluna já tem 63.
  - Se as entradas forem acrescentadas como estão: 71 na `ext_1` e o boot quebra (`validate_feature_count!`).
  - Se alguém "consertar" mexendo na ordem da `ext_1`: os bits trocam de dono e flags do fork ligam ou desligam
    em todas as contas.
  - **Ação:** acrescentar as 8 no fim da `ext_2` (posições 51 a 58), na ordem do upstream, com
    `column: feature_flags_ext_2`.
- **M2. Tipo de notificação 9.** A 4.19.1 adiciona `voice_call_missed: 9` (`notification.rb:47`). No fork, o 9 é
  `crm_followup_reminder`, e 10 a 14 também estão ocupados. As flags de `NotificationSetting`
  (`email_flags`/`push_flags`) usam o mesmo número.
  - **Ação:** `voice_call_missed: 15`.
  - Conferir `Enterprise::Notification` e `NotificationPreferences.vue`, que filtram pelo nome.
- **M3. Empresas movidas para o OSS** (cdfaa255dc #15963).
  - `enterprise/app/models/company.rb` → `app/models/company.rb`
  - `enterprise/app/controllers/api/v1/accounts/companies_controller.rb` e `companies/contacts_controller.rb` → `app/...`
  - `enterprise/app/policies/company_policy.rb` → `app/policies/company_policy.rb`
  - views `enterprise/app/views/api/v1/...companies...` → `app/views/...`

  O fork mudou esses arquivos:
  - a policy usa `relationship_record_read?`/`write?` e `contact_delete` no lugar de `true`/`administrator?`;
  - o controller ganha `summary`, `with_lock`, exclusão síncrona (200 ou 202) e merge de `additional_attributes`;
  - a busca de pessoas escapa `%` e `_` (#3078);
  - a view de conversas leva `crm_funnels` e `veio_da_ia`;
  - o `_company` expõe só `city`.

  Se o merge pegar a versão nova de `app/` e apagar a de `enterprise/`, somem as permissões por função
  (regressão de segurança) e o resto.
  - **Ação:** portar cada mudança do fork para o caminho novo. Rodar os specs de `spec/enterprise/controllers/api/v1/accounts/companies*`
    movidos para o caminho novo.
- **M4. `generate_sso_link_with_impersonation(impersonated_by)`** muda de assinatura. Chamada antiga nas views do
  Super Admin do fork quebra.
- **M5. `strong_migrations`.** As migrations upstream têm versão abaixo de `StrongMigrations.start_after`, então
  passam em produção. Mas o job "Migrations do lote" zera o `start_after` e vai acusar algumas: `add_index` sem
  `concurrently` em `captain_custom_tools`, `add_reference` em `campaign_recipients` e `remove_index`. Marcar
  `safety_assured` com justificativa (tabelas pequenas ou sem uso) e não reescrever.
- **M6. Traduções.** O "Update translations" (#16147) muda cerca de 200 linhas pt_BR existentes. Em conflito,
  manter o texto do fork.

## 4. Migrations e flags

### Migrations novas (24)

| Migration | Tipo | Efeito nas nossas contas |
|---|---|---|
| 20260907092035_add_assistant_to_captain_custom_tools | estrutura | Coluna e índice novos; troca o índice único de `[account_id, slug]` por `[assistant_id, slug]`. Captain sem uso |
| 20260907092039_backfill_captain_custom_tool_assistants | **grava** | Duplica ferramenta Captain por assistente. Sem ferramentas Captain, não faz nada |
| 20260917000000_add_device_trust_version_to_users | estrutura | `users.device_trust_version` com default 0 |
| 20260922000000_create_conversation_monitors | estrutura | Tabelas de monitores (sem uso) |
| 20260922090000_add_contact_inbox_to_campaign_recipients | estrutura | `campaign_recipients.contact_inbox_id` (a FK foi tirada no #16060) |
| 20260924000000_add_icon_to_conversation_monitors | estrutura | — |
| 20260924100000_add_headers_to_captain_custom_tools | estrutura | — |
| 20260924120000_add_source_metadata_to_captain_custom_tools | estrutura | — |
| 20260925000000_add_monitor_automation_events | estrutura | Colunas em `automation_rules` e tabelas de monitor |
| 20260925000001_add_monitor_index_to_automation_rules | estrutura | Índice concorrente |
| 20260929100000_add_announcement_fields_to_platform_banners | estrutura | `title`, `video_url` |
| 20261006233107_remove_label_suggestion_settings | **grava** | Tira `label_suggestion` de `accounts.settings` e de hooks `openai`. Ajuste sem uso; conta sem a chave não é tocada |
| 20261008055516_add_ring_state_to_calls | estrutura | — |
| 20261008061547_add_ringing_index_to_calls | estrutura | Índice parcial concorrente |
| 20261008090132_backfill_encrypted_captain_custom_tool_credentials | **grava** | Criptografa credenciais de ferramentas Captain. Sem linhas, não faz nada |
| 20261009081158_add_settings_to_captain_custom_tools | estrutura | — |
| 20261009094528_create_copilot_runs | estrutura | — |
| 20261009170254_create_copilot_action_items | estrutura | — |
| 20261013072916_add_metadata_url_to_account_saml_settings | estrutura | — |
| 20261014152259_enable_mobile_voice_push_for_all_accounts | **grava** | Liga `mobile_voice_push` em **todas** as contas e no default de instalação. **Neutralizar** (corpo vazio) |
| 20261015063804_replace_retired_captain_models | **grava** | Troca `CAPTAIN_OPEN_AI_MODEL` que começa com `gpt-4` (só com endpoint OpenAI padrão) e `accounts.settings.captain_models` com modelos aposentados. Faz `account.update!`, com validação e callbacks, só nas contas que têm modelo aposentado. Captain sem uso; ver incertos |
| 20261016080629_add_whatsapp_campaign_recovery | estrutura | `campaigns.whatsapp_cursor`, `campaign_recipients.send_attempted_at` |
| 20261017230231_set_google_translate_as_translation_provider | **grava** | `translation_provider = google_translate` só em conta com hook Google Translate (sem uso) |
| 20261019143116_add_index_to_articles_category_id | estrutura | Índice concorrente |

### Flags

A 4.19.1 cria 8 flags, todas declaradas pelo upstream em `feature_flags_ext_1`. No fork, todas vão para a `ext_2`,
posições 51 a 58 (ver M1):

| Flag | Default upstream | Premium | Posição no fork | Observação |
|---|---|---|---|---|
| captain_classifier | false | não | ext_2 #51 | sugestão de etiqueta e prioridade |
| conversation_monitors | false | sim | ext_2 #52 | monitores |
| campaign_analytics | false | sim | ext_2 #53 | análise de campanha WhatsApp |
| company_enrichment | false | sim | ext_2 #54 | enriquecimento Context.dev |
| stripe_integration | false | não | ext_2 #55 | Stripe |
| mobile_voice_push | **true** (+ `hidden`) | não | ext_2 #56 | **trocar para false**; a migration liga em todas (ver D10) |
| auto_translate | false | sim | ext_2 #57 | tradução automática |
| copilot_workflows | false | sim | ext_2 #58 | Copilot workflows |

Mudanças em flags existentes:

- `companies`: o upstream tira `premium: true`. O fork tem `enabled: true, premium: true`. Tirar o premium só
  amplia; sem efeito para nós. Pode entrar.
- `deprecated: true` em `captain_v1_action_classifier`, `captain_integration_v2` e `whatsapp_campaign`: some das
  listas do Super Admin. No caso de `whatsapp_campaign`, o código upstream deixa de olhar para ela (ver D1).
  Recusar o `deprecated` de `whatsapp_campaign`: o fork ainda a usa para liberar campanhas.
- Novo atributo `hidden` (só `mobile_voice_push`).

## 5. NEUTRALIZAR NO MERGE

| # | Arquivo / trecho | Ação |
|---|---|---|
| 1 | `config/features.yml`: as 8 flags novas | Acrescentar no fim da `ext_2` (51 a 58) com `column: feature_flags_ext_2`; não tocar na ordem da `ext_1` |
| 2 | `config/features.yml`: `mobile_voice_push` | `enabled: false` |
| 3 | `config/features.yml`: `whatsapp_campaign` | Não aceitar `deprecated: true` |
| 4 | `db/migrate/20261014152259_enable_mobile_voice_push_for_all_accounts.rb` | Manter a versão e esvaziar `up` |
| 5 | `app/models/notification.rb:47` `voice_call_missed: 9` | Renumerar para 15 |
| 6 | Arquivos de empresa movidos de `enterprise/` para `app/` (#15963) | Portar a policy, o controller, as views e o model do fork para o caminho novo |
| 7 | `app/models/campaign.rb:72` | Manter `inbox.inbox_type != 'Whatsapp' \|\| account.feature_enabled?(:whatsapp_campaign)` |
| 8 | `app/models/campaign.rb:78` `\|\| scheduled_at > Time.current` | Recusar (ou provar que nenhum caminho do fork chama `trigger!` antes da hora) |
| 9 | `app/services/whatsapp/oneoff_campaign_service.rb` (`perform` → `SendWhatsappBatchJob`, `perform_batch`, `:campaigns`) | Manter o `perform` síncrono e o gate `:whatsapp_campaign` do fork |
| 10 | `enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb` (`process_contacts`, `recipient_for`, `save_recipient_destination`, `perform_batch`) | Manter a versão do fork |
| 11 | `enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb:12` | Manter `:whatsapp_campaign` |
| 12 | `enterprise/app/jobs/enterprise/trigger_scheduled_items_job.rb:8` `Campaigns::RecoverWhatsappCampaignsJob.perform_later` | Remover a linha |
| 13 | `enterprise/app/models/enterprise/campaign.rb` `before_update :initialize_whatsapp_cursor` | Recusar |
| 14 | `CampaignHistoryController#ensure_whatsapp_campaign_enabled!` e `useCampaignHistory.js` | Gate em `whatsapp_campaign` + `campaign_analytics` (desligada) ou `enabled` falso: histórico escondido |
| 15 | `app/controllers/api/v1/accounts/campaigns_controller.rb:13-20` (422 "already started") | Recusar o bloco |
| 16 | Rotas e telas de campanha WhatsApp em página cheia | Manter as do fork |
| 17 | `app/services/mailbox/conversation_finder_strategies/new_conversation_strategy.rb:75-78` | Manter `@account.conversations` |
| 18 | `app/mailboxes/imap/imap_mailbox.rb:64` | Manter busca por `in_reply_to` em `@inbox.conversations` |
| 19 | `app/controllers/api/v1/accounts/conversations/messages_controller.rb:77-88` | Manter `retry_content_attributes` |
| 20 | `app/builders/messages/message_builder.rb:10` (cast de `private`) | Recusar por padrão; decisão do dono |
| 21 | `ReplyBox.vue` (citação por padrão, atalho Ctrl+Z, voz em nota, trava IA) | Manter o ReplyBox do fork |
| 22 | `app/listeners/action_cable_listener.rb:72` `conversation_bot_handoff` e `actionCable.js:46` | Recusar |
| 23 | `app/models/conversation.rb:184-197` `bot_handoff!` upstream | Não reintroduzir; vale o `ConversationBotHandoff` do fork |
| 24 | `app/models/concerns/auto_assignment_handler.rb:18` | Recusar a linha |
| 25 | `app/controllers/api/v1/accounts/companies_controller.rb:9` `RESULTS_PER_PAGE = 50` | Manter 25 |
| 26 | `.../companies/contacts_controller.rb:2` `RESULTS_PER_PAGE = 25` | Manter 15 |
| 27 | `.../companies/conversations_controller.rb` (paginação, `SortService`, contadores) e `notes_controller.rb` (paginação) | Manter as 20 mais recentes, sem paginação |
| 28 | `.../companies_controller.rb:15,87` `validate_social_profiles` | Recusar |
| 29 | `app/services/facebook/send_on_facebook_service.rb:100`, `instagram/send_on_instagram_service.rb:27`, `instagram/messenger/send_on_instagram_service.rb:34` | Manter o `human_agent_tag?` do fork (`Meta::HumanAgentTag`); recusar `Facebook::HumanAgentTagHelpers` |
| 30 | `app/models/concerns/labelable.rb:6` `include Labelable::Persistence` | Recusar por padrão; aceitar só com OK do dono depois da suíte de etiquetas |
| 31 | `app/services/messages/markdown_renderer_service.rb:45`, `lib/chatwoot_markdown_renderer.rb:8,15,22` (`:table`) e `BaseMarkdownRenderer#table/#table_cell` | Tirar `:table`; recusar os métodos de tabela e o `insertTable` do editor |
| 32 | `app/views/mailers/conversation_reply_mailer/{email_reply,reply_with_summary,reply_without_summary}.html.erb` | Manter o texto fixo da 4.18 |
| 33 | `app/controllers/api/v1/accounts/contacts_controller.rb:87` `merge(contact_type: :lead)` | Recusar |
| 34 | `app/models/conversation.rb:140,302` `mark_contact_as_lead` | Recusar |
| 35 | `app/services/contacts/sync_attributes.rb` (regra do `identifier`), `data_import/contact_manager.rb`, `data_imports/importer.rb` (`contact_type`), `contact_merge_action.rb` (`higher_contact_type`) | Recusar |
| 36 | `app/models/agent_bot_inbox.rb:17`, `integrations/hook.rb` (`ensure_exclusive_bot_provider`), `enterprise/app/models/captain_inbox.rb` | Recusar (ou aceitar só as validações, por decisão do dono) |
| 37 | `app/models/concerns/inbox_bot_status.rb:9,22` | Manter `agent_bot_inbox&.active?` |
| 38 | `app/controllers/api/v1/accounts/contacts_controller.rb:96-98` `resolve_legacy_company` e `CompanySelector` nos formulários de contato | Recusar |
| 39 | `MessagesView.vue` / `OlderConversationBar.vue` / `CollapsedReplyBar.vue` | Manter o `MessagesView` do fork, sem modo leitura e sem caixa recolhível |
| 40 | `ReplyEmailHead.vue` (campo assunto), `ConversationHeader.vue` (assunto), `search_service.rb:38` (`OR ... mail_subject`) | Recusar |
| 41 | `_conversation.json.jbuilder` (`contact_info_request` estático) e `RequestContactInfoButton` | Manter o bloco estático; não chamar o `show` |
| 42 | `app/services/message_templates/hook_execution_service.rb:8` `return if message.voice_call?` | Recusar |
| 43 | `enterprise/app/controllers/enterprise/devise_overrides/sessions_controller.rb:22,27` | Recusar os `unless` |
| 44 | `app/controllers/concerns/access_token_auth_helper.rb:14` | Trocar para `legacy_access_token \|\| bearer_access_token` |
| 45 | `filterQueryGenerator.js` (`timezone`) e `app/services/filter_service.rb` (`timezone_aware_filter_operation`) | Recusar; manter `days_before_filter_query` da 4.18 |
| 46 | `app/controllers/api/v1/accounts/contacts/conversations_controller.rb:10` | Manter `order(created_at: :desc, id: :desc)` |
| 47 | `app/models/contact.rb:152,172` `contact_type` no payload | Recusar (ou aceitar, por ser aditivo, por decisão do dono) |
| 48 | `app/builders/messages/facebook/message_builder.rb:136` | Recusar |
| 49 | Views, CSS e helpers do Super Admin (#16137) | Manter os do fork |
| 50 | `WhatsappTemplates/Modal.vue`, `Unsupported.vue`, `CustomAttributes.vue`/`ContactPanel.vue`, `conversationBulkActions/Index.vue` (`BulkMacroActions`) | Manter os do fork |
| 51 | Chamadas a `generate_sso_link_with_impersonation` no fork | Passar o super admin como argumento |
| 52 | Migrations upstream acusadas pelo job "Migrations do lote" | `safety_assured` com justificativa, sem reescrever |

## Incertos

1. **Transcrição de áudio nativa.** Não sei se alguma conta usa `audio_transcriptions` (o
   `Messages::AudioTranscriptionJob` roda para todo anexo de áudio quando `Llm::SpeechToTextService.available_for?`).
   Se usa:
   - #16266 troca o modelo para `gpt-transcribe`, com outra qualidade e outro custo;
   - #16184 conserta `.oga` (nota de voz do WhatsApp) e faz aparecer transcrição onde antes falhava.

   Pedir à Orquestração a contagem de contas com a chave ligada.
2. **`ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT` / `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT`.** Não conferi o valor em
   produção. O D8 só importa se estiverem ligados, mas o fork já tem regra própria e a ação é a mesma.
3. **Flags `whatsapp_campaign` e `campaigns` por conta.** O efeito do D1 depende de quais contas têm cada uma
   ligada. A neutralização proposta não depende disso.
4. **`ruby_llm` 2.0.** Não verifiquei a API: a gem não está instalada. Vale validar na CI antes do merge (D9).
5. **Portal público.** Não sei se a Central de Ajuda é acessada por clientes de fora. Se não for, os itens de
   portal do D12 viram cosméticos.
6. **Cast de `private` (D4).** É correção de bug (`"false"` virava nota). Pode haver integração que dependa do erro
   sem saber. Decisão do dono.
7. **Etiquetas (D11).** Recomendo aceitar, mas só a suíte do fork na CI diz se algum caminho dele lê e salva
   etiqueta sem mudança esperando o cache.
8. **#16092 e #15438 com dados reais.** A leitura indica efeito nulo para quem só usa AgentBot e conversas Abertas.
   Não testei.
9. **Os "já identificados".** Na 4.19.1: #16077, #15438, #16092. Ausentes da faixa (4.20): #16476, #16701,
   #16475, #16574, #16461, #16525 e #16584. O #16701 também não está na faixa: confirmar com o épico se ele era
   esperado aqui.
