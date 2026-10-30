# Funções personalizadas: modelo de permissões

**Data:** 17/10/2026 · **Versão:** 4, revisada pelos 8 chats donos de módulo · **Base:** `origin/main` em `21d16067fc` · **Estado:** proposta para decisão. A regra das duas listas ("só o dono" e "delegável com proteção") já foi aprovada pelo Rodrigo em 17/10 e está no PR #1783. Nada foi mudado no código.

Fontes: inventário de rotas e policies (OSS e `enterprise/`), Issues #452, #722, #879, #888, #894, #1136, #1140, #1148, #1157, #1158, #1585, #1652, o diagnóstico local `docs/funcoes-personalizadas/DIAGNOSTICO-2026-10-17.md` e as decisões do Rodrigo de 17/10 (exercício da empresa estruturada, que depois ele esclareceu ser só um exemplo: o modelo vale para empresa de qualquer porte).

As brechas aparecem aqui só como fato. Por decisão do Rodrigo, elas não são corrigidas agora: entram no épico.

**Convenção:** **[NOVO]** = não existe no código, é proposta. **[HIPÓTESE]** = deduzido, ainda não conferido. O resto foi visto no código.

## Decisões de 20/10/2026 (versão 5)

- **Não existe "dono da conta".** O administrador é o topo da conta e é quem monta a estrutura com funções. Onde este documento diz "dono da conta" ou "só o dono", leia "administrador". A dúvida Z2 e a seção 5.5 ficam resolvidas assim (Issue #1915, fechada sem código).
- **Regra 2 com ajuste fino.** Por padrão, ninguém entrega mais do que tem. O administrador pode ligar numa função o ajuste "Pode entregar acesso acima do próprio": quem tem essa função entrega qualquer função da conta, inclusive com áreas delegáveis (financeiro, tokens, segurança, pessoas). Exemplo: o RH contrata o diretor comercial e cria o acesso dele, maior que o do RH. Nem com o ajuste alguém promove a administrador, e a regra 3 continua valendo.
- **A proteção do ajuste é o histórico.** Toda entrega fica no histórico de auditoria (quem, para quem, qual função, quando). Sem aviso extra aos administradores.
- Primeiro lote a usar: Pessoas (#1931).
- **Financeiro (lote 10, #1969).** Plano, faturas, pagamentos e assinatura (o módulo Financeiro) ficam **só com o administrador**: a API financeira só lê a cobrança de quem comprou, sem leitura por empresa. Viram chave os custos da conta: `financial_view` vê os valores em R$/US$ do uso de IA (tela, CSV e aviso em tempo real) e a tela da autorização de cobranças da Meta; `financial_manage` liga e desliga essa autorização. Quem vê os relatórios do CRM sem `financial_view` vê o uso (quantidade e tokens), sem valor. As linhas 393 e 869–880 do inventário ficam assim: autorização da Meta = `financial_manage`; cobrança e faturas = só administrador.
- **Integrações e tokens (lote 11, #2027).** Duas chaves protegidas, que só o administrador entrega. `integration_manage` conecta, configura e desconecta integrações (apps, webhooks, robôs, apps do painel, importações, ferramentas do Captain) e troca a credencial de uma caixa que já existe: reconectar WhatsApp, Instagram e Facebook, token de gestão do WhatsApp, servidor de e-mail e webhook da caixa de API. Criar caixa nova continua em `inbox_manage`. `token_manage` vê e troca os segredos que a plataforma gera: HMAC e segredo da caixa, chave de assinatura do webhook, token e segredo do robô, tokens do CRM e feed do Google. Nunca emite nem gira token com escopo que a pessoa não tem; o `crm_admin` deixa de emitir token. Senha colada de outro sistema (IMAP, SMTP, Twilio, provider_config) volta só para o administrador, e senha em branco mantém a guardada. Na matriz, Tokens é ajuste fino de Integrações; no servidor as chaves são independentes. Limites aceitos: a reconexão de e-mail Google/Microsoft e do TikTok continua em `inbox_manage` no servidor (o OAuth decide pela identidade), e times/busca do Linear seguem abertos para uso dentro da conversa. Este parágrafo prevalece sobre as linhas da tabela que ainda dizem `integration_manage` para o feed do Google.
- **Anúncios da Meta (lote 12, #2070).** Uma chave protegida, que só o administrador entrega, ou quem tem o ajuste "Pode entregar acima do próprio", que só o administrador liga: `meta_ads_manage` conecta, configura e desconecta os anúncios da Meta — colar o token, entrar com o Facebook, escolher a conta de anúncios e o Pixel (o que dá ao usuário do sistema da plataforma acesso à conta de anúncios do cliente), para onde os anúncios levam, o aviso de vendas no funil (grava `meta_sync` no funil do CRM), a sugestão de etapas pela IA, a leitura avulsa, o resumo e o alerta no WhatsApp do dono (ler, mudar e testar) — e age sobre o consultor (abrir, Feito, Dispensar). Implica `meta_ads_view`. `meta_ads_view` continua só com o painel. O aviso em tempo real de leitura nova passa a ir também para quem tem `meta_ads_view` ou `meta_ads_manage`, não só para o administrador. Quem tem `meta_ads_manage` vê todos os WhatsApp oficiais na tela vazia dos Anúncios sem login, como o administrador. Os valores em dinheiro (gasto, valor das vendas) ficam como estão: `sales_value_view` é o lote 13. O grupo C (`security_manage`, `audit_log_view`, `account_settings_manage`) fica **só com o administrador, sem chave** (Rodrigo, 21/10): login único, histórico de auditoria e configurações gerais da conta não viram chave de função.
- **Valores de venda (lote 13, #2075).** Uma chave protegida, que só o administrador entrega, ou quem tem "Pode entregar acima do próprio": `sales_value_view` vê os valores de venda em R$ do CRM — valor do card, somas, metas em R$ e as taxas tiradas do dinheiro (ROI, % da meta, taxa de ganho por valor). Sem ela, a função vê as contagens, o valor dos cards de que é dona e os próprios números de "Só eu" (o R$ que vendeu e a própria meta); a barra da equipe some. Administrador e agente sem função continuam vendo. O `crm_admin` não liga a chave (quem cuida de Pessoas repassa o `crm_admin`). Sem a chave dá para trabalhar: mover e ganhar o card continuam; editar o card não muda o valor que a pessoa não vê; filtro e ordenação por valor (e a visão salva) são ignorados. A meta do mês é dinheiro: a gaveta de metas pede também `sales_value_view`, e na matriz ligar as metas liga a chave. O tempo real dos cards passa a exigir `crm_view` (antes ia a todo membro da caixa). Token de integração do CRM ganha o escopo `sales_value_view`, nunca acima da função de quem emite. Fora deste lote: telas do CRM (PR b), painel de Anúncios, receita dos links CTWA e origens das campanhas (PR c), mensagens ao cliente com `{{negocio.valor}}` e webhooks. Limite conhecido, aceito pelo Rodrigo: o texto livre que a IA escreve (motivo da sugestão, resumo, nota, aviso de passagem, memória) pode citar valores da conversa.

## O que mudou na versão 4 (revisão dos chats donos de módulo)

Os 8 chats donos de módulo leram a versão 3 em 17/10. Nenhum contrariou o modelo. As respostas trouxeram correções, que entraram assim:

- **Inventário (seção 2):** entraram as rotas de produto e carrossel pela conversa (#1716, #1749), o convite pelo topo da conversa e a criação automática do modelo de aviso. "Lembrar reunião" e "novo link" passaram do CRM para o Agendamento. Os calendários de SLA foram corrigidos (desde o #1618, tela e API pedem administrador ou `crm_admin`). Ficaram registrados o vazamento das conversas por resultado do agente de IA, a caixa de campanha aceita sem ser membro e o token do criador da caixa WAHA. O botão v1 "Criar os modelos na Meta" saiu: será retirado por decisão do Rodrigo.
- **Cobertura (seção 3):** recontada pelo mesmo script. Passou de 620 para 622 ações.
- **Catálogo (seção 5):** área Agendamento explícita; recorte exato do `campaign_send`; `sales_value_view` só para valor somado em R$; regra G nos 4 caminhos; nova seção 5.16 com as regras de compatibilidade.
- **Tela e plano (seção 6):** avisos novos na tela; etapa 3 em lotes, um por vez.
- **Dúvidas (seção 7):** Z1 resolvida pela proposta do Multifunnel. J com "de acordo" do Multifunnel. Dez dúvidas novas (7.4).
- **Seção 8:** virou o registro da etapa 2.

## O que mudou na versão 3

0. **O modelo vale para qualquer porte; a matriz de C-levels é um exemplo.** Nenhum nome de cargo fica preso a um conjunto de permissões. Numa empresa pequena, a pessoa de marketing também vende, e o administrador marca Marketing e CRM no mesmo cargo. A seção 4 agora traz três exemplos: pequena, média e estruturada.
1. **Cargo tem três eixos:** área (o que abre), nível (Não vê / Só olha / Pode mexer, mais ações delicadas à parte) e alcance (de quem são os dados). Caixa e funil continuam como camadas que só restringem.
2. **Alcance com hierarquia opcional.** Sem hierarquia configurada, o alcance mostra só "Só os meus" e "Empresa toda". Quem configura time-pai na tela de Equipes ganha "Meu time" e "Times abaixo de mim" (e "Toda a minha área", se houver área). Ninguém precisa montar organograma.
3. **"Nunca delegar" virou duas listas.** Só o dono: excluir ou transferir a conta, plano e cobrança do contrato, tornar alguém administrador. Delegável com proteção: pessoas, financeiro, integrações, tokens, segurança e configurações da conta, com quatro proteções obrigatórias.
4. **Chaves novas: de 6 para 21.** As 6 de antes continuam. Entram 15, das quais 13 são protegidas. São peças: cada empresa usa as que precisa. A dúvida Y separa as que toda empresa usa das que só interessam a empresa maior.
5. **Mais de um cargo por pessoa fica para depois.** Um cargo com várias áreas marcadas resolve o caso comum. Somar cargos é etapa posterior, útil para empresa grande, e não é pré-requisito de nada.
6. **Cargos prontos viram atalho.** Escolher um atalho já traz as áreas marcadas. O administrador desmarca ou soma qualquer área. "Montar eu" fica sempre disponível.
7. **Histórico de auditoria vira obrigatório**, junto com as chaves protegidas.
8. **Nova ordem de etapas, aprovada pelo Rodrigo:** inventário (feito), conversa com os chats donos de módulo, chaves no servidor com proteções e histórico (as brechas fecham aqui), alcance e hierarquia opcional, atalhos, mockup, tela nova. Ver seção 6.

---

## 1. Conceito

### 1.1 O que é

Função personalizada é um **cargo**. É um pacote de permissões com nome, montado uma vez e entregue a várias pessoas.

### 1.2 Para que serve

Dar **autonomia sem dar a chave da casa**, em empresa de qualquer porte.

O cargo é montado com peças: áreas, nível em cada área e alcance. O administrador combina as peças como quiser e dá o nome que quiser. Nenhum nome de cargo vem preso a um conjunto de permissões.

- **Empresa pequena:** a pessoa de marketing também vende. O administrador marca Marketing e CRM no mesmo cargo, "Marketing e Vendas".
- **Empresa média:** gerente comercial, supervisor de atendimento, alguém do financeiro. Cada um com as áreas dele.
- **Empresa estruturada:** CEO, CFO, CMO, CSO (vendas), CHRO (pessoas), CTO, COO. Abaixo, Heads, Gerentes, Supervisores, Analistas e Comerciais. Este foi o exercício que deu origem ao documento. É um exemplo, não o modelo.

Hoje nenhum dos três fecha. Para a pessoa de marketing cuidar dos anúncios, ela precisa virar administradora, e aí vê o financeiro. Para alguém cadastrar pessoas, vira administrador, e aí mexe no CRM. O novo modelo resolve esses casos sem administrador. A seção 4 mostra os três exemplos montados com as mesmas peças.

### 1.3 Os três eixos do cargo

| Eixo | Pergunta | Valores |
|---|---|---|
| **Área** | o que a pessoa abre | Conversas, Contatos, CRM, Agendamento, Marketing, IA e automações, Canais e integrações, Relatórios, Financeiro, Pessoas |
| **Nível** | o que ela faz na área | Não vê · Só olha · Pode mexer. Ações delicadas (exportar, excluir, disparar, IA com custo) ficam à parte, desligadas por padrão |
| **Alcance** | de quem são os dados que ela vê | Sempre: Só os meus · Empresa toda. Só com hierarquia configurada: Meu time · Times abaixo de mim · Toda a minha área |

**Exemplos:** "Marketing e Vendas" numa empresa pequena = Marketing "Pode mexer", CRM "Pode mexer", alcance "Empresa toda". Gerente de Vendas numa empresa que configurou times = CRM "Pode mexer", Conversas "Pode mexer", Relatórios "Só olha", alcance "Times abaixo de mim".

### 1.4 O que o cargo não decide

- **Qual caixa:** quem decide é ser membro da caixa (`lib/operator_guide/porques.md:246`; #879; #894).
- **Qual funil e "Todas / Só as suas":** é o acesso por funil, por pessoa e por caixa (`docs/multifunil/PLANO.md:19-22`).
- **Esconder mensagem dentro de uma conversa:** fora do plano (`PLANO.md:39`).
- **Mascarar CPF ou telefone:** não propor. Dado sensível no chat é do negócio.

Mudou desde a versão anterior: "gestor vê o time" entrou, para quem configurar hierarquia (seção 5.7). "Mais de um cargo por pessoa" ficou para etapa posterior (seção 5.8).

### 1.5 Camadas: o alcance não fura caixa nem funil

A pessoa vê o que caixa, cargo e funil liberam **juntos**. Uma camada pode fechar, nunca abrir o que outra fechou (`PLANO.md:167`; `Crm::Access::ConversationScope` "só restringe", `app/services/crm/access/conversation_scope.rb:15`).

Decisões do Multifunnel que continuam valendo:
- **Time não fura funil.** Alcance "Meu time" continua cortado pela caixa e pelo funil.
- **Atribuído ou participante sempre vê** a conversa dele.
- **Card aberto manda:** a conversa presa a um card segue a regra do card.
- **Integração sem acesso por funil nem alcance do cargo:** token de integração (n8n, MCP) não passa pelo filtro de funil (`conversation_scope.rb:122-125`) e também fica fora do alcance do cargo. O limite dele é o próprio token (Multifunnel, 17/10).

### 1.6 Por que importa

- Hoje há 38 chaves (`enterprise/app/models/custom_role.rb:59-98`). O Chatwoot original tem 6.
- Muita coisa nova ficou presa ao administrador (Anúncios Meta, detalhamento de relatório, calendários de atendimento, tudo de pessoas e financeiro).
- Outras ficaram abertas demais (ver contatos sem chave, excluir card em massa com só "ver").
- Não existe gestor nem alcance por time. O "supervisor do time" não tem resposta.
- Sem um modelo único, cada módulo inventa a sua regra.

### 1.7 O que o cargo deve fazer

1. Mostrar no máximo três níveis por área: **Não vê / Só olha / Pode mexer**.
2. Valer no servidor, não só no menu. Se a tela esconde, a API nega.
3. Deixar as ações delicadas como ajuste à parte, desligado por padrão e confirmado na tela.
4. Não mudar nada para o administrador nem para o agente sem cargo.

### 1.8 Princípios

1. **O cargo diz o que a pessoa faz e de quem são os dados; caixa e funil dizem onde.** Nenhuma chave do cargo escolhe caixa.
2. **As camadas só se somam por interseção** (seção 1.5).
3. **Pode mexer inclui Só olha.** Regra do servidor em `enterprise/app/models/enterprise/account_user.rb:7-13`. Hoje o CRM é exceção (`enterprise/app/policies/crm_permissions.rb:21-29`).
4. **Ação delicada é chave separada, desligada por padrão, com confirmação.**
5. **A chave extra pede o "Pode mexer" da área e o inclui.** Quem tem "Excluir contatos" já tem "Mexer em contatos".
6. **Sempre aditivo e compatível.** Administrador e agente sem cargo não mudam. Chaves antigas continuam valendo, sem migração (#452).
7. **Chave nova não dá ao agente sem cargo o que ele não faz hoje.** Se hoje só o administrador faz, a chave nova entra na lista de negadas ao agente sem cargo (`crm_permissions.rb:19`; `relationships/record_permissions.rb:9`).
8. **Cargo pronto é só atalho.** Escolher um atalho já traz áreas marcadas. O administrador desmarca ou soma qualquer área, e "Montar eu" está sempre disponível. Mudar um atalho não altera cargos já salvos (doc do #1136, seção 5.1).
9. **Ajudar, não travar.** Mostrar o caminho que funciona em vez de bloquear quem atende.
10. **Excluir um cargo não pode ampliar acesso em silêncio.** Hoje quem perde o cargo volta a agente padrão, que vê mais (`custom_role.rb:53`, `dependent: :nullify`).
11. **Um cargo, várias áreas.** O caso comum se resolve marcando várias áreas no mesmo cargo. Somar cargos fica para etapa posterior (seção 5.8). Quando vier, a pessoa recebe a união das chaves e, em cada área, o maior alcance entre os cargos.
12. **Duas listas no lugar de "nunca delegar"** (aprovado em 17/10):
    - **Só o dono da conta:** excluir ou transferir a conta; mudar plano e cobrança do contrato com a Hub2You; tornar alguém administrador.
    - **Delegável com proteção:** usuários, equipes e cargos (CHRO); financeiro e faturamento (CFO); integrações, webhooks, tokens e segurança com login único (CTO); configurações da conta.
13. **As quatro proteções das chaves delegáveis** (obrigatórias):
    1. só o dono entrega essas chaves (põe num cargo ou dá um cargo que as tenha);
    2. ninguém dá a outra pessoa mais do que ele próprio tem, nem cargo de administrador;
    3. ninguém edita o próprio cargo nem o próprio acesso;
    4. tudo fica no histórico de auditoria.
14. **Nenhum nome de cargo vem preso a permissões.** O nome é do administrador. As peças são as mesmas para a empresa de 3 pessoas e para a de 300.
15. **Hierarquia é opcional.** Sem time-pai configurado, tudo funciona com "Só os meus" e "Empresa toda". Ninguém precisa montar organograma para usar cargos.

"Dono da conta" não existe no código hoje. O papel é só `agent` ou `administrator` (`app/models/account_user.rb:36`). O dono é **[NOVO]** (seção 5.5). A regra das duas listas já está escrita no `CLAUDE.md` e no `AGENTS.md` pelo PR #1783 (Issue #1782), aguardando merge. Lá, "dono" se escreve "administrador" (o papel `administrator` que já existe). Separar "dono" de "administrador" fica para a dúvida Z2.

### 1.9 Referência de mercado (resumo)

HubSpot, Pipedrive, Kommo, Zendesk, Intercom e RD Station repetem o mesmo padrão:
1. separam "o que faz" de "quais registros vê";
2. alcance em degraus: meus, da equipe, todos, e uma opção para os sem dono;
3. excluir, exportar, trocar dono e atribuir são sempre permissões à parte;
4. gerir usuários e cargos costuma ficar com o administrador. [HIPÓTESE, conferir] HubSpot e Salesforce deixam dar "gerir usuários" a quem não é administrador, com a trava de não dar mais do que a pessoa tem. É o que a proteção 2 copia.

O nosso modelo segue isso e soma a hierarquia de times, opcional, que nesses produtos costuma ser "equipe e equipes abaixo".

---

## 2. Tudo que o administrador faz hoje

Cada linha é uma ação que o administrador consegue fazer. A coluna "quem passa hoje" diz quem mais consegue. Ela é fato; só o que vem depois da seta (→) é proposta.

O inventário foi levantado em `f2488a9e9a`. Até `21d16067fc`, os arquivos de permissão só ganharam as rotas de #1702 e #1716. As do #1716 entraram na versão 4 (seção 2.6). As do #1702 continuam fora (seção 5.14). A versão 4 também incorporou o que os chats donos de módulo apontaram (Agendamento, Campanhas, Agentes de IA, Modelos, WhatsApp Híbrido).

**Como ler "quem passa hoje":**
- **chave:** só quem tem a chave do cargo (o administrador sempre passa; o agente sem cargo às vezes passa, está escrito na coluna "chave hoje");
- **membro da caixa:** quem é membro da caixa (ou vê a conversa);
- **qualquer membro:** qualquer pessoa da conta;
- **só admin:** só o administrador, sem motivo de segurança (candidata a chave comum);
- **só admin → só o dono:** hoje só o administrador; no novo modelo, só o dono da conta;
- **só admin → protegida (`chave`):** hoje só o administrador (era "nunca delegar"); no novo modelo, a chave protegida indicada (seção 5.6);
- **chave → protegida (`chave`):** hoje passa com uma chave comum; no novo modelo, sai para a chave protegida indicada;
- **sem checagem:** o servidor não confere nada além de estar logado (brecha, fica para o épico);
- **super admin:** só o dono da plataforma;
- **ninguém:** bloqueado para todos, inclusive administrador;
- **outro:** regra própria, explicada na linha.

**Siglas de caminho na coluna "prova":** `c/` = `app/controllers/api/v1/accounts/` · `c2/` = `app/controllers/api/v2/accounts/` · `p/` = `app/policies/` · `ec/` = `enterprise/app/controllers/api/v1/accounts/` · `eec/` = `enterprise/app/controllers/enterprise/api/v1/accounts/` · `ep/` = `enterprise/app/policies/` · `au/` = `app/controllers/api/v1/accounts/autonomia/` · `crm/` = `app/controllers/api/v1/accounts/crm/`. Rotas em `config/routes.rb`.

Ações iguais que apareciam mais de uma vez no inventário (Anúncios Meta, Captain, Prospecção, Cotação, Financeiro, Relatórios v2, Atribuição) estão uma vez só.

### 2.1 Conversas

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver a lista de conversas | ver | GET /conversations | membro da caixa | conversation_* (estreitam) | c/conversations_controller.rb:7,12-16; app/finders/conversation_finder.rb:101 |
| ver os números por aba | ver | GET /conversations/meta | membro da caixa | conversation_* | c/conversations_controller.rb:18-21 |
| buscar conversas pelo texto | ver | GET /conversations/search | membro da caixa | conversation_* | c/conversations_controller.rb:23-27 |
| filtro avançado de conversas | ver | POST /conversations/filter | membro da caixa | conversation_* | c/conversations_controller.rb:51-60 |
| ver não lidas por lista | ver | GET /conversations/unread_counts | qualquer membro | — | c/conversations/unread_counts_controller.rb:15-31 |
| abrir uma conversa | ver | GET /conversations/:id | membro da caixa | conversation_* | p/conversation_policy.rb:10-19; ep/enterprise/conversation_policy.rb:2-11 |
| começar conversa nova (com ou sem modelo do WhatsApp) | criar | POST /conversations | membro da caixa | — | c/conversations_controller.rb:201-222 |
| mudar prioridade e SLA | editar | PATCH /conversations/:id | membro da caixa | conversation_* | c/conversations_controller.rb:47-49,149-154 |
| mudar prioridade pelo atalho | editar | POST /conversations/:id/toggle_priority | membro da caixa | conversation_* | c/conversations_controller.rb:109-112 |
| excluir a conversa inteira | excluir | DELETE /conversations/:id | só admin | — | p/conversation_policy.rb:6-8 |
| resolver, reabrir, pendente, adiar | executar | POST /conversations/:id/toggle_status | membro da caixa | conversation_* | c/conversations_controller.rb:82-93 |
| silenciar e voltar a ouvir | executar | POST /conversations/:id/mute, /unmute | membro da caixa | conversation_* | c/conversations_controller.rb:62-70 |
| mandar o histórico por e-mail para qualquer endereço | exportar | POST /conversations/:id/transcript | membro da caixa | conversation_* | c/conversations_controller.rb:72-80 |
| avisar que está digitando | executar | POST /conversations/:id/toggle_typing_status | membro da caixa | — | c/conversations_controller.rb:114-118 |
| marcar como lida | executar | POST /conversations/:id/update_last_seen | membro da caixa | — | c/conversations_controller.rb:120-133 |
| marcar como não lida | executar | POST /conversations/:id/unread | membro da caixa | — | c/conversations_controller.rb:135-139 |
| preencher campos personalizados da conversa | editar | POST /conversations/:id/custom_attributes | membro da caixa | conversation_* | app/controllers/concerns/conversation_custom_attributes_concern.rb:2-9 |
| apagar campos personalizados da conversa | excluir | POST /conversations/:id/destroy_custom_attributes | membro da caixa | conversation_* | conversation_custom_attributes_concern.rb:11-14 |
| ver os anexos da conversa | ver | GET /conversations/:id/attachments | membro da caixa | conversation_* | c/conversations_controller.rb:29-36 |
| ver qual assistente Captain atende a caixa | ver | GET /conversations/:id/inbox_assistant | membro da caixa | — | eec/conversations_controller.rb:4-12 |
| ver a linha do tempo de eventos da conversa | ver | GET /conversations/:id/reporting_events | membro da caixa | — | eec/conversations_controller.rb:14-16; routes.rb:757 |
| ler mensagens e notas privadas | ver | GET /conversations/:id/messages | membro da caixa | conversation_* | c/conversations/base_controller.rb:6-8 |
| responder, nota privada, anexo, mandar modelo | criar | POST /conversations/:id/messages | membro da caixa | conversation_* | c/conversations/messages_controller.rb:10-24; app/builders/messages/message_builder.rb:132-133 |
| apagar mensagem, inclusive do cliente (texto vira "mensagem apagada", anexo é destruído) | excluir | DELETE /conversations/:id/messages/:id | membro da caixa | conversation_* | c/conversations/messages_controller.rb:31-36 |
| mudar status de entrega (caixa API) | editar | PATCH /conversations/:id/messages/:id | membro da caixa | — | c/conversations/messages_controller.rb:26-29,133-136 |
| reenviar mensagem que falhou | executar | POST .../messages/:id/retry | membro da caixa | — | c/conversations/messages_controller.rb:38-44 |
| traduzir mensagem (custo Google) | executar | POST .../messages/:id/translate | membro da caixa | — | c/conversations/messages_controller.rb:46-65 |
| pedir dados de contato pelo WhatsApp | executar | POST /conversations/:id/contact_info_request | membro da caixa | — | c/conversations/contact_info_requests_controller.rb:1-7 |
| ver, salvar e apagar rascunho | editar | GET/PATCH/DELETE /conversations/:id/draft_messages | membro da caixa | — | c/conversations/draft_messages_controller.rb:2-17 |
| subir arquivo direto para a conversa | criar | POST /conversations/:id/direct_uploads | sem checagem | — | c/conversations/direct_uploads_controller.rb:15-21,35-37 |
| ver etiquetas da conversa | ver | GET /conversations/:id/labels | membro da caixa | — | c/conversations/labels_controller.rb:1-8 |
| pôr ou tirar etiquetas | editar | POST /conversations/:id/labels | membro da caixa | conversation_* | c/conversations/labels_controller.rb:1-12 |
| atribuir a pessoa, robô ou time | executar | POST /conversations/:id/assignments | membro da caixa | conversation_* | c/conversations/assignments_controller.rb:3-43 |
| ver para quem passar (pessoas e IA) | ver | GET /conversations/:id/passar_para | membro da caixa | — | c/conversations/passar_para_controller.rb:7-11 |
| passar para pessoa ou agente de IA | executar | POST /conversations/:id/passar_para | membro da caixa | — | c/conversations/passar_para_controller.rb:13-20 |
| ver quem pode receber conversas das caixas | ver | GET /assignable_agents | membro da caixa | — | c/assignable_agents_controller.rb:4-16 |
| ver participantes | ver | GET /conversations/:id/participants | membro da caixa | — | c/conversations/participants_controller.rb:6-8 |
| adicionar ou trocar participantes | editar | POST/PATCH /conversations/:id/participants | membro da caixa | — | c/conversations/participants_controller.rb:10-31,61-80 |
| tirar participantes | excluir | DELETE /conversations/:id/participants | membro da caixa | — | c/conversations/participants_controller.rb:33-41 |
| ações em massa (resolver, atribuir, time, adiar, etiquetar) | executar | POST /bulk_actions | membro da caixa | — | c/bulk_actions_controller.rb:22-28; app/jobs/bulk_actions_job.rb:61-67 |
| passar a conversa para a equipe do assunto, ou manter | executar | POST /crm/conversations/:id/repasse, /repasse/manter | membro da caixa | — | crm/conversation_cards_controller.rb:43-55 |
| ver a etapa do card na lista de conversas | ver | GET /crm/conversations/card_stages | qualquer membro | — | crm/cards_controller.rb:65-78 |
| ver o card de uma conversa | ver | GET /crm/conversations/:id/card | membro da caixa | — | crm/cards_controller.rb:51-57 |
| ver os assuntos (cards) da conversa | ver | GET /crm/conversations/:id/cards | membro da caixa | — | crm/conversation_cards_controller.rb:59-61,94-96 |
| ver o nome da campanha na bolha | ver | GET /campaign_journey/campaign_names | qualquer membro | — | c/campaign_journey/campaign_names_controller.rb:8 |
| copiloto Autonom.ia: sugerir resposta | executar | POST /autonomia/conversations/:id/copilot | membro da caixa | — | au/conversation_copilot_controller.rb:43-51,59-67 |
| copiloto: ver agentes internos | ver | GET .../copilot/agents | membro da caixa | — | au/conversation_copilot_controller.rb:21-30 |
| copiloto: conversar com agente interno | executar | POST .../copilot/chat | membro da caixa | — | au/conversation_copilot_controller.rb:34-39 |
| marcar "resposta errada" na IA Autonom.ia | criar | POST /autonomia/agents/message_reports | membro da caixa | — | au/agents/message_reports_controller.rb:6-9,32-35 |
| ver ligação de WhatsApp | ver | GET /whatsapp_calls/:id | membro da caixa | conversation_* | ec/whatsapp_calls_controller.rb:17,59-62 |
| atender, recusar, desligar ligação de WhatsApp | executar | POST /whatsapp_calls/:id/accept, /reject, /terminate | membro da caixa | conversation_* | ec/whatsapp_calls_controller.rb:19-29 |
| guardar gravação da ligação | criar | POST /whatsapp_calls/:id/upload_recording | membro da caixa | — | ec/whatsapp_calls_controller.rb:31-33,113-138 |
| ligar para o cliente pelo WhatsApp | executar | POST /whatsapp_calls/initiate | membro da caixa | conversation_* | ec/whatsapp_calls_controller.rb:35-47,64-92 |
| pegar chave temporária da Twilio | executar | GET /inboxes/:id/conference/token | membro da caixa | — | ec/conference_controller.rb:5-11,52-55 |
| entrar na ligação Twilio | executar | POST /inboxes/:id/conference | membro da caixa | conversation_* | ec/conference_controller.rb:13-28 |
| encerrar ligação Twilio | executar | DELETE /inboxes/:id/conference | membro da caixa | conversation_* | ec/conference_controller.rb:30-39 |
| ver a lista de ligações (alcance: com report_manage vê a conta toda, sem ela só as próprias) | ver | GET /calls | qualquer membro | report_manage amplia | ec/calls_controller.rb:2-6; enterprise/app/finders/call_finder.rb:26-39 |
| filtros e pastas salvas (pessoais) | configurar | GET/POST/PATCH/DELETE /custom_filters | qualquer membro | — | p/custom_filter_policy.rb:2-20 |
| busca geral (conversas, mensagens, contatos, artigos) | ver | GET /search, /search/* | membro da caixa | — | c/search_controller.rb:2-33; app/services/search_service.rb:160 |
| ver as próprias notificações | ver | GET /notifications, /unread_count | qualquer membro | — | c/notifications_controller.rb:9-13,51-54 |
| marcar notificação lida, não lida, todas | editar | PATCH/POST /notifications... | qualquer membro | — | c/notifications_controller.rb:15-35 |
| adiar notificação | editar | POST /notifications/:id/snooze | qualquer membro | — | c/notifications_controller.rb:56-60 |
| apagar notificações | excluir | DELETE /notifications/:id, POST /destroy_all | qualquer membro | — | c/notifications_controller.rb:37-49 |
| preferências de aviso por e-mail e push | configurar | GET/PATCH /notification_settings | qualquer membro | — | c/notification_settings_controller.rb:2-29 |
| ligar push neste aparelho | configurar | POST/DELETE /api/v1/notification_subscriptions | qualquer membro | — | routes.rb:1118 |
| subir arquivo genérico | criar | POST /upload | qualquer membro | — | c/upload_controller.rb:2-12,21-37 |

### 2.2 Contatos, Empresas e Relacionamentos

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver a lista de contatos | ver | GET /contacts | qualquer membro | (contact_view existe mas o servidor não confere) | p/contact_policy.rb:2-4 |
| ver o resumo dos contatos | ver | GET /contacts/summary | qualquer membro | — | p/contact_policy.rb:18-20 |
| buscar contato | ver | GET /contacts/search | qualquer membro | — | p/contact_policy.rb:22-24; eec/contacts_controller.rb:4-11 |
| filtrar contatos | ver | POST /contacts/filter | qualquer membro | — | p/contact_policy.rb:26-28 |
| ver quem está online | ver | GET /contacts/active | qualquer membro | — | p/contact_policy.rb:6-8 |
| abrir a ficha do contato | ver | GET /contacts/:id | qualquer membro | — | p/contact_policy.rb:42-44 |
| criar contato | criar | POST /contacts | chave | contact_manage (admin e agente sem cargo passam) | ep/enterprise/contact_policy.rb:4-6; ep/relationships/record_permissions.rb:7-12 |
| editar contato | editar | PATCH /contacts/:id | chave | contact_manage | ep/enterprise/contact_policy.rb:8-10 |
| apagar a foto do contato | editar | DELETE /contacts/:id/avatar | chave | contact_manage | ep/enterprise/contact_policy.rb:12-14 |
| apagar campo personalizado do contato | editar | POST /contacts/:id/destroy_custom_attributes | chave | contact_manage | ep/enterprise/contact_policy.rb:16-18 |
| excluir contato | excluir | DELETE /contacts/:id | só admin | — | p/contact_policy.rb:54-56 |
| ver por quais caixas falar com o contato | ver | GET /contacts/:id/contactable_inboxes | qualquer membro | — | p/contact_policy.rb:34-36 |
| importar contatos (importador antigo) | executar | POST /contacts/import | chave | contact_manage | ep/enterprise/contact_policy.rb:24-26 |
| importar contatos (jornada nova #1006) | executar | /contact_imports/* | chave | contact_manage | c/contact_imports_controller.rb:11 |
| exportar contatos (base inteira, por e-mail) | exportar | POST /contacts/export | chave | contact_manage | ep/enterprise/contact_policy.rb:20-22 |
| juntar contatos repetidos (o absorvido é apagado) | executar | POST /actions/contact_merge | chave | contact_manage (agente sem cargo passa) | c/actions/contact_merges_controller.rb:5-14 |
| ver conversas do contato | ver | GET /contacts/:id/conversations | qualquer membro | — | c/contacts/conversations_controller.rb:24-28 |
| ver anexos do contato | ver | GET /contacts/:id/attachments | qualquer membro | — | c/contacts/attachments_controller.rb:4-9 |
| ver mídias do contato | ver | GET /contacts/:id/media... | qualquer membro | — | ec/contacts/media_controller.rb:5,17-19 |
| ligar o contato a uma caixa | criar | POST /contacts/:id/contact_inboxes | membro da caixa | — | c/contacts/contact_inboxes_controller.rb:16-19 |
| achar contato pelo identificador numa caixa | ver | POST /contact_inboxes/filter | membro da caixa | — | c/contact_inboxes_controller.rb:13-16 |
| ver etiquetas do contato | ver | GET /contacts/:id/labels | qualquer membro | — | c/contacts/labels_controller.rb:7-9 |
| pôr ou tirar etiquetas do contato | editar | POST /contacts/:id/labels | chave | contact_manage | c/contacts/labels_controller.rb:7-9 |
| ver notas do contato | ver | GET /contacts/:id/notes | qualquer membro | — | c/contacts/notes_controller.rb:2 |
| escrever, editar, apagar nota do contato | editar | POST/PATCH/DELETE /contacts/:id/notes | chave | contact_manage | c/contacts/notes_controller.rb:2,26-28 |
| marcar que o contato recusa mensagens | editar | POST/DELETE /contacts/:id/opt_out | chave | contact_manage | c/contacts/opt_outs_controller.rb:10,36-38 |
| marcar contato como cliente | editar | POST/DELETE /contacts/:id/customer | chave | contact_manage | c/contacts/customers_controller.rb:4,18-20 |
| ligar para o contato pela caixa de voz | executar | POST /contacts/:id/call | membro da caixa | — | ec/contacts/calls_controller.rb:6-7,31-36 |
| ver origem do contato e em quais públicos está | ver | GET /campaign_journey/contact_origins/:id | qualquer membro | — | c/campaign_journey/contact_origins_controller.rb:10 |
| ver, resumir e buscar empresas | ver | GET /companies, /summary, /search | qualquer membro | — | ep/company_policy.rb:4-14 |
| abrir a ficha da empresa | ver | GET /companies/:id | qualquer membro | — | ep/company_policy.rb:16-18 |
| criar empresa | criar | POST /companies | chave | contact_manage | ep/company_policy.rb:20-22 |
| editar empresa, foto, campo | editar | PATCH /companies/:id... | chave | contact_manage | ep/company_policy.rb:24-34 |
| excluir empresa | excluir | DELETE /companies/:id | só admin | — | ep/company_policy.rb:36-38 |
| ver contatos da empresa | ver | GET /companies/:id/contacts | qualquer membro | — | ec/companies/base_controller.rb:17-19 |
| ligar ou desligar contato da empresa | editar | POST/DELETE /companies/:id/contacts | chave | contact_manage | ec/companies/base_controller.rb:21-23 |
| ver conversas e notas da empresa | ver | GET /companies/:id/conversations, /notes | qualquer membro | — | ec/companies/conversations_controller.rb:9-13; notes_controller.rb:2-9 |
| ver mídias da empresa | ver | GET /companies/:id/media... | qualquer membro | — | ec/companies/media_controller.rb:4-5,28-30 |
| ver configuração dos campos | ver | GET /relationships/configuration | qualquer membro | — | c/relationships/configurations_controller.rb:7 |
| mudar configuração dos campos | configurar | PATCH /relationships/configuration | chave | attribute_manage | c/relationships/configurations_controller.rb:13 |
| preencher campo de contato ou empresa | editar | PATCH /relationships/:entity/:id/values | chave | contact_manage | c/relationships/values_controller.rb:13 |

### 2.3 Etiquetas, atributos, respostas prontas e macros

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver todas as etiquetas | ver | GET /labels | qualquer membro | — | p/label_policy.rb:2-4 |
| ver uma etiqueta | ver | GET /labels/:id | chave | label_manage | p/label_policy.rb:10-12 |
| criar, editar, excluir etiqueta | configurar | POST/PATCH/DELETE /labels | chave | label_manage | p/label_policy.rb:6-8,14-20 |
| ver atributos personalizados | ver | GET /custom_attribute_definitions | qualquer membro | — | p/custom_attribute_definition_policy.rb:2-8 |
| criar, editar, excluir atributo | configurar | POST/PATCH/DELETE /custom_attribute_definitions | chave | attribute_manage | p/custom_attribute_definition_policy.rb:10-20 |
| ver e buscar respostas prontas | ver | GET /canned_responses | qualquer membro | — | c/canned_responses_controller.rb:3 |
| criar resposta pronta | criar | POST /canned_responses | chave | canned_response_manage (agente sem cargo passa) | p/canned_response_policy.rb:4-6,18-19 |
| editar resposta pronta | editar | PATCH /canned_responses/:id | chave | canned_response_manage | p/canned_response_policy.rb:8-10 |
| excluir resposta pronta | excluir | DELETE /canned_responses/:id | chave | canned_response_manage | p/canned_response_policy.rb:12-14 |
| ver macros | ver | GET /macros | qualquer membro | — | c/macros_controller.rb:5-9 |
| ver uma macro | ver | GET /macros/:id | qualquer membro | — | p/macro_policy.rb:10-12 |
| criar macro (pessoal; da equipe pede macro_manage) | criar | POST /macros | qualquer membro | macro_manage para equipe | app/models/macro.rb:37-41 |
| editar macro (pessoal: só o autor) | editar | PATCH /macros/:id | chave | macro_manage | p/macro_policy.rb:14-18 |
| excluir macro | excluir | DELETE /macros/:id | chave | macro_manage | p/macro_policy.rb:20-24 |
| rodar macro em conversas | executar | POST /macros/:id/execute | qualquer membro | — | c/macros_controller.rb:50-54 |

### 2.4 Automações e SLA

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver regras de automação | ver | GET /automation_rules | chave | automation_view | p/automation_rule_policy.rb:2-4,10-12 |
| criar regra | criar | POST /automation_rules | chave | automation_manage | p/automation_rule_policy.rb:6-8 |
| editar regra | editar | PATCH /automation_rules/:id | chave | automation_manage | p/automation_rule_policy.rb:14-16 |
| excluir regra | excluir | DELETE /automation_rules/:id | chave | automation_manage | p/automation_rule_policy.rb:27-29 |
| duplicar regra | criar | POST /automation_rules/:id/clone | chave | automation_manage | p/automation_rule_policy.rb:18-20 |
| ensaiar regra sem executar | ver | POST /automation_rules/:id/ensaio | chave | automation_view | p/automation_rule_policy.rb:22-25 |
| ver decisores e o que decidiram | ver | GET /autonomia/decisores... | chave | automation_view | p/autonomia/decisor_policy.rb:5-15 |
| criar, editar, apagar decisor | configurar | POST/PATCH/DELETE /autonomia/decisores | chave | automation_manage | p/autonomia/decisor_policy.rb:17-27 |
| testar decisor com IA | executar | POST /autonomia/decisores/:id/teste | chave | automation_manage | p/autonomia/decisor_policy.rb:29-31 |
| confirmar exemplo do decisor | criar | POST /autonomia/decisores/:id/exemplos | chave | automation_manage | p/autonomia/decisor_policy.rb:33-35 |
| resolver caso parado do decisor | executar | POST /autonomia/decisoes/:id/resolver | chave | automation_manage | p/autonomia/decisor_policy.rb:37-39 |
| ver políticas de SLA | ver | GET /sla_policies | qualquer membro | — | ep/sla_policy_policy.rb:2-12 |
| criar política de SLA | criar | POST /sla_policies | chave | sla_manage | ep/sla_policy_policy.rb:14-16 |
| editar política de SLA | editar | PATCH /sla_policies/:id | chave | sla_manage | ep/sla_policy_policy.rb:6-8 |
| excluir política de SLA | excluir | DELETE /sla_policies/:id | chave | sla_manage | ep/sla_policy_policy.rb:18-20 |
| ver calendários de atendimento (desde o #1618, tela e API pedem administrador ou crm_admin; sla_manage sozinho não passa) | ver | GET /crm/service_schedules | chave | crm_admin | ep/enterprise/crm/service_schedule_policy.rb:6-8,24-30; app/javascript/dashboard/routes/dashboard/crm/pages/CrmSlaPage.vue:29-35 |
| criar, editar, excluir calendário de atendimento | configurar | POST/PATCH/DELETE /crm/service_schedules | chave | crm_admin | ep/enterprise/crm/service_schedule_policy.rb:10-20 |

### 2.5 Caixas de entrada (Conexões)

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver a lista de caixas (alcance: inbox_view vê todas) | ver | GET /inboxes | qualquer membro | inbox_view amplia | c/inboxes_controller.rb:108-111; p/inbox_policy.rb:18-19 |
| abrir a caixa e ver configurações | ver | GET /inboxes/:id | membro da caixa | inbox_view | p/inbox_policy.rb:31-33 |
| ver atendentes que podem receber (antigo) | ver | GET /inboxes/:id/assignable_agents | membro da caixa | inbox_view | p/inbox_policy.rb:40-42 |
| ver campanhas da caixa | ver | GET /inboxes/:id/campaigns | chave | campaign_view (e ver a caixa) | p/inbox_policy.rb:52-54 |
| ver qual robô está ligado | ver | GET /inboxes/:id/agent_bot | membro da caixa | inbox_view | p/inbox_policy.rb:44-46 |
| ver modelos aprovados da caixa (seletor da conversa) | ver | GET /inboxes/:id/message_templates | membro da caixa | inbox_view | p/inbox_policy.rb:48-50; c/concerns/inbox_health_management.rb:19-31 |
| ver saúde da conexão (grava estado) | ver | GET /inboxes/:id/health | membro da caixa | inbox_view | c/concerns/inbox_health_management.rb:5 |
| criar caixa pelo formulário | criar | POST /inboxes | chave | inbox_manage | p/inbox_policy.rb:56-58,124-126 |
| editar caixa (dados do canal podem ter credencial) | editar | PATCH /inboxes/:id | chave | inbox_manage | p/inbox_policy.rb:60-62; c/inboxes_controller.rb:141-147 |
| excluir caixa | excluir | DELETE /inboxes/:id | chave | inbox_manage | p/inbox_policy.rb:64-66 |
| tirar a foto da caixa | editar | DELETE /inboxes/:id/avatar | chave | inbox_manage | p/inbox_policy.rb:72-74 |
| ligar ou desligar robô na caixa | configurar | POST /inboxes/:id/set_agent_bot | chave | inbox_manage | p/inbox_policy.rb:68-70 |
| sincronizar modelos com a Meta | executar | POST /inboxes/:id/sync_templates | chave | inbox_manage | p/inbox_policy.rb:76-78 |
| gravar token de gestão do WhatsApp | configurar | PUT /inboxes/:id/whatsapp_business_management_token | só admin → protegida (`integration_manage`) | — | p/inbox_policy.rb:80-83 |
| registrar de novo o webhook do canal | executar | POST /inboxes/:id/register_webhook | chave | inbox_manage | c/concerns/inbox_health_management.rb:6,51 |
| gerar novo segredo da caixa API | configurar | POST /inboxes/:id/reset_secret | só admin → protegida (`token_manage`) | — | p/inbox_policy.rb:89-91 |
| trocar o token HMAC | configurar | POST /inboxes/:id/rotate_hmac_token | só admin → protegida (`token_manage`) | — | p/inbox_policy.rb:93-96 |
| ligar ou desligar campanhas de WhatsApp API na caixa | configurar | POST/DELETE /inboxes/:id/..._whatsapp_api_campaigns | chave | inbox_manage | p/inbox_policy.rb:98-104 |
| ligar ou desligar ligações de WhatsApp | configurar | POST /inboxes/:id/enable/disable_whatsapp_calling | chave | inbox_manage | eec/inboxes_controller.rb:8,17; p/inbox_policy.rb:106-112 |
| ligações recebidas e gravação | configurar | POST /inboxes/:id/set_inbound_calls, /set_call_recording | chave | inbox_manage | eec/inboxes_controller.rb:30,45; p/inbox_policy.rb:114-120 |
| ver quem atende na caixa | ver | GET /inbox_members/:id | membro da caixa | inbox_view | c/inbox_members_controller.rb:5-6 |
| pôr, trocar, tirar atendentes da caixa (muda quem vê o quê) | editar | POST/PATCH/DELETE /inbox_members | chave | inbox_manage | c/inbox_members_controller.rb:11,19,25 |
| ver modelo da pesquisa de satisfação | ver | GET /inboxes/:id/csat_template | membro da caixa | inbox_view | c/inbox_csat_templates_controller.rb:49 |
| criar modelo da pesquisa na Meta | criar | POST /inboxes/:id/csat_template | membro da caixa | — | p/inbox_policy.rb:35-38 |
| analisar texto da pesquisa com IA | executar | POST /inboxes/:id/csat_template/analyze | membro da caixa | — | c/inbox_csat_templates_controller.rb:67-71 |
| criar caixa WhatsApp por QR (WAHA). A caixa usa o token de quem a criou; com o #1709, só aceita eventos desse dono. Se essa pessoa for removida, o conector para | criar | POST /waha_inboxes | chave | inbox_manage | c/waha_inboxes_controller.rb:15; app/services/waha/inbox_provisioner.rb:82 |
| ver status, QR e reconectar WAHA | executar | GET/POST /waha_inboxes/:id/... | chave | inbox_manage | c/waha_inboxes_controller.rb:67-69 |
| ver conexão híbrida | ver | GET /whatsapp_hybrid_connections/:id | chave | inbox_manage | c/whatsapp_hybrid_connections_controller.rb:71-73 |
| conectar, código, reconectar, pausar, retomar, ajustar, desligar o híbrido | configurar | POST/PATCH/DELETE /whatsapp_hybrid_connections/:id/... | chave (não é credencial: só pareia o número) | inbox_manage | c/whatsapp_hybrid_connections_controller.rb:18-68 |
| criar caixa Twilio | criar | POST /channels/twilio_channel | chave | inbox_manage | c/channels/twilio_channels_controller.rb:17-18 |
| conectar WhatsApp oficial pelo login da Meta (caixa nova) | configurar | POST /whatsapp/authorization sem inbox_id | sem checagem | — | c/whatsapp/authorizations_controller.rb:2-4,22-27 |
| reautorizar WhatsApp de caixa existente (troca credencial) | configurar | POST /whatsapp/authorization com inbox_id | chave → protegida (`integration_manage`) | inbox_manage | c/whatsapp/authorizations_controller.rb:4-5 |
| testar dados do WhatsApp manual (recebe token) | executar | POST /whatsapp/manual/preview | chave → protegida (`integration_manage`) | inbox_manage | c/whatsapp/manual_setup_controller.rb:39-41 |
| conectar WhatsApp manual colando token | configurar | POST /whatsapp/manual/connect | chave → protegida (`integration_manage`) | inbox_manage | c/whatsapp/manual_setup_controller.rb:11-18,39-41 |
| ver webhook do WhatsApp manual | ver | GET /whatsapp/manual/:id/webhook_status | chave | inbox_manage | c/whatsapp/manual_setup_controller.rb:43-50 |
| registrar webhook do WhatsApp manual | configurar | POST /whatsapp/manual/:id/setup_webhook | chave → protegida (`integration_manage`) | inbox_manage | c/whatsapp/manual_setup_controller.rb:26-35 |
| pedir acesso ao cadastro de WhatsApp (nuvem) | configurar | POST /whatsapp/access_request | só admin → protegida (`integration_manage`) | — | ec/whatsapp/access_requests_controller.rb:4,7 |
| listar páginas do Facebook | ver | POST /callbacks/facebook_pages | sem checagem | — | c/callbacks_controller.rb:26 |
| criar caixa de página do Facebook | criar | POST/GET /callbacks/register_facebook_page | sem checagem | — | c/callbacks_controller.rb:4-24 |
| reautorizar página do Facebook (troca token de qualquer caixa) | configurar | POST /callbacks/reauthorize_page | sem checagem | — | c/callbacks_controller.rb:45-57,61-63 |
| conectar e-mail Google, Microsoft, Instagram, TikTok | criar | POST /google, /microsoft, /instagram, /tiktok/authorization | chave | inbox_manage | c/oauth_authorization_controller.rb:33-35 |
| conectar Twitter/X | criar | POST /twitter/authorization | chave | inbox_manage | c/twitter/authorizations_controller.rb:26-27 |
| testadores do Instagram | executar | /instagram/testers/* | chave | inbox_manage | c/instagram/testers_controller.rb:66-67 |
| credenciais do app OAuth de e-mail da conta | configurar | GET/PATCH/DELETE /email_oauth_apps/:provider | só admin → protegida (`integration_manage`) | — | c/email_oauth_apps_controller.rb:4,54-55 |
| ver quem atende a caixa (aba Agente de IA) | ver | GET /autonomia/inboxes/:id/quem_atende | membro da caixa | inbox_view | au/quem_atende_controller.rb:10,15-16 |
| trocar quem atende a caixa | configurar | PUT /autonomia/inboxes/:id/quem_atende | chave | inbox_manage (+ autonomia_manage para agente) | au/quem_atende_controller.rb:22-26 |
| ver a caixa WAHA para a qual fui convidado | ver | GET /autonomia/invite_connection | outro (só o convidado) | — | au/invite_connections_controller.rb:12-20,59-68 |
| ver status e QR da conexão convidada | ver | GET /autonomia/invite_connection/:id/connection | outro (só o convidado) | — | au/invite_connections_controller.rb:22-36,64 |
| reconectar WhatsApp convidado | executar | POST /autonomia/invite_connection/:id/reconnect | outro (só o convidado) | — | au/invite_connections_controller.rb:38-50,64 |

### 2.6 Modelos do WhatsApp

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver modelos do número (com "Atualizar", que sincroniza com a Meta) | ver | GET /inboxes/:id/whatsapp_templates(?refresh=true) | chave | whatsapp_templates_view | c/inboxes/whatsapp_templates_controller.rb:11,73-75; p/whatsapp_template_policy.rb:4-6 |
| ver onde o modelo está em uso | ver | GET .../whatsapp_templates/:id/usage | chave | whatsapp_templates_view | c/inboxes/whatsapp_templates_controller.rb:49-51 |
| criar modelo e mandar para a Meta | criar | POST /inboxes/:id/whatsapp_templates | chave | whatsapp_templates_manage | c/inboxes/whatsapp_templates_controller.rb:30-32; p/whatsapp_template_policy.rb:12-14 |
| alterar modelo | editar | PATCH .../whatsapp_templates/:id | chave | whatsapp_templates_manage | c/inboxes/whatsapp_templates_controller.rb:34-36 |
| excluir modelo (apaga na Meta) | excluir | DELETE .../whatsapp_templates/:id | chave | whatsapp_templates_manage | c/inboxes/whatsapp_templates_controller.rb:38-41 |
| subir arquivo de exemplo | criar | POST .../whatsapp_templates/media | chave | whatsapp_templates_manage | c/inboxes/whatsapp_templates_controller.rb:43-47 |
| ver números com modelos e envios do mês | ver | GET /whatsapp_template_inboxes | chave | whatsapp_templates_view | c/whatsapp_template_inboxes_controller.rb:11,23-25 |
| ver preço por envio e franquia | ver | GET /whatsapp_message_prices | chave | whatsapp_templates_view ou campaign_view | p/whatsapp_message_price_policy.rb:3-5 |
| criar ou melhorar modelo com IA | executar | POST /whatsapp_template_suggestions | chave | whatsapp_templates_manage | c/whatsapp_template_suggestions_controller.rb:14-15,36-38 |
| ver a autorização do dono | ver | GET /whatsapp_template_consent | chave | whatsapp_templates_manage | c/whatsapp_template_consents_controller.rb:15,20-22 |
| ligar autorização para o sistema criar modelos (gasto com a Meta) | configurar | POST /whatsapp_template_consent | só admin → protegida (`financial_manage`) | — | c/whatsapp_template_consents_controller.rb:15-18,38-43 |
| ver catálogo de produtos | ver | GET /inboxes/:id/whatsapp_catalog | chave | whatsapp_templates_view | c/inboxes/whatsapp_catalogs_controller.rb:6-8,35-37 |
| buscar produtos do catálogo | ver | GET .../whatsapp_catalog/products | chave | whatsapp_templates_view | c/inboxes/whatsapp_catalogs_controller.rb:19-22 |
| abrir a tela antiga de modelos em Campanhas | ver | tela campaigns_templates_index | só admin | — | app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js:82 |
| mandar modelo de produto ou carrossel pela conversa: catálogo, produtos, fotos aprovadas do modelo, foto do computador (#1716, no ar pelo #1749). Decisão do Rodrigo em 16/10: "liberar para quem atende a caixa". Sem chave, e não vira `whatsapp_templates_view` | ver | GET/POST /inboxes/:id/whatsapp_conversation_assets/catalog, /products, /template, /media | membro da caixa | — | p/whatsapp/templates/conversation_assets_policy.rb:5-26; routes.rb:978-983 |

O reenvio do modelo (#1768) não tem rota própria: herda o responder da conversa (membro da caixa).

### 2.7 Campanhas

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver campanhas clássicas | ver | GET /campaigns | chave | campaign_view | p/campaign_policy.rb:2 |
| abrir campanha clássica | ver | GET /campaigns/:id | chave | campaign_view | p/campaign_policy.rb:10 |
| criar campanha clássica | criar | POST /campaigns | chave | campaign_manage | p/campaign_policy.rb:14 |
| editar campanha clássica | editar | PATCH /campaigns/:id | chave | campaign_manage | p/campaign_policy.rb:6 |
| excluir campanha clássica | excluir | DELETE /campaigns/:id | chave | campaign_manage | p/campaign_policy.rb:18 |
| ver resultado da campanha de WhatsApp | ver | GET /campaigns/:id/analytics/* | chave | campaign_view | ec/campaigns/analytics_controller.rb:5,38 |
| ver campanhas de WhatsApp API | ver | GET /whatsapp_api_campaigns | chave | campaign_view | p/whatsapp_api_campaign_policy.rb:2 |
| abrir campanha de WhatsApp API | ver | GET /whatsapp_api_campaigns/:id | chave | campaign_view | p/whatsapp_api_campaign_policy.rb:6 |
| criar e disparar campanha de WhatsApp API | disparar | POST /whatsapp_api_campaigns | chave | campaign_manage | p/whatsapp_api_campaign_policy.rb:10 |
| pausar, retomar, cancelar campanha de WhatsApp API | executar | POST .../pause, /resume, /cancel | chave | campaign_manage | p/whatsapp_api_campaign_policy.rb:14,18,22 |
| ver modelos internos da caixa API | ver | GET /inboxes/:id/whatsapp_api_message_templates | chave | campaign_view | p/whatsapp_api_message_template_policy.rb:2-4 |
| criar, alterar, arquivar modelo interno da caixa API | editar | POST/PATCH/DELETE .../whatsapp_api_message_templates | chave | campaign_manage | p/whatsapp_api_message_template_policy.rb:6-16 |
| ver públicos | ver | GET /campaign_imports | chave | campaign_view | p/campaign_import_policy.rb:4 |
| abrir público | ver | GET /campaign_imports/:id | chave | campaign_view | p/campaign_import_policy.rb:8 |
| subir planilha para criar público | criar | POST /campaign_imports | chave | campaign_manage | p/campaign_import_policy.rb:20 |
| excluir público | excluir | DELETE /campaign_imports/:id | chave | campaign_manage | p/campaign_import_policy.rb:24 |
| confirmar importação do público | executar | POST /campaign_imports/:id/confirm | chave | campaign_manage | p/campaign_import_policy.rb:36 |
| desfazer etiquetas da importação | executar | POST /campaign_imports/:id/undo_labels | chave | campaign_manage | p/campaign_import_policy.rb:40 |
| baixar planilha original do público | exportar | GET /campaign_imports/:id/download | chave | campaign_manage | p/campaign_import_policy.rb:44 |
| montar público (colunas, empresas, canais, variáveis) | editar | PATCH/GET/POST /campaign_imports/:id/... | chave | campaign_manage | c/campaign_import_audiences_controller.rb:12,130 |
| ver contato de exemplo para a prévia | ver | GET /campaign_imports/:id/sample_contact | chave | campaign_manage | p/campaign_import_policy.rb:82 |
| ver linhas com problema e pessoas do público | ver | GET /campaign_imports/:id/problem_rows, /contacts | chave | campaign_view | p/campaign_import_policy.rb:72,77 |
| criar campanha multicanal pela jornada | disparar | POST /campaign_journey/campaigns | chave | campaign_manage | c/campaign_journey/campaigns_controller.rb:11,83 |
| ver prévia de quem recebe | ver | POST /campaign_journey/recipient_previews | chave | campaign_manage | c/campaign_journey/recipient_previews_controller.rb:7,24 |
| ver conversa aberta e pedir texto à IA (o POST autoriza criar campanha, e o envio manda o modelo) | executar | GET/POST /campaign_journey/conversa_aberta | chave | campaign_manage | c/campaign_journey/conversa_aberta_controller.rb:11,52 |
| ver painel geral de campanhas | ver | GET /campaign_journey/overview | chave | campaign_view | c/campaign_journey/overviews_controller.rb:10 |
| ver campanhas paradas | ver | GET /campaign_journey/campaign_pauses | chave | campaign_view | c/campaign_journey/campaign_pauses_controller.rb:19,51 |
| retomar campanha parada | disparar | POST .../campaign_pauses/:id/resume | chave | campaign_manage | c/campaign_journey/campaign_pauses_controller.rb:20,55 |
| ver resultado, destinatários e período | ver | GET /campaign_journey/results/... | chave | campaign_view | c/campaign_journey/results_controller.rb:13,49 |
| exportar resultado em planilha | exportar | GET .../results/:id/export | chave | campaign_manage | c/campaign_journey/results_controller.rb:49 |
| ver campanhas de e-mail | ver | GET /email_campaigns/campaigns | chave | campaign_view | p/email_campaign_policy.rb:2 |
| abrir campanha de e-mail | ver | GET /email_campaigns/campaigns/:id | chave | campaign_view | p/email_campaign_policy.rb:6 |
| criar campanha de e-mail | criar | POST /email_campaigns/campaigns | chave | campaign_manage | p/email_campaign_policy.rb:10 |
| editar ou excluir campanha de e-mail | editar | PATCH/DELETE /email_campaigns/campaigns/:id | chave | campaign_manage | p/email_campaign_policy.rb:14,18 |
| enviar, agendar, pausar, retomar, cancelar, reavaliar, reconferir e-mail | disparar | POST .../:id/send_now, /schedule... | chave | campaign_manage | p/email_campaign_policy.rb:22-48 |
| duplicar campanha de e-mail | criar | POST .../:id/duplicate | chave | campaign_manage | p/email_campaign_policy.rb:50 |
| e-mail de teste, imagem e vídeo | executar | POST .../:id/test_send, /assets, /resolve_video | chave | campaign_manage | c/email_campaigns/test_sends_controller.rb:14 |
| ver campos variáveis e validar o e-mail | ver | GET .../:id/placeholders, /validate | chave | campaign_view | c/email_campaigns/template_tools_controller.rb:16 |
| ver destinatários do e-mail | ver | GET .../:id/recipients | chave | campaign_view | c/email_campaigns/recipients_controller.rb:2,85 |
| subir destinatários do e-mail | criar | POST .../:id/recipients | chave | campaign_manage | c/email_campaigns/recipients_controller.rb:3,89 |
| IA do e-mail (gerar, reescrever, aplicar, desfazer) | executar | POST /email_campaigns/ai/... | chave | campaign_manage | c/email_campaigns/ai_controller.rb:16-64 |
| acompanhar a IA do e-mail | ver | GET /email_campaigns/ai/campaigns/:id/status | sem checagem | — | c/email_campaigns/ai_controller.rb:33-37 |
| ver modelos de e-mail | ver | GET /email_campaigns/templates | chave | campaign_view | p/email_campaign_template_policy.rb:2,6 |
| salvar ou excluir modelo de e-mail | criar | POST/DELETE /email_campaigns/templates | chave | campaign_manage | p/email_campaign_template_policy.rb:11,15 |
| importar modelo de e-mail (inclusive ver) | criar | /email_campaigns/template_imports/* | chave | campaign_manage | p/email_campaign_template_import_policy.rb:5-27 |
| ver remetentes e domínios de envio | ver | GET /email_campaigns/sender_identities | chave | campaign_view | p/email_sender_identity_policy.rb:2,6 |
| cadastrar remetente e domínio, conferir DNS, remover | configurar | POST/DELETE /email_campaigns/sender_identities... | chave → protegida (`account_settings_manage`) | campaign_manage | p/email_sender_identity_policy.rb:10-24 |
| ver relatórios de e-mail | ver | GET /email_campaigns/reports... | chave | campaign_view | p/email_campaign_report_policy.rb:2 |
| exportar relatório de e-mail | exportar | GET .../reports/:id/export | chave | campaign_manage | p/email_campaign_report_policy.rb:7 |
| ver e reavaliar a reputação de envio | ver | GET/POST /email_campaigns/reputation | só admin → protegida (`security_manage`) | — | p/email_reputation_policy.rb:2-8 |
| histórico, liberar provedor, forçar reputação | configurar | /email_campaigns/reputation/history... | super admin | — | p/email_reputation_policy.rb:10-20 |
| correções em lote da proteção de e-mail | executar | /email_campaigns/maintenance/backfills | super admin | — | p/email_protection_maintenance_policy.rb:2-23 |
| ver kits de marca | ver | GET /brand_kits | chave | campaign_view | p/brand_kit_policy.rb:3,7 |
| criar, editar, arquivar, padrão do kit | editar | POST/PATCH/DELETE /brand_kits... | chave | campaign_manage | p/brand_kit_policy.rb:11-29 |
| importar identidade visual de um site | criar | POST /brand_kit_imports | chave | campaign_manage | p/brand_import_job_policy.rb:7 |
| acompanhar importação de marca | ver | GET /brand_kit_imports/:id | chave | campaign_view | p/brand_import_job_policy.rb:3 |
| ver campanhas de anúncio para filtrar (métricas pedem crm_view_reports) | ver | GET /ctwa_campaigns | qualquer membro | crm_view_reports para métricas | c/ctwa_campaigns_controller.rb:108-109 |
| ver links rastreados (receita só admin) | ver | GET /ctwa_tracked_links | chave | campaign_view | c/ctwa_tracked_links_controller.rb:10,111-112 |
| criar, editar, excluir link rastreado | editar | POST/PATCH/DELETE /ctwa_tracked_links | chave | campaign_manage | c/ctwa_tracked_links_controller.rb:19,27,35 |

**Caixa da campanha aceita sem ser membro (fato, conferido pelo chat de Campanhas).** Ao montar a campanha, a tela lista só as caixas em que a pessoa é membro (`p/inbox_policy.rb:13-15`). O servidor aceita qualquer caixa da conta nos 4 pontos de criação: `app/services/campaign_journey/audience_campaign_creator.rb:71`, `app/services/campaign_journey/whatsapp_api_campaign_creator.rb:111`, `app/services/campaign_journey/email_campaign_creator.rb:75` e `c/campaign_journey/conversa_aberta_controller.rb:58`. Dúvida 7.4-5.

### 2.8 Anúncios Meta

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver a conexão, contas de anúncio, pixels e funis | ver | GET /crm/meta_ads_connection, /ad_accounts, /pixels, /funnels | só admin | — | crm/meta_ads_connections_controller.rb:40,178-189; p/crm/meta_ads_connection_policy.rb:4 |
| ver painel, números, anúncio por dentro, listas do caminho | ver | POST /insights; GET /panel, /panel_ad, /panel_list | só admin | — | crm/meta_ads_connections_controller.rb:40,93-109 |
| conectar por token ou login do Facebook | configurar | PUT /crm/meta_ads_connection; POST /facebook_login | só admin → protegida (`meta_ads_manage`) | — | crm/meta_ads_connections_controller.rb:49,63; p/crm/meta_ads_connection_policy.rb:8 |
| escolher conta, pixel, destinos, funil, sugestão de etapas | configurar | POST /selection, /suggest_stages; PATCH /destinations, /funnel | só admin → protegida (`meta_ads_manage`) | — | crm/meta_ads_connections_controller.rb:130-167 |
| desconectar os anúncios | excluir | DELETE /crm/meta_ads_connection | só admin → protegida (`meta_ads_manage`) | — | p/crm/meta_ads_connection_policy.rb:12 |
| pedir à IA a ação do dia e mensagem sugerida | executar | POST /daily_action, /quote_message | só admin | — | crm/meta_ads_ai_controller.rb:15,77-80 |
| ver o resumo dos anúncios no WhatsApp | ver | GET /whatsapp_report | só admin | — | crm/meta_ads_whatsapp_reports_controller.rb:16,46-50 |
| configurar e testar o resumo no WhatsApp | configurar | PATCH /whatsapp_report; POST /whatsapp_report/test | só admin | — | crm/meta_ads_whatsapp_reports_controller.rb:16-18 |
| abrir, aceitar, dispensar ação do consultor | executar | POST /advisor_actions/:id/open, /accept, /dismiss | só admin | — | crm/meta_ads_advisor_actions_controller.rb:12,36-39 |

### 2.9 CRM

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver a lista de funis | ver | GET /crm/pipelines | chave | crm_view (agente sem cargo passa) | crm/pipelines_controller.rb:8; ep/enterprise/crm/pipeline_policy.rb:4 |
| abrir um funil | ver | GET /crm/pipelines/:id | chave | crm_view | ep/enterprise/crm/pipeline_policy.rb:8 |
| criar funil | criar | POST /crm/pipelines | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_policy.rb:12 |
| editar funil (inclui envio de conversões Meta e Google) | configurar | PATCH /crm/pipelines/:id | chave | crm_manage_pipelines | crm/pipelines_controller.rb:28-36,122-160 |
| arquivar funil | excluir | DELETE /crm/pipelines/:id | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_policy.rb:20 |
| ver etapas | ver | GET /crm/pipelines/:id/stages | chave | crm_view | ep/enterprise/crm/pipeline_stage_policy.rb:4 |
| criar etapa | criar | POST /crm/pipelines/:id/stages | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_stage_policy.rb:12 |
| editar etapa | editar | PATCH /crm/stages/:id | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_stage_policy.rb:16 |
| excluir etapa | excluir | DELETE /crm/stages/:id | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_stage_policy.rb:20 |
| mudar ordem das etapas | editar | POST /crm/stages/reorder | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_stage_policy.rb:24 |
| ver caixas do funil | ver | GET /crm/pipelines/:id/inboxes | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_inbox_policy.rb:4 |
| ligar caixa ao funil | configurar | POST /crm/pipelines/:id/inboxes | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_inbox_policy.rb:12 |
| desligar caixa do funil | configurar | DELETE /crm/pipelines/:id/inboxes/:id | chave | crm_manage_pipelines | ep/enterprise/crm/pipeline_inbox_policy.rb:16 |
| ver IA do funil | ver | GET /crm/pipelines/:id/ai_settings | chave | crm_manage_ai | crm/ai_settings_controller.rb:4,8 |
| mudar IA do funil | configurar | PATCH /crm/pipelines/:id/ai_settings | chave | crm_manage_ai | crm/ai_settings_controller.rb:13 |
| IA melhora critérios das etapas (custo) | executar | POST .../ai_settings/improve_criteria | chave | crm_manage_ai | crm/ai_settings_controller.rb:25 |
| ver critérios padrão de funil não salvo | ver | GET /crm/stage_criteria/defaults | chave | crm_manage_pipelines + crm_manage_ai | crm/stage_criteria_controller.rb:38-41 |
| IA melhora critérios de funil não salvo | executar | POST /crm/stage_criteria/improve | chave | crm_manage_pipelines + crm_manage_ai | crm/stage_criteria_controller.rb:38-41 |
| ver automações de etapa | ver | GET /crm/stages/:id/stage_automations | chave | crm_manage_pipelines | ep/enterprise/crm/stage_automation_policy.rb:4 |
| criar automação de etapa | criar | POST /crm/stages/:id/stage_automations | chave | crm_manage_pipelines | ep/enterprise/crm/stage_automation_policy.rb:12 |
| abrir, editar, excluir automação | editar | GET/PATCH/DELETE /crm/stage_automations/:id | chave | crm_manage_pipelines | ep/enterprise/crm/stage_automation_policy.rb:8,16,20 |
| criar, editar, excluir passo da automação | editar | /crm/stage_automations/:id/steps | chave | crm_manage_pipelines | ep/enterprise/crm/stage_automation_step_policy.rb:4-12 |
| ver lista de cards | ver | GET /crm/cards | chave | crm_view | ep/enterprise/crm/card_policy.rb:4 |
| baixar planilha de cards | exportar | GET /crm/cards/export | chave | crm_export (agente sem cargo não passa) | ep/enterprise/crm/card_policy.rb:8; crm_permissions.rb:19 |
| abrir card | ver | GET /crm/cards/:id | chave | crm_view + card visível | ep/enterprise/crm/card_policy.rb:12 |
| ver opções de dono | ver | GET /crm/cards/owner_options | chave | crm_view | crm/cards_controller.rb:45 |
| ver totais da lista | ver | GET /crm/cards/summaries | chave | crm_view | crm/cards/summaries_controller.rb:10 |
| criar card | criar | POST /crm/cards | chave | crm_manage_cards + funil | ep/enterprise/crm/card_policy.rb:16 |
| criar card a partir da conversa | criar | POST /crm/cards/from_conversation | chave | crm_manage_cards | ep/enterprise/crm/card_policy.rb:33 |
| editar card, trocar dono | editar | PATCH /crm/cards/:id | chave | crm_manage_cards + funil | ep/enterprise/crm/card_policy.rb:21 |
| excluir card | excluir | DELETE /crm/cards/:id | chave | crm_manage_cards + funil | ep/enterprise/crm/card_policy.rb:25 |
| mover card de etapa | editar | POST /crm/cards/:id/move | chave | crm_move_cards ou crm_manage_cards | ep/enterprise/crm/card_policy.rb:29 |
| fechar card (ganho ou perdido) | editar | POST /crm/cards/:id/close | chave | crm_manage_cards | p/crm/card_policy.rb:32 |
| ligar ou desligar conversa do card | editar | POST .../link_conversation, /unlink_conversation | chave | crm_manage_cards | ep/enterprise/crm/card_policy.rb:37,41 |
| ligar ou desligar contato do card | editar | POST .../link_contact, /unlink_contact | chave | crm_manage_cards | ep/enterprise/crm/card_policy.rb:45,49 |
| criar contato a partir do card | criar | POST /crm/cards/:id/contact | chave | crm_manage_cards + criar contato | crm/cards/contacts_controller.rb:13-15 |
| ação em massa: mover, atribuir, status, excluir (o "excluir" em massa arquiva o card, `archive_card!`) | executar | POST /crm/cards/bulk | chave | crm_view (só "ver") | crm/cards/bulk_controller.rb:7; app/services/crm/cards/bulk_action.rb:45-49 |
| ver sugestão de etapa da IA (também o `ai_suggestion` do quadro e o filtro `ai_pending`; #2150, 23/10) | ver | GET /crm/cards/:id/current_ai_suggestion | chave | crm_manage_ai | ep/enterprise/crm/card_policy.rb:73 |
| IA avalia o card | executar | POST /crm/cards/:id/evaluate_ai | chave | crm_manage_ai | ep/enterprise/crm/card_policy.rb:53 |
| IA resume o card | executar | POST /crm/cards/:id/summarize | chave | crm_manage_ai | ep/enterprise/crm/card_policy.rb:57 |
| reiniciar follow-up automático | executar | POST /crm/cards/:id/reset_auto_followup | chave | crm_manage_ai | ep/enterprise/crm/card_policy.rb:61 |
| aceitar ou dispensar sugestão de etapa | executar | POST /crm/ai_suggestions/:id/accept, /dismiss | chave | crm_manage_ai | ep/enterprise/crm/ai_stage_suggestion_policy.rb:8,12 |
| ver o Kanban | ver | GET /crm/kanban | chave | crm_view | crm/kanban_controller.rb:7 |
| ver oportunidades do contato | ver | GET /crm/contacts/:id/opportunities | chave | crm_view | crm/contact_opportunities_controller.rb:4,8 |
| ver oportunidades da empresa | ver | GET /crm/companies/:id/opportunities | chave | crm_view | ec/crm/company_opportunities_controller.rb:7,11 |
| escolher o assunto atual da conversa | editar | POST /crm/conversations/:id/focus | chave | crm_manage_cards + funil | crm/conversation_cards_controller.rb:34 |
| aceitar ou dispensar sugestão de assunto | executar | POST .../subject_suggestions/:id/accept, /dismiss | chave | crm_manage_cards | crm/conversation_cards_controller.rb:16,25,70-71 |
| ver lembretes e janela de 24h | ver | GET /crm/follow_ups... | chave | crm_view | ep/enterprise/crm/follow_up_policy.rb:4 |
| abrir lembrete | ver | GET /crm/follow_ups/:id | chave | crm_view | ep/enterprise/crm/follow_up_policy.rb:8 |
| criar lembrete | criar | POST /crm/follow_ups | chave | crm_manage_cards | ep/enterprise/crm/follow_up_policy.rb:12 |
| editar, excluir, cancelar, adiar lembrete | editar | PATCH/DELETE/POST /crm/follow_ups/:id... | chave | crm_manage_cards | ep/enterprise/crm/follow_up_policy.rb:16,20,33 |
| concluir lembrete | executar | POST /crm/follow_ups/:id/complete | chave | crm_manage_cards | ep/enterprise/crm/follow_up_policy.rb:25-29 |
| dispensar aviso do lembrete | executar | POST /crm/follow_ups/:id/dismiss_reminder | chave | crm_view | ep/enterprise/crm/follow_up_policy.rb:35 |
| ver lembrete que repete | ver | GET /crm/follow_up_series/:id | chave | crm_view | ep/enterprise/crm/follow_up_series_policy.rb:6 |
| mudar, pausar, retomar, encerrar lembrete que repete | editar | PATCH/POST /crm/follow_up_series/:id... | chave | crm_manage_cards | ep/enterprise/crm/follow_up_series_policy.rb:10 |
| ver o calendário | ver | GET /crm/calendar/events | chave | crm_view | crm/calendar_controller.rb:3 |
| ver horários livres | ver | GET /crm/calendar/available_slots | chave | crm_view | crm/calendar_controller.rb:12 |
| ver reuniões | ver | GET /crm/meetings | chave | crm_view | crm/meetings_controller.rb:7,15 |
| abrir reunião | ver | GET /crm/meetings/:id | chave | crm_view | crm/meetings_controller.rb:177-179 |
| sincronizar reunião com a agenda (escrita com só "ver") | executar | POST /crm/meetings/:id/sync | chave | crm_view | crm/meetings_controller.rb:27-35 |
| marcar reunião | criar | POST /crm/meetings | chave | crm_manage_cards | crm/meetings_controller.rb:39-40 |
| remarcar, cancelar, resultado, resumo | editar | PATCH/DELETE/POST /crm/meetings/:id... | chave | crm_manage_cards | crm/meetings_controller.rb:64,81,96,135 |
| sugerir horários e rascunho do convite com IA | executar | POST /crm/meetings/suggest_times, /draft_invite | chave | crm_manage_cards | crm/meetings_controller.rb:116,127 |
| ver os 8 relatórios do CRM | ver | GET /crm/reports/* | chave | crm_view_reports (agente sem cargo passa) | ep/enterprise/crm/report_policy.rb:4 |
| ver quanto a IA do CRM gastou | ver | GET /crm/ai_usage | chave | crm_view_reports (agente sem cargo passa) | crm/ai_usage_controller.rb:4-5,26 |
| baixar custo de IA | exportar | GET /crm/ai_usage/export | chave | crm_view_reports | crm/ai_usage_controller.rb:12,26 |
| ver conversões enviadas à Meta | ver | GET /crm/meta_conversions... | chave | crm_view | crm/meta_conversions_controller.rb:12,27 |
| criar feed de conversões do Google | configurar | POST /crm/google_conversion_feed | só admin → protegida (`integration_manage`) | — | crm/google_conversion_feeds_controller.rb:3 |
| ver e criar visões salvas | criar | GET/POST /crm/saved_views | qualquer membro | — | p/crm/saved_view_policy.rb:2-12 |
| editar ou excluir visão salva | editar | PATCH/DELETE /crm/saved_views/:id | outro (dono ou admin) | — | p/crm/saved_view_policy.rb:16-22 |
| ver funil e etapa padrão de cada caixa | ver | GET /crm/inbox_settings | chave | crm_manage_pipelines | ep/enterprise/crm/inbox_setting_policy.rb:4 |
| mudar funil e etapa padrão da caixa | configurar | PATCH /crm/inbox_settings/:id | chave | crm_manage_pipelines | ep/enterprise/crm/inbox_setting_policy.rb:12 |
| ver quem vê o quê nas caixas e simular quem recebe | ver | GET /crm/caixas...; POST .../quem_recebe | chave | crm_admin | crm/caixas_controller.rb:5-6,44; ep/enterprise/crm/inbox_agent_access_policy.rb:5 |
| salvar configuração da caixa (pode dar a si mesmo "Todos os funis") | configurar | PUT /crm/caixas/:id | chave | crm_admin (+ autonomia_manage para IA) | crm/caixas_controller.rb:7,21,48-55,69; app/services/crm/caixas/gravador.rb:178-200 |
| ver em quais caixas eu tenho acesso restrito | ver | GET /crm/meu_acesso | qualquer membro | — | crm/meu_acesso_controller.rb:4-6 |
| ver catálogo de chaves da memória (#1601) | ver | GET /crm/memoria/chaves | só admin | — | crm/memoria_chaves_controller.rb:6,26-27 |
| editar chave do catálogo da memória | configurar | PATCH /crm/memoria/chaves/:id | só admin | — | crm/memoria_chaves_controller.rb:6,26-27 |
| ver fatos que a IA guardou do cliente | ver | GET /crm/memoria/cards/:id/fatos | chave | crm_view | crm/memoria_fatos_controller.rb:14 |
| anotar, invalidar, aceitar, destravar fato | editar | POST /crm/memoria/cards/:id/fatos... | chave | crm_manage_cards + funil | crm/memoria_fatos_controller.rb:21,33,39,47 |
| ver tokens de integração do CRM | ver | GET /crm/integration_tokens | chave → protegida (`token_manage`) | crm_admin | crm/integration_tokens_controller.rb:14 |
| criar token de integração | criar | POST /crm/integration_tokens | chave → protegida (`token_manage`) | crm_admin | crm/integration_tokens_controller.rb:20 |
| revogar token | excluir | DELETE /crm/integration_tokens/:id | chave → protegida (`token_manage`) | crm_admin | crm/integration_tokens_controller.rb:37 |
| girar token | executar | POST /crm/integration_tokens/:id/rotate | chave → protegida (`token_manage`) | crm_admin | crm/integration_tokens_controller.rb:45 |
| consultar pedido de IA em andamento | ver | GET /ai_requests/:id | outro (só quem pediu) | — | c/ai_requests_controller.rb:3-7 |

### 2.10 Agendamento

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver, criar, editar, excluir perfis antigos | configurar | /crm/booking_profiles | só admin | — | p/crm/agent_booking_profile_policy.rb:2-20 |
| mudar quem atende nos perfis antigos | configurar | /crm/booking_profiles/:id/agent_links | só admin | — | p/crm/agent_booking_profile_policy.rb:10-16 |
| ver páginas de agendamento e pessoas | ver | GET /crm/booking_pages... | chave | agendamento_view | crm/booking_pages_controller.rb:16; p/crm/booking_page_policy.rb:7-17 |
| criar, editar, excluir, publicar, pausar página | configurar | POST/PATCH/DELETE /crm/booking_pages... | chave | agendamento_manage | p/crm/booking_page_policy.rb:19-21 |
| prévia, convite de teste, logos, foto, usar identidade | editar | POST /crm/booking_pages/:id/... | chave | agendamento_manage | p/crm/booking_page_policy.rb:19-21 |
| mudar quem atende na página | configurar | PUT /crm/booking_pages/:id/people | chave | agendamento_manage | p/crm/booking_page_policy.rb:19-21 |
| passar reuniões de uma pessoa a outra | executar | GET reassign_preview; POST reassign | chave | agendamento_manage | p/crm/booking_page_policy.rb:19-21 |
| IA sugere modelo e texto de aviso; ver estado | executar | POST/GET .../notice_* | chave | agendamento_manage | p/crm/booking_page_policy.rb:19-21 |
| criar sozinho o modelo de aviso na Meta ao publicar a página ou trocar a caixa de avisos (só com a autorização do dono ligada) | executar | efeito de POST/PATCH /crm/booking_pages... | chave | agendamento_manage (+ autorização ativa) | app/models/concerns/crm/booking_notice_template_ensure.rb:18-28 |
| salvar identidade visual na conta | configurar | POST .../save_identity | só admin → protegida (`account_settings_manage`) | — | p/crm/booking_page_policy.rb:29-33 |
| conferir se o link curto está livre | ver | GET /crm/booking_pages/short_name | chave | agendamento_manage | crm/booking_page_short_names_controller.rb:13-14 |
| ver páginas para marcar e horários livres | ver | GET /crm/booking_pages/bookable, /:id/slots | outro (quem pode atender) | — | p/crm/booking_page_meeting_policy.rb:7-23; host_eligibility.rb:12,31-34 |
| marcar reunião pelo painel | criar | POST /crm/booking_pages/:id/meetings | outro (quem pode atender + card ou contato) | — | crm/booking_page_meetings_controller.rb:65-75 |
| ajustar os próprios horários | editar | GET/PUT /crm/my_booking_hours | outro (quem pode atender) | — | crm/my_booking_hours_controller.rb:9,33-34 |
| ver e gerar link por cliente (lista da equipe pede agendamento_view) | criar | GET/POST /crm/booking_invites | outro (quem pode atender) | agendamento_view amplia | p/crm/booking_invite_policy.rb:8-14,34-39 |
| gerar link pelo topo da conversa | criar | POST /crm/booking_invites com conversation_id | outro (quem pode atender + vê a conversa) | — | crm/booking_invites_controller.rb:27-35,101-104 |
| lembrar o cliente da reunião (manda mensagem) | executar | POST /crm/meetings/:id/remind | outro (crm_view + funil) | — | crm/meeting_actions_controller.rb:42-51 |
| mandar novo link para remarcar | executar | POST /crm/meetings/:id/rebook_link | outro (quem pode atender + funil) | — | crm/meeting_actions_controller.rb:31,42-51 |
| entregar ou copiar link | executar | POST /crm/booking_invites/:id/deliver, /copied | outro (agendamento_view ou quem criou) | — | p/crm/booking_invite_policy.rb:16-27 |
| cancelar link | excluir | DELETE /crm/booking_invites/:id | outro (agendamento_manage ou quem criou) | — | p/crm/booking_invite_policy.rb:29-31 |
| ver números e "abriu e não marcou" ("Meus números" = links que a pessoa criou e reuniões em que ela é quem atende) | ver | GET /crm/booking_stats... | outro (meus; equipe com agendamento_view) | — | p/crm/booking_stats_policy.rb:8-18; app/services/crm/booking_v2/results.rb:22-24 |
| reenviar link para quem não marcou | executar | POST .../opened_not_booked/:id/resend | outro (quem pode atender) | — | p/crm/booking_stats_policy.rb:20-22 |

"Quem pode atender" = administrador, agente sem cargo, ou cargo com `crm_view` ou `crm_admin` (`host_eligibility.rb:31-34`). Essa elegibilidade não olha funil. Reunião marcada pelo painel grava em `crm_meetings.created_by_id` quem atende; quem marcou fica em `metadata.booked_by_user_id`.

**Saiu da tabela: botão v1 "Criar os modelos na Meta"** (`POST .../notice_templates/create`, `create_notice_templates?` em `p/crm/booking_page_policy.rb:24-27`). Será retirado, junto com a rota, por decisão do Rodrigo em 17/10, no PR do Agendamento (#1612). Ele usava o criador sem a garantia e sem a autorização (`creator.rb:44-50`). Ainda está na main até esse PR mesclar. Não vai para nenhuma chave. A criação de modelo de aviso continua só pelo caminho automático (linha "criar sozinho" acima), travada pela autorização, que hoje é só do administrador.

### 2.11 Agentes de IA (Autonom.ia)

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver a lista de agentes | ver | GET /autonomia/agents | chave | autonomia_view | au/agents_controller.rb:33; au/base_controller.rb:3,48-50 |
| abrir agente | ver | GET /autonomia/agents/:id | chave | autonomia_view | au/agents_controller.rb:37 |
| criar agente | criar | POST /autonomia/agents | chave | autonomia_manage | au/agents_controller.rb:41-54 |
| editar agente | editar | PATCH /autonomia/agents/:id | chave | autonomia_manage | au/agents_controller.rb:72-81 |
| excluir agente | excluir | DELETE /autonomia/agents/:id | chave | autonomia_manage | au/agents_controller.rb:83-86 |
| trocar ou tirar foto | editar | PATCH/DELETE /autonomia/agents/:id/avatar | chave | autonomia_manage | au/agents_controller.rb:88-105 |
| testar no playground (gasta IA) | executar | POST /autonomia/agents/:id/test | chave | autonomia_view | au/agents/playground_controller.rb:11-17,28-31 |
| rascunho de resposta no teste | executar | POST /autonomia/agents/:id/suggest | chave | autonomia_view | au/agents/playground_controller.rb:20-24 |
| ver desempenho | ver | GET /autonomia/agents/:id/analytics | chave | autonomia_view | au/agents/analytics_controller.rb:7 |
| ver conversas por resultado. **Vazamento:** só confere a conta; com `autonomia_view`, a pessoa vê até 50 conversas de caixas em que não é membro | ver | GET .../analytics/conversations | chave | autonomia_view | au/agents/analytics_controller.rb:15-33; app/services/autonomia/agents/analytics.rb:61-70 |
| ver conhecimento | ver | GET /autonomia/agents/:id/sources | chave | autonomia_view | au/agents/sources_controller.rb:5 |
| pôr conhecimento | criar | POST /autonomia/agents/:id/sources | chave | autonomia_manage | au/agents/sources_controller.rb:9 |
| apagar conhecimento | excluir | DELETE .../sources/:id | chave | autonomia_manage | au/agents/sources_controller.rb:37 |
| reler conhecimento | executar | POST .../sources/:id/resync | chave | autonomia_manage | au/agents/sources_controller.rb:46 |
| ver caixas onde atende | ver | GET /autonomia/agents/:id/channels | chave | autonomia_view | au/agents/channels_controller.rb:11 |
| ligar agente a qualquer caixa (sem ser membro nem inbox_manage; a lista mostra a conta toda) | configurar | POST /autonomia/agents/:id/channels | chave | autonomia_manage | au/agents/channels_controller.rb:7,18,43-44,105-110 |
| tirar agente da caixa | configurar | DELETE .../channels/:id | chave | autonomia_manage | au/agents/channels_controller.rb:30 |
| salvar onde e quando atende (também liga em qualquer caixa da conta) | configurar | PUT /autonomia/agents/:id/onde_atende | chave | autonomia_manage | au/agents/onde_atende_controller.rb:20-21,65,73 |
| ver o ajudante | ver | GET /autonomia/agents/:id/ajuda | chave | autonomia_view | au/agents/ajuda_controller.rb:5,8,24-25 |
| definir o ajudante | configurar | PUT /autonomia/agents/:id/ajuda | chave | autonomia_manage | au/agents/ajuda_controller.rb:14-20 |
| ver ferramentas do agente (guardam cabeçalho secreto) | ver | GET .../tools | super admin | — | au/agents/tools_controller.rb:2,48-49,77-83 |
| criar, editar, apagar ferramenta | configurar | POST/PATCH/DELETE .../tools | super admin | — | au/agents/tools_controller.rb:12-29 |
| testar ferramenta | executar | POST .../tools/:id/test | super admin | — | au/agents/tools_controller.rb:37 |
| ver sugestões de FAQ | ver | GET .../faq_suggestions | chave | autonomia_view | p/autonomia/agents/faq_suggestion_policy.rb:4-6 |
| aprovar sugestão de FAQ | editar | POST .../faq_suggestions/:id/approve | chave | autonomia_manage | p/autonomia/agents/faq_suggestion_policy.rb:8-10 |
| ignorar sugestão de FAQ | editar | POST .../faq_suggestions/:id/ignore | chave | autonomia_manage | p/autonomia/agents/faq_suggestion_policy.rb:12-14 |
| ver histórico da instrução | ver | GET .../instruction_versions | chave | autonomia_view | au/agents/instruction_versions_controller.rb:8 |
| voltar para versão anterior | editar | POST .../instruction_versions/:id/restore | chave | autonomia_manage | au/agents/instruction_versions_controller.rb:17 |
| abrir a conversa de montagem | ver | GET /autonomia/build_threads/:id | chave | autonomia_view | au/agents/build_threads_controller.rb:4 |
| começar a montar agente com IA | criar | POST /autonomia/build_threads | chave | autonomia_manage | au/agents/build_threads_controller.rb:12 |
| mandar mensagem ao construtor | executar | POST /autonomia/build_threads/:id/messages | chave | autonomia_manage | au/agents/build_threads_controller.rb:33 |
| tentar de novo a montagem | executar | POST /autonomia/build_threads/:id/retry | chave | autonomia_manage | au/agents/build_threads_controller.rb:54 |
| mandar imagem ao construtor | criar | POST /autonomia/builder_images | chave | autonomia_manage | au/agents/builder_images_controller.rb:7 |
| ver números da semana | ver | GET /autonomia/numeros_da_semana | chave | autonomia_view | au/numeros_da_semana_controller.rb:3-4 |
| ver caixas ocupadas (todas da conta) | ver | GET /autonomia/canais_ocupados | chave | autonomia_view | au/canais_ocupados_controller.rb:2-3 |

### 2.12 Prospecção

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver buscas (as de todos pede prospecting_view_all_searches) | ver | GET /autonomia/prospecting/searches | chave | prospecting_view | au/prospecting/searches_controller.rb:9,43; au/prospecting/base_controller.rb:73-79 |
| sugestão e detalhe de local (chama o Google, custo) | ver | GET .../location_suggestions, /location_details | chave | prospecting_view | au/prospecting/searches_controller.rb:21,32 |
| criar busca | criar | POST .../searches | chave | prospecting_manage | au/prospecting/searches_controller.rb:48 |
| refazer busca | editar | PATCH .../searches/:id | chave | prospecting_manage | au/prospecting/searches_controller.rb:72 |
| baixar planilha da busca | exportar | GET .../searches/:id/export | chave | prospecting_view | au/prospecting/searches_controller.rb:84 |
| excluir busca | excluir | DELETE .../searches/:id | chave | prospecting_manage | au/prospecting/searches_controller.rb:90 |
| ver leads | ver | GET .../leads | chave | prospecting_view | au/prospecting/leads_controller.rb:5,10 |
| editar lead | editar | PATCH .../leads/:id | chave | prospecting_manage | au/prospecting/leads_controller.rb:14 |
| lead vira contato (sem contact_manage) | criar | POST .../leads/:id/contact | chave | prospecting_manage | au/prospecting/leads_controller.rb:30 |
| mandar lead ao CRM | criar | POST .../leads/:id/crm_card, /leads/crm_cards | chave | prospecting_manage + criar card | au/prospecting/leads_controller.rb:49,65; base_controller.rb:16-21 |
| leads num público de campanha | criar | POST .../leads/campaign_segment | chave | prospecting_manage (+ campaign_manage) | au/prospecting/leads_controller.rb:81; base_controller.rb:25-34 |
| verificar WhatsApp do lead | executar | POST .../leads/:id/whatsapp_verification | chave | prospecting_manage | au/prospecting/leads_controller.rb:92 |
| enriquecer lead (IA) | executar | POST .../leads/:id/enrichment | chave | prospecting_manage | au/prospecting/leads_controller.rb:112 |
| pesquisar empresa e decisor (IA) | executar | POST .../leads/:id/research | chave | prospecting_manage | au/prospecting/leads_controller.rb:128 |
| usar sócio como contato | editar | POST .../leads/:id/adopt_owner | chave | prospecting_manage | au/prospecting/leads_controller.rb:141-146 |
| recusa de contato (LGPD) | editar | POST/DELETE .../leads/:id/consent_refusal | chave | prospecting_manage | au/prospecting/lead_consent_refusals_controller.rb:7,16 |
| descartar leads em lote | excluir | POST .../leads/discard | chave | prospecting_manage | au/prospecting/lead_batches_controller.rb:6 |
| contatos em lote a partir de leads | criar | POST .../leads/contacts | chave | prospecting_manage | au/prospecting/lead_batches_controller.rb:18 |
| ver listas | ver | GET .../lists | chave | prospecting_view | au/prospecting/lists_controller.rb:6,10 |
| criar lista | criar | POST .../lists | chave | prospecting_manage | au/prospecting/lists_controller.rb:15 |
| baixar planilha da lista | exportar | GET .../lists/:id/export | chave | prospecting_view | au/prospecting/lists_controller.rb:23 |
| pôr ou tirar lead da lista | editar | POST/DELETE .../lists/:id/leads | chave | prospecting_manage | au/prospecting/lists_controller.rb:29,45 |
| lista vira público de campanha | criar | POST .../lists/:id/campaign_segment | chave | prospecting_manage (+ campaign_manage) | au/prospecting/lists_controller.rb:52,61 |
| ver configurações | ver | GET .../settings | chave | prospecting_view | au/prospecting/settings_controller.rb:4 |
| mudar funil padrão, cache, pontuação, país | configurar | PATCH .../settings | chave | prospecting_manage | au/prospecting/settings_controller.rb:8-30 |
| salvar, editar, apagar jogadas | configurar | /autonomia/prospecting/saved_presets | chave | prospecting_manage | au/prospecting/saved_presets_controller.rb:7-26 |

### 2.13 Cotação (seguros)

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver conexão com o portal | ver | GET /autonomia/insurance/connection | chave | insurance_view | au/insurance/connection_controller.rb:3; au/insurance/base_controller.rb:2-3 |
| gravar login e senha do portal | configurar | POST /autonomia/insurance/connection | chave (Lia: fora das mudanças gerais) | insurance_manage | au/insurance/connection_controller.rb:13-18 |
| reconectar e reler produtos | executar | POST .../connection/reconnect, /scan | chave (Lia: fora das mudanças gerais) | insurance_manage | au/insurance/connection_controller.rb:24,36 |
| apagar conexão e credenciais | excluir | DELETE /autonomia/insurance/connection | chave (Lia: fora das mudanças gerais) | insurance_manage | au/insurance/connection_controller.rb:44-47 |
| ver se o agente de cotação existe | ver | GET /autonomia/insurance/quote_agent | chave | insurance_view | au/insurance/quote_agent_controller.rb:8 |
| criar o agente de cotação (sem autonomia_manage) | criar | POST /autonomia/insurance/quote_agent | chave | insurance_manage | au/insurance/quote_agent_controller.rb:15-17 |
| ver cotações e seguradoras acionadas | ver | GET /autonomia/insurance/measurement | chave | insurance_view | au/insurance/measurement_controller.rb:9-12 |

### 2.14 Relatórios

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| gráfico de evolução das conversas | ver | GET /api/v2/.../reports | chave | report_manage | c2/reports_controller.rb:5,105-107; ep/enterprise/report_policy.rb:2-4 |
| resumos (conta, robô, conversas por agente, métricas do robô) | ver | GET .../reports/summary, /bot_summary, /conversations_summary, /conversations, /bot_metrics | chave | report_manage | c2/reports_controller.rb:13-67 |
| baixar 6 planilhas (agente, caixa, etiqueta, time, resumo, tráfego) | exportar | GET .../reports/agents... | chave | report_manage | c2/reports_controller.rb:21-52 |
| 3 gráficos avançados | ver | GET .../reports/inbox_label_matrix... | chave | report_manage | c2/reports_controller.rb:72-95 |
| abrir as conversas por trás de um número (detalhamento) | ver | GET .../reports/drilldown | só admin | — | c2/reports_controller.rb:54-55 |
| resumo por agente, time, caixa, etiqueta, canal | ver | GET /api/v2/.../summary_reports/* | chave | report_manage | c2/summary_reports_controller.rb:2,29-31 |
| números ao vivo (também por time ou agente) | ver | GET /api/v2/.../live_reports/* | chave | report_manage | c2/live_reports_controller.rb:5,16,36-38 |
| retrospectiva do ano (pessoal) | ver | GET /api/v2/.../year_in_review | qualquer membro | — | c2/year_in_reviews_controller.rb:1-25 |
| ver avaliações de satisfação | ver | GET /csat_survey_responses | chave | report_manage | p/csat_survey_response_policy.rb:2-4 |
| ver totais da satisfação | ver | GET /csat_survey_responses/metrics | chave | report_manage | p/csat_survey_response_policy.rb:6-8 |
| baixar planilha de satisfação | exportar | GET /csat_survey_responses/download | chave | report_manage | p/csat_survey_response_policy.rb:10-12 |
| anotar revisão numa avaliação | editar | PATCH /csat_survey_responses/:id | chave | report_manage | ep/enterprise/csat_survey_response_policy.rb:14-16 |
| ver eventos brutos de relatório | ver | GET /reporting_events | só admin | — | ec/reporting_events_controller.rb:6,10 |
| ver conversas com SLA estourado | ver | GET /applied_slas | chave | report_manage | ec/applied_slas_controller.rb:7,10 |
| ver números do SLA | ver | GET /applied_slas/metrics | chave | report_manage | ec/applied_slas_controller.rb:19-23 |
| baixar planilha do SLA | exportar | GET /applied_slas/download | chave | report_manage | ec/applied_slas_controller.rb:25-30 |

### 2.15 Central de Ajuda

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver índice da Central de Ajuda da plataforma | ver | GET /central-de-ajuda | qualquer membro | — | c/central_de_ajuda_controller.rb:3-7 |
| abrir artigo da Central | ver | GET /central-de-ajuda/:id | qualquer membro | — | c/central_de_ajuda_controller.rb:10-22 |
| buscar na Central | ver | GET /central-de-ajuda/busca | qualquer membro | — | c/central_de_ajuda_controller.rb:24-26 |
| busca com IA | executar | GET /central-de-ajuda/busca_inteligente | qualquer membro | — | c/central_de_ajuda_controller.rb:30-35 |
| ver portais | ver | GET /portals | qualquer membro | — | p/portal_policy.rb:4-6 |
| ver um portal | ver | GET /portals/:slug | qualquer membro | — | p/portal_policy.rb:8-10 |
| conferir SSL do domínio | ver | GET /portals/:slug/ssl_status | qualquer membro | — | p/portal_policy.rb:12-14 |
| criar, editar, apagar, arquivar portal | configurar | POST/PATCH/DELETE /portals... | ninguém | knowledge_base_manage (sem efeito) | p/portal_policy.rb:16-22 |
| ver artigos do portal | ver | GET /portals/:slug/articles | qualquer membro | — | p/article_policy.rb:4-6 |
| abrir artigo do portal | ver | GET /portals/:slug/articles/:id | chave | knowledge_base_view | ep/enterprise/article_policy.rb:4-6 |
| criar, editar, apagar, ordenar artigos | editar | POST/PATCH/DELETE .../articles | ninguém | — | p/article_policy.rb:12-16 |
| artigos em lote | editar | .../articles/bulk_actions/* | ninguém | — | c/articles/bulk_actions_controller.rb:47-49 |
| ver categorias | ver | GET /portals/:slug/categories | qualquer membro | — | p/category_policy.rb:4-6 |
| abrir categoria | ver | GET .../categories/:id | chave | knowledge_base_view | ep/enterprise/category_policy.rb:4-6 |
| criar, editar, apagar, ordenar categorias | editar | POST/PATCH/DELETE .../categories | ninguém | — | p/category_policy.rb:12-16 |

### 2.16 Guia da Plataforma

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| perguntar ao Guia | executar | POST /autonomia/guide/chat | qualquer membro | — | au/guide_controller.rb:21-34 |
| buscar a resposta (só o próprio pedido) | ver | GET /autonomia/guide/chat/:id | qualquer membro | — | au/guide_controller.rb:43-48 |
| preparar ação proposta | ver | POST /autonomia/guide/acoes/preparar | qualquer membro | — | au/guide_controller.rb:52-57 |
| executar ação (roda com a permissão real da pessoa) | executar | POST /autonomia/guide/acoes/executar | qualquer membro | — | au/guide_controller.rb:67-77; app/services/autonomia/guide/acoes.rb:11-12,41 |
| anexar arquivo | criar | POST /autonomia/guide/arquivos | qualquer membro | — | au/guide_controller.rb:82-96 |
| falar pelo microfone | executar | POST /autonomia/guide/transcricao | qualquer membro | — | au/guide_controller.rb:101-113 |
| ver o que o Guia fez | ver | GET /autonomia/guide/execucoes | qualquer membro | — | au/guide_controller.rb:117-122 |
| desfazer algo do Guia | executar | POST .../execucoes/:id/desfazer | qualquer membro | — | au/guide_controller.rb:126-134 |
| ver conversas guardadas | ver | GET /autonomia/guide/conversas... | qualquer membro | — | au/guide_conversas_controller.rb:10-52 |
| apagar conversa com o Guia | excluir | DELETE /autonomia/guide/conversas/:id | qualquer membro | — | au/guide_conversas_controller.rb:43-46 |
| ver o que o Guia lembra | ver | GET /autonomia/guide_memorias | qualquer membro | — | au/guide_memorias_controller.rb:13-20 |
| corrigir lembrança (da empresa: só admin) | editar | PATCH /autonomia/guide_memorias/:id | outro (dono; empresa só admin) | — | au/guide_memorias_controller.rb:22-28,43-48 |
| apagar lembrança (da empresa: só admin) | excluir | DELETE /autonomia/guide_memorias/:id | outro (dono; empresa só admin) | — | au/guide_memorias_controller.rb:31-34,43-48 |
| ver vigias | ver | GET /autonomia/vigias | só admin → protegida (`account_settings_manage`) | — | p/autonomia/guide/vigia_policy.rb:4-5,12-14 |
| criar, editar, apagar vigia | configurar | POST/PATCH/DELETE /autonomia/vigias | só admin → protegida (`account_settings_manage`) | — | p/autonomia/guide/vigia_policy.rb:6-8 |
| ver avisos do Guia | ver | GET /autonomia/avisos | só admin → protegida (`account_settings_manage`) | — | p/autonomia/guide/aviso_policy.rb:2 |
| marcar aviso visto | editar | PATCH /autonomia/avisos/:id | só admin → protegida (`account_settings_manage`) | — | au/avisos_controller.rb:23-30 |
| ver pendências do Guia | ver | GET /autonomia/pendencias_do_guia | só admin → protegida (`account_settings_manage`) | — | p/autonomia/guide/execucao_policy.rb:3 |
| ver tarefas longas | ver | GET /autonomia/tarefas | qualquer membro | — | au/tarefas_controller.rb:11-20 |
| começar, seguir, pausar, retomar, cancelar tarefa | executar | POST /autonomia/tarefas/:id/... | qualquer membro | — | au/tarefas_controller.rb:22-54 |
| desfazer tarefa longa | executar | POST /autonomia/tarefas/:id/desfazer | qualquer membro | — | au/tarefas_controller.rb:42-44,57-59 |

### 2.17 Captain (IA nativa do Chatwoot, não usada)

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver preferências de IA da conta | ver | GET /captain/preferences | qualquer membro | — | c/captain/preferences_controller.rb:2-6 |
| trocar modelos e recursos de IA da conta | configurar | PATCH /captain/preferences | só admin → protegida (`account_settings_manage`) | — | c/captain/preferences_controller.rb:27-29 |
| reescrever, resumir, sugerir resposta e etiqueta | executar | POST /captain/tasks/* | qualquer membro | — | p/captain/tasks_policy.rb:2-20 |
| ver assistentes | ver | GET /captain/assistants | qualquer membro | — | ep/captain/assistant_policy.rb:2-8 |
| criar assistente | criar | POST /captain/assistants | só admin | — | ep/captain/assistant_policy.rb:30-32 |
| editar assistente | editar | PATCH /captain/assistants/:id | só admin | — | ep/captain/assistant_policy.rb:34-36 |
| apagar assistente | excluir | DELETE /captain/assistants/:id | só admin | — | ep/captain/assistant_policy.rb:46-48 |
| testar assistente (gasta IA) | executar | POST /captain/assistants/:id/playground | qualquer membro | — | ep/captain/assistant_policy.rb:54-56 |
| ver ferramentas do assistente | ver | GET /captain/assistants/tools | outro (admin, ou todos com flag) | — | ep/captain/assistant_policy.rb:26-28 |
| métricas, perguntas frequentes e resumo | ver | GET .../:id/metrics, /faq_stats, /summary | qualquer membro | — | ep/captain/assistant_policy.rb:10-20 |
| detalhamento do assistente | ver | GET .../:id/drilldown | só admin | — | ep/captain/assistant_policy.rb:22-24 |
| estatísticas de resolução | ver | GET .../:id/stats/* | qualquer membro | — | ec/captain/assistant_stats_controller.rb:5 |
| ver caixas do assistente | ver | GET .../:id/inboxes | qualquer membro | — | ec/captain/inboxes_controller.rb:2,5 |
| ligar ou desligar assistente na caixa | configurar | POST/DELETE .../:id/inboxes | só admin | — | ec/captain/inboxes_controller.rb:9,15 |
| ver cenários | ver | GET .../scenarios | qualquer membro | — | ep/captain/scenario_policy.rb:2-8 |
| criar, editar, apagar cenários | editar | POST/PATCH/DELETE .../scenarios | só admin | — | ep/captain/scenario_policy.rb:10-20 |
| ver perguntas e respostas | ver | GET /captain/assistant_responses | qualquer membro | — | ec/captain/assistant_responses_controller.rb:2,11,18 |
| detalhamento de uma resposta | ver | GET .../assistant_responses/:id/drilldown | só admin | — | ec/captain/assistant_responses_controller.rb:20 |
| criar, editar, apagar respostas | editar | POST/PATCH/DELETE /captain/assistant_responses | só admin | — | ec/captain/assistant_responses_controller.rb:26-41 |
| ver sugestões de FAQ | ver | GET /captain/faq_suggestions | membro da caixa | — | ec/captain/faq_suggestions_controller.rb:61-71 |
| editar, aprovar, descartar sugestão (aprovar cria resposta) | editar | PATCH/POST /captain/faq_suggestions/:id... | membro da caixa | — | ep/captain/faq_suggestion_policy.rb:10-20 |
| ver documentos | ver | GET /captain/documents | qualquer membro | — | ec/captain/documents_controller.rb:2,10,21 |
| detalhamento do documento | ver | GET .../documents/:id/drilldown | só admin | — | ec/captain/documents_controller.rb:48 |
| adicionar documento | criar | POST /captain/documents | só admin | — | ec/captain/documents_controller.rb:23 |
| ressincronizar documento | executar | POST .../documents/:id/sync | só admin | — | ec/captain/documents_controller.rb:34 |
| apagar documento | excluir | DELETE .../documents/:id | só admin | — | ec/captain/documents_controller.rb:52 |
| ações em lote | excluir | POST /captain/bulk_actions | só admin | — | ec/captain/bulk_actions_controller.rb:2,8 |
| ver ferramentas personalizadas (pode expor configuração de acesso) | ver | GET /captain/custom_tools | qualquer membro | — | ep/captain/custom_tool_policy.rb:2-8 |
| criar, editar, apagar, testar ferramenta personalizada | configurar | POST/PATCH/DELETE /captain/custom_tools... | só admin → protegida (`integration_manage`) | — | ep/captain/custom_tool_policy.rb:10-24 |
| ver as próprias conversas com o copiloto | ver | GET /captain/copilot_threads... | qualquer membro | — | ec/captain/copilot_threads_controller.rb:7-14 |
| conversar com o copiloto (conversa citada não é conferida) | executar | POST /captain/copilot_threads, .../copilot_messages | sem checagem | — | ec/captain/copilot_threads_controller.rb:16-31,65-74; copilot_messages_controller.rb:13-19 |
| ver de onde a IA tirou a resposta | ver | GET /captain/agent_sessions/:id | membro da caixa | — | ec/captain/agent_sessions_controller.rb:2-5,24-26 |
| marcar resposta do Captain como errada | criar | POST /captain/message_reports | membro da caixa | — | ec/captain/message_reports_controller.rb:17-27 |

### 2.18 Integrações e robôs

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver robôs | ver | GET /agent_bots | qualquer membro | — | p/agent_bot_policy.rb:2-4,10-12 |
| criar, editar, excluir robô | configurar | POST/PATCH/DELETE /agent_bots | só admin → protegida (`integration_manage`) | — | p/agent_bot_policy.rb:6-8,14-20 |
| tirar foto do robô | editar | DELETE /agent_bots/:id/avatar | só admin → protegida (`integration_manage`) | — | p/agent_bot_policy.rb:22-24 |
| novo token ou segredo do robô | configurar | POST /agent_bots/:id/reset_access_token, /reset_secret | só admin → protegida (`token_manage`) | — | p/agent_bot_policy.rb:26-32 |
| ver webhooks | ver | GET /webhooks | só admin → protegida (`integration_manage`) | — | p/webhook_policy.rb:2-4 |
| criar, editar, excluir webhook | configurar | POST/PATCH/DELETE /webhooks | só admin → protegida (`integration_manage`) | — | p/webhook_policy.rb:6-16 |
| ver apps no painel | ver | GET /dashboard_apps | qualquer membro | — | p/dashboard_app_policy.rb:2-8 |
| criar, editar, excluir app no painel | configurar | POST/PATCH/DELETE /dashboard_apps | só admin → protegida (`integration_manage`) | — | p/dashboard_app_policy.rb:10-20 |
| ver catálogo de integrações | ver | GET /integrations/apps | qualquer membro | — | c/integrations/apps_controller.rb:2 |
| ligar, alterar, desligar integração | configurar | POST/PATCH/DELETE /integrations/hooks | só admin → protegida (`integration_manage`) | — | p/hook_policy.rb:2-16 |
| disparar evento da integração na conversa | executar | POST /integrations/hooks/:id/process_event | qualquer membro | — | p/hook_policy.rb:10-12 |
| conectar, alterar, desconectar Slack | configurar | /integrations/slack | só admin → protegida (`integration_manage`) | — | c/integrations/slack_controller.rb:2 |
| desconectar Linear | excluir | DELETE /integrations/linear | só admin → protegida (`integration_manage`) | — | c/integrations/linear_controller.rb:3-4 |
| usar Linear na conversa (não confere se vê a conversa) | executar | /integrations/linear/* | qualquer membro | — | c/integrations/linear_controller.rb:2-4,109-111 |
| iniciar conexão Shopify | configurar | POST /integrations/shopify/auth | sem checagem | — | c/integrations/shopify_controller.rb:4-8 |
| ver pedidos Shopify do contato | ver | GET /integrations/shopify/orders | qualquer membro | — | c/integrations/shopify_controller.rb:25 |
| desconectar Shopify | excluir | DELETE /integrations/shopify | só admin → protegida (`integration_manage`) | — | c/integrations/shopify_controller.rb:35 |
| iniciar conexão Notion (passa por inbox_manage) | configurar | POST /notion/authorization | chave → protegida (`integration_manage`) | inbox_manage | c/oauth_authorization_controller.rb:33-35 |
| desconectar Notion | excluir | DELETE /integrations/notion | só admin → protegida (`integration_manage`) | — | c/integrations/notion_controller.rb:2-3 |
| reunião de vídeo Dyte na conversa | executar | POST /integrations/dyte/* | outro (quem vê a conversa) | — | c/integrations/dyte_controller.rb:24-25 |

### 2.19 Usuários, equipes e cargos

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver pessoas da conta | ver | GET /agents | qualquer membro | — | p/user_policy.rb:2-4 |
| convidar pessoa (papel e cargo) | criar | POST /agents | só admin → protegida (`user_manage`) | — | p/user_policy.rb:6-8; eec/agents_controller.rb:16-24 |
| convidar várias pessoas | criar | POST /agents/bulk_create | só admin → protegida (`user_manage`) | — | p/user_policy.rb:18-20 |
| editar pessoa (papel, cargo; sem o campo do cargo, o cargo é apagado; tornar administrador está na linha de baixo) | editar | PATCH /agents/:id | só admin → protegida (`user_manage`) | — | p/user_policy.rb:10-12; eec/agents_controller.rb:9-12,23 |
| tornar alguém administrador (campo papel no convite ou na edição) | editar | POST/PATCH /agents (campo `role`) | só admin → só o dono | — | p/user_policy.rb:6-12; app/models/account_user.rb:36 |
| remover pessoa (se ela criou uma caixa WAHA, o conector dessa caixa para) | excluir | DELETE /agents/:id | só admin → protegida (`user_manage`) | — | p/user_policy.rb:14-16 |
| ver times | ver | GET /teams | qualquer membro | — | p/team_policy.rb:2-12 |
| criar time | criar | POST /teams | só admin → protegida (`team_manage`) | — | p/team_policy.rb:14-16 |
| editar time | editar | PATCH /teams/:id | só admin → protegida (`team_manage`) | — | p/team_policy.rb:6-8 |
| excluir time | excluir | DELETE /teams/:id | só admin → protegida (`team_manage`) | — | p/team_policy.rb:18-20 |
| ver membros do time | ver | GET /teams/:id/team_members | qualquer membro | — | p/team_member_policy.rb:2-4 |
| pôr pessoas no time | editar | POST /teams/:id/team_members | só admin → protegida (`team_manage`) | — | p/team_member_policy.rb:6-8 |
| trocar a lista de membros | editar | PATCH /teams/:id/team_members | só admin → protegida (`team_manage`) | — | p/team_member_policy.rb:14-16 |
| tirar pessoas do time | editar | DELETE /teams/:id/team_members | só admin → protegida (`team_manage`) | — | p/team_member_policy.rb:10-12 |
| ver cargos | ver | GET /custom_roles | só admin → protegida (`role_manage`) | — | ep/custom_role_policy.rb:2-12 |
| criar cargo | criar | POST /custom_roles | só admin → protegida (`role_manage`) | — | ep/custom_role_policy.rb:14-16 |
| editar cargo | editar | PATCH /custom_roles/:id | só admin → protegida (`role_manage`) | — | ep/custom_role_policy.rb:6-8 |
| excluir cargo (quem tinha volta a agente padrão) | excluir | DELETE /custom_roles/:id | só admin → protegida (`role_manage`) | — | ep/custom_role_policy.rb:18-20; enterprise/app/models/custom_role.rb:53 |

### 2.20 Regras de distribuição e capacidade

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver regras de distribuição | ver | GET /assignment_policies | só admin | — | p/assignment_policy_policy.rb:2-8 |
| criar regra | criar | POST /assignment_policies | só admin | — | p/assignment_policy_policy.rb:10-12 |
| editar regra | editar | PATCH /assignment_policies/:id | só admin | — | p/assignment_policy_policy.rb:14-16 |
| excluir regra | excluir | DELETE /assignment_policies/:id | só admin | — | p/assignment_policy_policy.rb:18-20 |
| ver caixas de uma regra | ver | GET /assignment_policies/:id/inboxes | só admin | — | c/assignment_policies/inboxes_controller.rb:3 |
| ver regra da caixa | ver | GET /inboxes/:id/assignment_policy | só admin | — | c/inboxes/assignment_policies_controller.rb:4 |
| ligar regra na caixa | configurar | POST /inboxes/:id/assignment_policy | só admin | — | c/inboxes/assignment_policies_controller.rb:11-18 |
| desligar regra da caixa | configurar | DELETE /inboxes/:id/assignment_policy | só admin | — | c/inboxes/assignment_policies_controller.rb:20-23 |
| ver políticas de capacidade | ver | GET /agent_capacity_policies | só admin | — | ep/agent_capacity_policy_policy.rb:2-4,10-12 |
| criar política de capacidade | criar | POST /agent_capacity_policies | só admin | — | ep/agent_capacity_policy_policy.rb:6-8 |
| editar política de capacidade | editar | PATCH /agent_capacity_policies/:id | só admin | — | ep/agent_capacity_policy_policy.rb:14-16 |
| excluir política de capacidade | excluir | DELETE /agent_capacity_policies/:id | só admin | — | ep/agent_capacity_policy_policy.rb:18-20 |
| ver pessoas da política | ver | GET .../:id/users | só admin | — | ec/agent_capacity_policies/users_controller.rb:2 |
| pôr pessoa na política | editar | POST .../:id/users | só admin | — | ec/agent_capacity_policies/users_controller.rb:11-15 |
| tirar pessoa da política | editar | DELETE .../:id/users/:id | só admin | — | ec/agent_capacity_policies/users_controller.rb:17-20 |
| definir limite por caixa | criar | POST .../:id/inbox_limits | só admin | — | ec/agent_capacity_policies/inbox_limits_controller.rb:8-13 |
| mudar limite por caixa | editar | PATCH .../inbox_limits/:id | só admin | — | ec/agent_capacity_policies/inbox_limits_controller.rb:15-17 |
| apagar limite por caixa | excluir | DELETE .../inbox_limits/:id | só admin | — | ec/agent_capacity_policies/inbox_limits_controller.rb:19-22 |

### 2.21 Conta, faturamento, financeiro e primeiros passos

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver dados da conta (carregado no painel) | ver | GET /accounts/:id | qualquer membro | — | p/account_policy.rb:2-4 |
| chaves de cache (técnico) | ver | GET /cache_keys | qualquer membro | — | p/account_policy.rb:6-8 |
| alterar dados da conta | configurar | PATCH /accounts/:id | só admin → protegida (`account_settings_manage`) | — | p/account_policy.rb:14-16 |
| marcar presença | executar | POST /update_active_at | qualquer membro | — | p/account_policy.rb:18-20 |
| ver limites de uso | ver | GET /limits | qualquer membro | — | p/account_policy.rb:10-12 |
| ver resumo da cobrança | ver | GET /billing_summary | só admin → protegida (`financial_view`) | — | ep/enterprise/account_policy.rb:2-4 |
| iniciar assinatura | executar | POST /subscription | só admin → só o dono | — | p/account_policy.rb:22-24 |
| escolher moeda | configurar | POST /select_billing_currency | só admin → só o dono | — | p/account_policy.rb:26-28 |
| abrir portal de pagamento | executar | POST /checkout | só admin → só o dono | — | p/account_policy.rb:30-32 |
| comprar créditos | executar | POST /topup_checkout | só admin → protegida (`financial_manage`) | — | p/account_policy.rb:38-40 |
| ver pacotes de créditos | ver | GET /topup_options | só admin → protegida (`financial_view`) | — | p/account_policy.rb:42-44 |
| pedir exclusão da conta | excluir | POST /toggle_deletion | só admin → só o dono | — | p/account_policy.rb:34-36 |
| layout de e-mail com marca | configurar | GET/PATCH /branded_email_layout | só admin → protegida (`account_settings_manage`) | — | c/branded_email_layouts_controller.rb:2 |
| ver assinatura Autonom.ia | ver | GET /autonomia/financial/subscription | só admin → protegida (`financial_view`) | — | au/financial_controller.rb:4,7,25-27 |
| ver prévia da cobrança | ver | GET /autonomia/financial/billing_preview | só admin → protegida (`financial_view`) | — | au/financial_controller.rb:11 |
| ver faturas | ver | GET /autonomia/financial/invoices | só admin → protegida (`financial_view`) | — | au/financial_controller.rb:15 |
| ver pagamentos | ver | GET /autonomia/financial/payments | só admin → protegida (`financial_view`) | — | au/financial_controller.rb:19 |
| concluir etapa do cadastro inicial | configurar | PATCH /onboarding | só admin → protegida (`account_settings_manage`) | — | c/onboardings_controller.rb:2,9-19 |
| ver geração da central de ajuda inicial | ver | GET /onboarding/help_center_generation | só admin → protegida (`account_settings_manage`) | — | c/onboardings_controller.rb:21-23 |
| ver a trilha de primeiros passos | ver | GET /onboarding/progress | qualquer membro | — | c/onboarding_progress_controller.rb:5-7 |
| pular passo da trilha | executar | POST /onboarding/progress/:id/skip | só admin → protegida (`account_settings_manage`) | — | c/onboarding_progress_controller.rb:10-11,28-30 |
| retomar passo da trilha | executar | POST /onboarding/progress/:id/resume | só admin → protegida (`account_settings_manage`) | — | c/onboarding_progress_controller.rb:18-19 |
| abrir telas Fluxo de conversa, Modelos, Importar dados | configurar | telas de configuração | só admin → protegida (`account_settings_manage`) | — | conversationWorkflow.routes.js:17; templates.routes.js:17; data.routes.js:20,29 |

### 2.22 Segurança

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver registro de auditoria | ver | GET /audit_logs | só admin → protegida (`audit_log_view`) | — | ec/audit_logs_controller.rb:2 |
| ver login único (SAML) | ver | GET /saml_settings | só admin → protegida (`security_manage`) | — | ep/account_saml_settings_policy.rb:2-4 |
| cadastrar login único | configurar | POST /saml_settings | só admin → protegida (`security_manage`) | — | ep/account_saml_settings_policy.rb:6-8 |
| alterar login único | configurar | PATCH /saml_settings | só admin → protegida (`security_manage`) | — | ep/account_saml_settings_policy.rb:10-12 |
| apagar login único | excluir | DELETE /saml_settings | só admin → protegida (`security_manage`) | — | ep/account_saml_settings_policy.rb:14-16 |

### 2.23 Importação de outro sistema

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| ver importações | ver | GET /data_imports | só admin → protegida (`integration_manage`) | — | p/data_import_policy.rb:2-8 |
| testar a chave do outro sistema | executar | POST /data_imports/validate_source | só admin → protegida (`integration_manage`) | — | p/data_import_policy.rb:14-16 |
| iniciar importação | criar | POST /data_imports | só admin → protegida (`integration_manage`) | — | p/data_import_policy.rb:10-12 |
| recomeçar, repetir, abandonar | executar | POST /data_imports/:id/start, /retry, /abandon | só admin → protegida (`integration_manage`) | — | p/data_import_policy.rb:18-28 |
| baixar erros e itens pulados | ver | GET /data_imports/:id/error_logs, /skip_logs | só admin → protegida (`integration_manage`) | — | p/data_import_policy.rb:30-36 |

### 2.24 Fora da conta (só para registro)

| Ação | Tipo | Endpoint | Quem passa hoje | Chave hoje | Prova |
|---|---|---|---|---|---|
| criar conta nova pelo cadastro público | criar | POST /api/v1/accounts, /api/v2/accounts | outro (público, com captcha) | — | c/../accounts_controller.rb:4-11; c2/../accounts_controller.rb:4-9 |
| primeira configuração da instalação | configurar | /installation/onboarding | outro (só na instalação nova) | — | app/controllers/installation/onboarding_controller.rb:2-15 |
| ligar módulos por conta e configs da instalação | configurar | /super_admin/* | super admin | — | routes.rb:1409-1428 |

---

## 3. Cobertura

Contagem feita por script sobre as tabelas da seção 2 (uma linha = uma ação; ações agrupadas no inventário continuam agrupadas). O script foi conferido antes: rodado na versão anterior, ele devolve os mesmos números dela (619, 298, 73, 47, 8, 162, 21, 10). A diferença de 619 para 620 é a linha nova "tornar alguém administrador", separada de "editar pessoa".

**Versão 4: de 620 para 622.** O script, rodado de novo, devolve os mesmos números da versão 3 em todos os módulos que não mudaram. Mudaram três: Modelos (+1, produto e carrossel pela conversa, aberta a membro da caixa); Agendamento (+3: entraram o convite pelo topo da conversa, a criação automática do modelo de aviso, e "lembrar" e "novo link", que vieram do CRM; saiu o botão v1 retirado); CRM (−2, "lembrar" e "novo link" foram para o Agendamento).

| Módulo | Ações | Só o dono | Delegável com proteção | Com chave | (dessas, vão para chave protegida) | Só admin (não sensível) | Sem checagem | Aberto | Regra própria | Super admin ou ninguém |
|---|---|---|---|---|---|---|---|---|---|---|
| Conversas | 66 | 0 | 0 | 0 | 0 | 1 | 1 | 64 | 0 | 0 |
| Contatos, Empresas e Relacionamentos | 41 | 0 | 0 | 17 | 0 | 2 | 0 | 22 | 0 | 0 |
| Etiquetas, atributos, respostas prontas e macros | 15 | 0 | 0 | 8 | 0 | 0 | 0 | 7 | 0 | 0 |
| Automações e SLA | 17 | 0 | 0 | 16 | 0 | 0 | 0 | 1 | 0 | 0 |
| Caixas de entrada (Conexões) | 49 | 0 | 5 | 26 | 4 | 0 | 4 | 11 | 3 | 0 |
| Modelos do WhatsApp | 15 | 0 | 1 | 12 | 0 | 1 | 0 | 1 | 0 | 0 |
| Campanhas | 59 | 0 | 1 | 54 | 1 | 0 | 1 | 1 | 0 | 2 |
| Anúncios Meta | 9 | 0 | 3 | 0 | 0 | 6 | 0 | 0 | 0 | 0 |
| CRM | 84 | 0 | 1 | 77 | 4 | 2 | 0 | 2 | 2 | 0 |
| Agendamento | 22 | 0 | 1 | 8 | 0 | 2 | 0 | 0 | 11 | 0 |
| Agentes de IA (Autonom.ia) | 35 | 0 | 0 | 32 | 0 | 0 | 0 | 0 | 0 | 3 |
| Prospecção | 26 | 0 | 0 | 26 | 0 | 0 | 0 | 0 | 0 | 0 |
| Cotação (seguros) | 7 | 0 | 0 | 7 | 0 | 0 | 0 | 0 | 0 | 0 |
| Relatórios | 16 | 0 | 0 | 13 | 0 | 2 | 0 | 1 | 0 | 0 |
| Central de Ajuda | 15 | 0 | 0 | 2 | 0 | 0 | 0 | 9 | 0 | 4 |
| Guia da Plataforma | 21 | 0 | 5 | 0 | 0 | 0 | 0 | 14 | 2 | 0 |
| Captain (IA nativa do Chatwoot, não usada) | 33 | 0 | 2 | 0 | 0 | 13 | 1 | 16 | 1 | 0 |
| Integrações e robôs | 20 | 0 | 11 | 1 | 1 | 0 | 1 | 6 | 1 | 0 |
| Usuários, equipes e cargos | 18 | 1 | 14 | 0 | 0 | 0 | 0 | 3 | 0 | 0 |
| Regras de distribuição e capacidade | 18 | 0 | 0 | 0 | 0 | 18 | 0 | 0 | 0 | 0 |
| Conta, faturamento, financeiro e primeiros passos | 23 | 4 | 14 | 0 | 0 | 0 | 0 | 5 | 0 | 0 |
| Segurança | 5 | 0 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Importação de outro sistema | 5 | 0 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Fora da conta (só para registro) | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 1 |
| **Total** | **622** | **5** | **68** | **299** | **10** | **47** | **8** | **163** | **22** | **10** |

**Como ler:**
- **Só o dono:** hoje só o administrador; no novo modelo, só o dono da conta.
- **Delegável com proteção:** hoje só o administrador (era "sensível"); no novo modelo, uma chave protegida.
- **Com chave:** um cargo consegue liberar a ação hoje. A coluna seguinte diz quantas dessas saem da chave comum para uma chave protegida.
- **Só admin (não sensível):** presa ao administrador sem motivo de segurança. Candidata a chave comum.
- **Sem checagem:** brecha. Fica para o épico.
- **Aberto:** passa por ser membro da caixa ou da conta. Em Conversas é de propósito: o trio `conversation_*` só estreita o alcance.

**Números principais (622 ações):**
- **5 só do dono:** iniciar assinatura, escolher moeda do contrato, abrir o portal de pagamento, pedir exclusão da conta, tornar alguém administrador. "Transferir a conta" não tem endpoint hoje **[NOVO]**.
- **68 delegáveis com proteção** (hoje só admin): 20 de integrações, 14 de configurações da conta, 6 de equipes, 6 do financeiro para ver, 5 de segurança, 4 de usuários, 4 de cargos, 3 de tokens, 3 da conexão de Anúncios Meta, 2 do financeiro para mexer, 1 do histórico de auditoria.
- **299 com chave** (48%). Dessas, **10 saem para chave protegida**: 5 credenciais e webhooks hoje em `inbox_manage` ou no Notion vão para `integration_manage`; 4 tokens do CRM saem de `crm_admin` para `token_manage`; o domínio de envio de e-mail sai de `campaign_manage` para `account_settings_manage`.
- **47 só admin sem motivo de segurança.** As maiores: 18 de distribuição e capacidade (ganham `assignment_manage`), 13 do Captain (fora da matriz), 6 de Anúncios Meta (ganham `meta_ads_view` e `meta_ads_manage`).
- **8 sem checagem** e **163 abertas por desenho** (a nova é produto e carrossel pela conversa, decisão do Rodrigo de 16/10).

**O que mudou de marcação e por quê:**
- **Híbrido do WhatsApp:** deixou de ser "sensível". O controller só recebe ajustes de rota e de limite (`whatsapp_hybrid_connections_controller.rb:86-87`), sem credencial colada. É parear número, como o WAHA. Fica em `inbox_manage`.
- **Modelos de aviso do Agendamento na Meta (corrigido na versão 4):** a versão 3 dizia que isso "deixou de ser sensível". Estava errado. O sensível é a **autorização de gasto** com a Meta, não criar o modelo. O botão v1 sai por decisão do Rodrigo (#1612) e não vai para chave nenhuma. A criação automática ao publicar a página fica em `agendamento_manage`, porque só roda com a autorização ligada. A autorização segue só admin (dúvida X e 7.4-6).
- **Credencial do portal de cotação (3 linhas):** continua em `insurance_manage`. A Lia fica fora das mudanças gerais.

**Destaques:**
- **Pessoas, conta e segurança:** das 38 ações que eram "nunca delegar" nessas três seções, 33 viram chave protegida e 5 ficam com o dono.
- **Anúncios Meta:** 9 de 9 presas ao administrador hoje. Com `meta_ads_view` (6) e `meta_ads_manage` (3), o CMO cuida de tudo sem ser administrador.
- **Contatos:** 22 ações abertas a qualquer membro, inclusive ler a base inteira. `contact_view` existe e o servidor não confere (#1157).
- **Relatórios:** o detalhamento e os eventos brutos são só admin. O detalhamento abre conversas, então precisa respeitar o alcance (dúvida I).

---

## 4. Exemplos: o mesmo modelo em empresas de tamanhos diferentes

As peças são as mesmas: áreas, nível em cada área e alcance. O administrador combina como quiser e dá o nome que quiser. Os três exemplos abaixo usam só essas peças. Nenhum deles é obrigatório.

### 4.1 Empresa pequena (3 a 8 pessoas)

Sem times configurados. O alcance mostra só "Só os meus" e "Empresa toda", mais as opções de conversa que já existem (as dela e as da fila).

| Pessoa | Áreas e nível | Alcance |
|---|---|---|
| **Dono** | tudo (papel administrador + dono) | Empresa toda |
| **Marketing e Vendas** (uma pessoa) | Marketing: Pode mexer. CRM: Pode mexer | Empresa toda |
| **Atendentes** | Conversas: Pode mexer. Contatos: Só olha | Só os meus + fila |

Um cargo só resolve a pessoa que faz marketing e vende. Se ela também responde clientes, o administrador marca Conversas na mesma tela. Disparar campanha e conectar anúncios são ajustes à parte: o primeiro é ação delicada, o segundo é chave protegida que só o dono entrega.

### 4.2 Empresa média

O dono configurou, na tela de Equipes, o time Comercial e o time Atendimento, cada um com quem lidera. Isso liga "Meu time" e "Times abaixo de mim".

| Pessoa | Áreas e nível | Alcance |
|---|---|---|
| **Dono** | tudo (papel administrador + dono) | Empresa toda |
| **Gerente comercial** | CRM, Conversas e Contatos: Pode mexer. Relatórios: Só olha | Times abaixo de mim |
| **Supervisor de atendimento** | Conversas: Pode mexer + reatribuir. Relatórios: Só olha | Meu time |
| **Vendedores** | CRM e Conversas: Pode mexer | Só os meus + fila |
| **Atendentes** | Conversas: Pode mexer. Contatos: Só olha | Só os meus + fila |
| **Financeiro** | Financeiro: Pode mexer (chave protegida, o dono entrega). Relatórios: Só olha | Empresa toda |

Se o dono não quiser configurar times, o gerente e o supervisor ficam com "Empresa toda" ou "Só os meus". O resto funciona igual.

### 4.3 Empresa estruturada (C-levels)

O exercício que deu origem ao documento. Mostra o modelo no limite: muitas áreas, hierarquia configurada e chaves protegidas entregues pelo dono.

#### 4.3.1 Matriz de referência

**M** = pode mexer · **V** = só olha · **—** = não vê. Marketing = campanhas, Anúncios Meta, modelos do WhatsApp e kit de marca. Financeiro = financeiro, faturamento e custo de IA. Pessoas = usuários, equipes e cargos. Os números entre colchetes remetem aos ajustes da seção 4.3.2.

| Cargo | Conversas | Contatos | CRM | Marketing | IA e automações | Canais e integrações | Relatórios | Financeiro | Pessoas | Alcance |
|---|---|---|---|---|---|---|---|---|---|---|
| **CEO (dono)** | M | M | M | M | M | M | V [1] | M | M | Empresa toda |
| **CFO** | — | V [2] | V + valores [3] | V (inclui gasto de anúncio) | — | — | V | M | — | Empresa toda |
| **CMO** | V | M + exportar | V | M + disparar + conectar anúncios [4] | V [5] | — [6] | V | só gasto de anúncio | — | Empresa toda |
| **CSO** | M | M | M (funis, sem tokens) | V | — | — | V (CRM) [7] | só valor de vendas | — | Empresa toda |
| **CHRO** | — | — | — | — | — | — | V (produtividade) [8] | — | M (sem dar administrador) | Empresa toda |
| **CTO** | V | — | V | — | M | M (tokens, segurança, auditoria) | V | — | — | Empresa toda |
| **COO** | M | M | V | V | M | V + distribuição [9] | V | — | — | Empresa toda |
| **Head** | como o C-level da área | | | | | | | | | Toda a minha área |
| **Gerente** | M nas áreas dele | | | | | | V | | | Times abaixo de mim |
| **Supervisor** | M + reatribuir | | | | | | V | | | Meu time |
| **Analista / Comercial** | M nos próprios | | | | | | | | | Só os meus + fila |

#### 4.3.2 Ajustes feitos na matriz e por quê

1. **CEO, Relatórios "V" em vez de "M".** Relatório é só leitura. Não existe "mexer" em relatório.
2. **CFO, Contatos "V".** Mantido, mas dá a base inteira de clientes (nome, telefone, e-mail). Se o CFO não precisa, vira "—".
3. **CFO, CRM "V + valores".** Hoje o valor do card aparece para qualquer um com `crm_view` (`app/services/crm/cards/payload_builder.rb:4`). Só a receita dos links rastreados é só admin (`ctwa_tracked_links_controller.rb:112`). "Valores" = `sales_value_view`, só o somado em R$ (Z1, resolvida pela proposta do Multifunnel).
4. **CMO, "conectar anúncios".** Conectar a conta de anúncios grava token da Meta. Isso é `meta_ads_manage`, chave protegida: o dono entrega.
5. **CMO, IA e automações "V" em vez de "M (marketing)".** Não existe automação "só de marketing". `automation_manage` e `autonomia_manage` valem para todas as regras e todos os agentes da conta. Se o CMO receber "M", mexe também nas automações do atendimento. A automação de marketing de verdade (jornada de campanha) já está em Marketing.
6. **CMO, Canais "—".** Mantido. Montar campanha pede escolher a caixa de envio, e a tela lista só as caixas em que a pessoa é membro (`app/policies/inbox_policy.rb:13-15`). Campanhas confirmou: não dar `inbox_view`. Basta ser membro da caixa (dúvida 7.4-5).
7. **CSO, Relatórios "V (CRM)".** Não existe filtro "só vendas" em `report_manage`. Vendas = `crm_view_reports` (os 8 relatórios do CRM). Os de atendimento (`report_manage`) são opcionais.
8. **CHRO, Relatórios "V (produtividade)".** `report_manage` dá os relatórios por agente. Cuidado: o detalhamento abre a conversa por trás do número. Para o CHRO, que não vê conversas, o detalhamento tem de respeitar Conversas "—" (dúvida I).
9. **COO, "+ distribuição".** Operação precisa das regras de distribuição e capacidade, que são 18 ações só admin hoje. Entra `assignment_manage` (dúvida K, resolvida).

#### 4.3.3 Cada C-level: o que precisa e qual chave cobre

Chave protegida marcada com 🔒: só o dono entrega.

| Cargo | O que precisa | Chaves |
|---|---|---|
| **CEO (dono)** | tudo, mais as três ações do dono | papel administrador + dono **[NOVO]** |
| **CFO** | ver e pagar o contrato, ver custo de IA e valor de vendas, acompanhar marketing e relatórios | `financial_view` 🔒, `financial_manage` 🔒, `ai_cost_view` 🔒, `sales_value_view` 🔒, `crm_view`, `crm_view_reports`, `campaign_view`, `meta_ads_view`, `report_manage`, `contact_view` |
| **CMO** | marketing completo, ver tudo menos financeiro e pessoas | um cargo com as áreas marcadas (na etapa posterior, também dá para somar "Visão executiva" + "Marketing completo"): `campaign_manage`, `campaign_send`, `whatsapp_templates_manage`, `meta_ads_view`, `meta_ads_manage` 🔒, `contact_manage`, `contact_export`, `conversation_view` **[NOVO]**, `crm_view`, `report_manage`, `automation_view`, `autonomia_view` |
| **CSO** | vendas completas, funis, sem tokens | `crm_admin` (sem tokens, que vão para `token_manage`), `conversation_manage`, `contact_manage`, `campaign_view`, `crm_view_reports`, `sales_value_view` 🔒 |
| **CHRO** | convidar, desativar, montar times e cargos, ver produtividade | `user_manage` 🔒, `team_manage` 🔒, `role_manage` 🔒, `report_manage`. Proteções: não dá administrador, não dá mais do que tem, não mexe no próprio acesso |
| **CTO** | integrações, tokens, segurança, IA, auditoria | `integration_manage` 🔒, `token_manage` 🔒, `security_manage` 🔒, `audit_log_view` 🔒, `inbox_manage`, `autonomia_manage`, `automation_manage`, `conversation_view`, `crm_view`, `report_manage` |
| **COO** | atendimento e operação | `conversation_manage`, `contact_manage`, `inbox_view`, `assignment_manage` **[NOVO]**, `automation_manage`, `autonomia_manage`, `sla_manage`, `crm_view`, `campaign_view`, `report_manage` |

#### 4.3.4 Os níveis abaixo dos C-levels

Estes alcances pressupõem que a empresa configurou a hierarquia de times. Sem ela, cada um fica com "Só os meus" ou "Empresa toda".

- **Head:** recebe o cargo da área (ex.: "Marketing completo") com alcance "Toda a minha área". Não recebe chave protegida, a não ser que o dono entregue.
- **Gerente:** "Pode mexer" nas áreas dele, Relatórios "Só olha", alcance "Times abaixo de mim".
- **Supervisor:** "Pode mexer" + reatribuir conversas e cards do time, alcance "Meu time". Não entra no rodízio de conversas por estar acima do time (seção 5.7).
- **Analista / Comercial:** "Pode mexer" nos próprios registros, alcance "Só os meus + fila". É o `conversation_unassigned_manage` de hoje.

---

## 5. Catálogo proposto

### 5.1 Como ler

- **Três níveis por área:** Não vê (sem chave) · Só olha (`_view`) · Pode mexer (`_manage`, que inclui o "Só olha", `account_user.rb:12`).
- **Chave extra** só onde o estrago é de outro tamanho: disparar em massa, exportar dado pessoal, excluir, configurar o trabalho dos outros. Ela só liga junto com o "Pode mexer" da área e o inclui (`account_user.rb:13`). Na tela, aparece como **ajuste sensível dentro da área**, com confirmação (decisão 5 do #888).
- **Chave protegida 🔒:** está na lista "delegável com proteção". Segue as quatro proteções (seção 5.6).
- **Alcance é o terceiro eixo**, não chave de ação (seção 5.7).
- **Status:** *existe* = sem mudança · *nova* · *juntar* = passa a valer onde hoje não vale · *dividir* = parte sai para outra chave · *mover* = ação troca de chave.
- **Agente sem cargo:** toda chave nova mantém o que ele faz hoje. Se hoje ele não faz, a chave nova entra na lista de negadas a ele (`PLAIN_AGENT_DENIED_KEYS`, `crm_permissions.rb:19`, e `relationships/record_permissions.rb:9`). Toda chave protegida entra nessa lista.

### 5.2 Regra de compatibilidade para "dividir" e "mover"

Toda chave marcada *dividir* ou *mover* tira de cargos já salvos algo que eles fazem hoje. Isso bate com a decisão "aditivo, sem migração" (#452). Três caminhos:

- **(a)** a chave antiga continua liberando a ação; a separação vale só para cargos novos ou editados;
- **(b)** uma migração dá a chave nova a quem tinha a antiga (fere o #452);
- **(c)** aceitar a perda, porque a ação nunca deveria ter sido delegada.

Para chave protegida, o caminho (b) está proibido: daria a chave sem o dono escolher (proteção 1).

| Chave | Caminho recomendado | Por quê |
|---|---|---|
| `campaign_send` (sai de `campaign_manage`) | (a) | quem já dispara continua; cargo novo nasce separado |
| `contact_export` (sai de `contact_manage`) | (a) | idem |
| `crm_delete_cards` (sai de `crm_manage_cards`) | (a) | idem |
| tokens do CRM saem de `crm_admin` para `token_manage` 🔒 | (c) com aviso ao dono | chave protegida; (b) proibido |
| credenciais e webhooks saem de `inbox_manage` para `integration_manage` 🔒 | (c) com aviso ao dono, depois de contar em produção quantos cargos usam | idem |
| domínio de envio sai de `campaign_manage` para `account_settings_manage` 🔒 | (c) com aviso | domínio é da conta, não da campanha |
| custo de IA sai de `crm_view_reports` para `ai_cost_view` 🔒 | (c) | é financeiro da conta |
| exportar Prospecção sobe de `prospecting_view` para `prospecting_manage` | (c) | exportar em lote com só "ver" é brecha |
| credencial do portal de cotação | nada agora | a Lia fica fora das mudanças gerais |

"Com aviso ao dono" = na primeira entrada depois do deploy, o dono vê "estes cargos perderam X; quer entregar a chave nova a alguém?". **[NOVO]**

### 5.3 Catálogo por área

Chaves existentes que não mudam aparecem só no mapa (5.10). Aqui estão as áreas com mudança.

**Conversas**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `conversation_view` | ver | ler conversas e mensagens no alcance, sem responder, atribuir ou mudar status | **nova** (antes era épico separado, D6) |
| `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage` | alcance | o trio de hoje; passa a ser lido como degraus da régua (5.7) | existe |
| `conversation_message_delete` | excluir | apagar mensagem (o anexo some, o texto vira "mensagem apagada") | **nova**; agente sem cargo continua apagando |

`conversation_view` só é seguro depois do contrato de rotas (etapa 3): cada rota de escrita de conversa precisa recusar quem só lê.

**Contatos (vale para Empresas e Relacionamentos)**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `contact_view` | ver | lista, ficha, busca, filtro, notas, mídias, empresas | existe, **juntar** no servidor (#1157) |
| `contact_manage` | editar | criar, editar, notas, etiquetas, importar, juntar contatos | existe |
| `contact_export` | exportar | exportar a base | **nova**, *dividir* (a) |
| `contact_delete` | excluir | excluir contato e empresa | **nova**, negada ao agente sem cargo |

Pela decisão de 08/10 (#1157), o dado do contato continua aparecendo dentro da conversa e do card para quem não tem `contact_view`.

**CRM**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `crm_manage_cards` | editar | cards, lembretes, reuniões, assunto, fatos da memória (`memoria_fatos` usa a policy do card); **juntar** sincronizar reunião e a ação em massa (atribuir, status). Mover em massa exige `crm_move_cards`, como mover um card | existe, *juntar* |
| `crm_delete_cards` | excluir | excluir card, um ou em massa. O "excluir" em massa hoje arquiva (`archive_card!`): se arquivar fica aqui ou em `crm_manage_cards` é a dúvida 7.4-2 | **nova**, *dividir* (a) |
| `crm_view_reports` | ver | os 8 relatórios | existe; custo de IA sai para `ai_cost_view` |
| `crm_admin` | pacote | todo o CRM e a tela Caixas | existe; tokens saem para `token_manage`; proteção 3 impede editar a própria linha na tela Caixas (`gravador.rb:178-200`) |
| `crm_manage_pipelines` | configurar | funis, etapas, automações de etapa; se o Rodrigo delegar, também o catálogo de chaves da memória (#1601, hoje só admin em `memoria_chaves_controller.rb:6`) | existe |
| `sales_value_view` 🔒 | ver | só o valor **somado** em R$: totais do Kanban e do funil, receita dos links rastreados, relatórios em R$. O valor do próprio card continua visível para quem vê o card | **nova** (Z1 resolvida); nasce **ligada** para todo cargo que já tem `crm_view` (5.16) |
| `ai_cost_view` 🔒 | ver | quanto a IA gastou, com exportação | **nova** |

**Marketing (Campanhas, Anúncios Meta, Modelos, kit de marca)**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `campaign_send` | disparar | os pontos de disparo, na lista abaixo | **nova**, *dividir* (a) |
| `meta_ads_view` | ver | painel de Anúncios, números, IA do dia, mensagem sugerida (as duas últimas gastam IA, ver 5.12) | **nova** (decidida no #1158) |
| `meta_ads_manage` 🔒 | configurar | conectar (token ou login do Facebook), escolher conta, pixel, destinos, funil, resumo no WhatsApp, aceitar ou dispensar ação do consultor, desconectar | **nova** |

**Recorte do `campaign_send`** (lista do chat de Campanhas, 17/10):
- E-mail: enviar agora, agendar e retomar (`p/email_campaign_policy.rb:22-48`). Pausar e cancelar ficam em `campaign_manage`.
- Jornada: o POST que cria e já dispara (`c/campaign_journey/campaigns_controller.rb:11,83`) e retomar campanha parada (`campaign_pauses`).
- WhatsApp API: o POST cria e dispara junto, sem rascunho. Quem só tem `campaign_manage` deixaria de criar (dúvida 7.4-3).
- Campanha clássica: criar ou editar com `scheduled_at` conta como disparar.
- Conversa aberta: o POST autoriza criar campanha (`conversa_aberta_controller.rb:52`) e o envio manda o modelo.
- E-mail de teste (até 5 endereços): fica fora do disparo se a dúvida 7.4-4 for para `campaign_manage`, como recomenda Campanhas.

**Modelos do WhatsApp (regra única, confirmada pelo chat de Modelos):**
- `whatsapp_templates_view` e `whatsapp_templates_manage` valem para a tela de Modelos e para as ações dentro dela.
- "Atualizar" **continua com ver**: só relê a Meta, e já roda sozinho a cada 5 minutos.
- A tela antiga `campaigns_templates_index` (hoje só admin) entra na regra única.
- `whatsapp_api_message_template_policy` (modelos internos da caixa API, com `campaign_view` e `campaign_manage`) **fica com Campanhas**. Não unificar.
- Produto e carrossel pela conversa (#1716/#1749) ficam com quem atende a caixa, sem chave.

**Remetente de e-mail:** ver remetentes fica em `campaign_view`; cadastrar domínio vai para `account_settings_manage` 🔒 (dúvida L). Quem monta campanha sem remetente vê "peça ao administrador" (seção 6, etapa 7).

**Agendamento**

As chaves já existem (#1401; `p/crm/booking_page_policy.rb:1-2,7-22`). Não há chave nova.

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `agendamento_view` | ver | páginas de agendamento e pessoas; números e convites da equipe | existe |
| `agendamento_manage` | configurar | criar, editar, publicar, pausar página; quem atende; passar reuniões; textos de aviso; criação automática do modelo de aviso ao publicar (só com a autorização ligada) | existe |

- **Fica fora de chave:** o botão v1 "Criar os modelos na Meta" será retirado (#1612, decisão do Rodrigo). Salvar identidade visual na conta vai para `account_settings_manage` 🔒.
- **Alcance (proposta do chat de Agendamento):** reuniões, "lembrar" e "novo link" seguem o alcance do CRM pelo card, porque o card aberto manda (`crm/meetings_controller.rb:193-197`). O alcance do Agendamento vale para convites e números (time de quem criou). A página é "minha" ou "do meu time" quando todos que atendem nela estão no alcance. "Passar reuniões" (`reassigner.rb:57`) exige origem e destino no alcance. "Meus horários" é sempre "Só os meus".
- **Quem pode atender** continua sendo a elegibilidade (`host_eligibility.rb:14-19`). Quando vier a soma de cargos, ler a união (hoje lê um cargo só, `:27,34`). Se a dúvida J for aprovada, `crm_manage_cards` entra na lista de chaves que dão elegibilidade.

**IA e automações:** sem chave nova. `automation_*` e `autonomia_*` continuam.

- **Regra G (recomendada, Agentes IA de acordo):** pôr ou tirar agente de uma caixa exige ser membro da caixa ou ter `inbox_manage`, nos 4 caminhos: `channels#create` e `#destroy`, `onde_atende#update`, `quem_atende` e `Crm::Caixas::GravadorDeAgentes`. A lista de caixas mostra só as alcançáveis. O lado da caixa já pede `inbox_manage` + `autonomia_manage` (`quem_atende_controller.rb:23,26`; `crm/caixas_controller.rb:47-51`).
- **Conversas por resultado:** passam pelo filtro de conversas da pessoa (`Conversations::PermissionFilterService`) antes do limite de 50. Os totais da lista podem continuar da conta. O chat de Agentes IA se ofereceu para fazer no PR dele.
- **Ferramentas do agente (#1430):** ficam para depois, numa chave protegida 🔒, porque guardam cabeçalho secreto (`tools_controller.rb:77-83`).
- Cotação: a Lia fica fora (`insurance_manage` em `quote_agent_controller.rb`, sem mudança).

**Canais e integrações**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `inbox_view`, `inbox_manage` | ver, configurar | caixas, atendentes, robô, ligações, WAHA, híbrido | existe; credenciais saem |
| `integration_manage` 🔒 | configurar | webhooks, apps no painel, integrações (Slack, Shopify, Notion, Linear), robôs, app OAuth de e-mail, token de gestão do WhatsApp, conexão manual e reautorização do WhatsApp, pedido de acesso ao WhatsApp nuvem, feed de conversões do Google, importação de outro sistema, ferramentas personalizadas do Captain | **nova** |
| `token_manage` 🔒 | configurar | chaves que a plataforma emite: tokens de integração do CRM, token e segredo de robô, segredo da caixa API, HMAC | **nova** |

Regra simples para separar as duas: `integration_manage` liga a conta a sistemas de fora (inclusive colando credencial de terceiro). `token_manage` cria a chave que dá a um sistema de fora acesso à nossa API.

**WhatsApp Híbrido e WAHA (confirmado pelo chat do Híbrido):** criar caixa WAHA, QR, reconectar e a conexão híbrida ficam em `inbox_manage`. Reação e edição de mensagem (#1709) são da conversa. A caixa WAHA usa o token de quem a criou: remover essa pessoa para o conector (aviso na seção 6, etapa 7).

**Relatórios:** `report_manage` existe e ganha o detalhamento, que passa a respeitar o alcance de Conversas (dúvida I).

**Financeiro**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `financial_view` 🔒 | ver | resumo da cobrança, pacotes de créditos, assinatura Autonom.ia, prévia, faturas, pagamentos | **nova** |
| `financial_manage` 🔒 | mexer | comprar créditos; ligar a autorização para o sistema criar modelos com custo na Meta (dúvida X) | **nova** |

"Financeiro" e "faturamento" viraram uma área só. Para o cliente, os dois são "o que pagamos à plataforma" (`au/financial_controller.rb` e `account_policy.rb:22-44`). O Financeiro da Autonom.ia hoje só tem leitura (4 rotas GET, `config/routes.rb:609-614`). Mudar plano, moeda e forma de pagamento fica com o dono.

**Pessoas**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `user_manage` 🔒 | mexer | convidar (uma ou várias), editar, desativar e remover pessoa; nunca dar papel de administrador | **nova** |
| `team_manage` 🔒 | mexer | criar, editar, excluir times, membros, líderes e time-pai | **nova** |
| `role_manage` 🔒 | mexer | ver, criar, editar, excluir e atribuir cargos | **nova** |

**Operação e conta**

| Chave | Tipo | O que cobre | Status |
|---|---|---|---|
| `assignment_manage` | configurar | regras de distribuição e capacidade (18 ações) | **nova**, comum |
| `account_settings_manage` 🔒 | configurar | dados da conta, layout de e-mail com marca, primeiros passos, preferências de IA, identidade visual da conta, domínio de envio de e-mail, Vigias, avisos e pendências do Guia, telas Fluxo de conversa e Modelos | **nova** |
| `security_manage` 🔒 | configurar | login único (SAML), reputação de envio de e-mail | **nova** |
| `audit_log_view` 🔒 | ver | histórico de auditoria | **nova** |

[HIPÓTESE] Vigias, avisos e pendências do Guia estavam no "nunca delegar" antigo. Pus em configurações da conta por serem ajustes do Guia para a empresa. Conferir com o chat do Guia.

### 5.4 As 21 chaves novas

| # | Chave | Área | 🔒 Protegida |
|---|---|---|---|
| 1 | `meta_ads_view` | Marketing | não |
| 2 | `campaign_send` | Marketing | não |
| 3 | `contact_export` | Contatos | não |
| 4 | `contact_delete` | Contatos | não |
| 5 | `crm_delete_cards` | CRM | não |
| 6 | `conversation_message_delete` | Conversas | não |
| 7 | `conversation_view` | Conversas | não |
| 8 | `assignment_manage` | Operação | não |
| 9 | `meta_ads_manage` | Marketing | sim |
| 10 | `sales_value_view` | CRM / Financeiro | sim |
| 11 | `ai_cost_view` | Financeiro | sim |
| 12 | `financial_view` | Financeiro | sim |
| 13 | `financial_manage` | Financeiro | sim |
| 14 | `user_manage` | Pessoas | sim |
| 15 | `team_manage` | Pessoas | sim |
| 16 | `role_manage` | Pessoas | sim |
| 17 | `integration_manage` | Canais e integrações | sim |
| 18 | `token_manage` | Canais e integrações | sim |
| 19 | `security_manage` | Conta | sim |
| 20 | `audit_log_view` | Conta | sim |
| 21 | `account_settings_manage` | Conta | sim |

As 6 primeiras são as da versão anterior. Com elas, o catálogo vai de 38 para **59 chaves**. Para o leigo, a tela continua com três níveis por área. As chaves extras aparecem como ajuste sensível, e as protegidas só aparecem para o dono.

O pedido era "cerca de 15". Deram 21 porque cada área pedida virou ver e mexer onde as duas ações existem, e porque surgiram `meta_ads_manage` (o CMO conectar anúncios) e `assignment_manage` (o COO). Onde dá para cortar está na dúvida Y.

### 5.5 Só o dono

| O que | Hoje | Prova |
|---|---|---|
| pedir exclusão da conta | só admin | `p/account_policy.rb:34-36` |
| transferir a conta | não existe | **[NOVO]** |
| iniciar assinatura (plano) | só admin | `p/account_policy.rb:22-24` |
| escolher moeda do contrato | só admin | `p/account_policy.rb:26-28` |
| abrir portal de pagamento (plano e forma de pagamento) | só admin | `p/account_policy.rb:30-32` |
| tornar alguém administrador (convite ou edição) | só admin | `p/user_policy.rb:6-12`; `app/models/account_user.rb:36` |

**Quem é o dono [NOVO].** Hoje não há dono, só `role` agent ou administrator. Proposta: tabela do fork `account_owners` (account_id, user_id), sem coluna em tabela do Chatwoot. O dono é sempre administrador. Para as contas que já existem, alguém precisa ser marcado dono (dúvida Z2). Dois sócios: dúvida U.

O dono é o único que vê e entrega as chaves protegidas. O administrador que não é dono continua fazendo tudo o que faz hoje, menos as ações desta tabela. [HIPÓTESE] Isso tira do administrador comum as três ações do contrato e a promoção a administrador, que hoje ele tem. É uma perda real para contas com vários administradores (dúvida Z2).

### 5.6 Delegável com proteção

A lista: `user_manage`, `team_manage`, `role_manage`, `financial_view`, `financial_manage`, `ai_cost_view`, `sales_value_view`, `integration_manage`, `token_manage`, `security_manage`, `audit_log_view`, `account_settings_manage`, `meta_ads_manage`.

Como cada proteção vira regra de servidor **[NOVO]**:

1. **Só o dono entrega.** Pôr chave protegida num cargo, ou dar a alguém um cargo que tenha chave protegida, exige ser dono. Quem tem `role_manage` vê esses cargos, mas não os atribui.
2. **Ninguém dá mais do que tem, nem administrador.** Ao criar ou editar cargo, ou ao atribuir, o servidor confere que as chaves e o alcance do cargo estão contidos nos de quem está dando. Papel de administrador só o dono dá. Ver a dúvida S: aplicada ao pé da letra, essa regra impede o CHRO de montar o cargo de um vendedor.
3. **Ninguém mexe no próprio acesso.** Recusar no servidor: editar o próprio cargo, atribuir cargo a si, mudar o próprio papel, gravar a própria linha na tela Caixas (`gravador.rb:248-252` hoje não impede), pôr a si como líder de time.
4. **Tudo no histórico.** Toda mudança de cargo, de chave, de papel, de time-pai, de líder e de dono fica no histórico de auditoria. Hoje `custom_role_id` e as chaves não ficam registrados (`enterprise/app/models/enterprise/audit/account_user.rb:5-11`).

### 5.7 Alcance: a régua e a hierarquia opcional

**A régua, do menor para o maior:**

| Degrau | Vê os registros de | Aparece quando |
|---|---|---|
| Só os meus | quem é atribuído, dono ou participante. Com "+ fila", também os sem dono | sempre |
| Meu time | todos os times em que a pessoa é membro ou líder | a empresa configurou time-pai na tela de Equipes |
| Times abaixo de mim | o meu time e todos os times-filhos, em qualquer profundidade | idem |
| Toda a minha área | todos os times da mesma área (dúvida V) | idem, e há área definida |
| Empresa toda | tudo, ainda cortado por caixa e funil | sempre |

**Sem hierarquia configurada,** a tela mostra só "Só os meus" e "Empresa toda". Em Conversas, continuam as opções que já existem: as dela e as da fila (o trio `conversation_*`). Ninguém precisa montar organograma. A empresa pequena usa cargos sem nunca abrir a tela de Equipes.

**Se a empresa tirar a hierarquia depois,** o cargo que usava "Meu time" ou acima não pode ganhar "Empresa toda" em silêncio. [NOVO] Ele cai para "Só os meus" e o administrador vê o aviso "caiu para Só os meus", com a ação "Escolher de novo". Segue o princípio 10.

**Três "só os meus" diferentes:** o alcance do cargo, o `only_own` do funil e o `assigned_only` da caixa. Ver a dúvida 7.4-1.

**Hierarquia de times [NOVO], opcional:**
- `team_parents` (account_id, team_id, parent_team_id): o time-pai. Tabela do fork, sem coluna em `teams`.
- `team_leaders` (account_id, team_id, user_id): o gestor do time. **Não** é membro do time, para não entrar no rodízio de conversas (`assignment_handler.rb:21-28`; `auto_assignment_handler.rb:42-53`).
- Configurado na tela de Equipes que já existe: dois campos novos, "Time acima" e "Quem lidera". Sem página nova.

**Onde a régua vale (primeira versão):**

| Área | Como o registro entra num time |
|---|---|
| Conversas | `team_id` da conversa (já existe no Chatwoot) ou o time do atendente (dúvida W) |
| CRM | time do dono do card ou do atendente da conversa principal. Sem coluna `team_id` no card (decisão do Multifunnel) |
| Agendamento | reuniões, "lembrar" e "novo link" seguem o CRM pelo card; convites e números, pelo time de quem criou; "Meus horários" sempre "Só os meus" (proposta do chat de Agendamento, seção 5.3) |
| Prospecção | time de quem criou a busca [HIPÓTESE] |
| Relatórios | filtro por time e agente, que já existe nos números ao vivo (`c2/live_reports_controller.rb`) |
| Contatos, Campanhas, Marketing | só "Empresa toda" nesta versão: contato e campanha não têm dono hoje |

**Como guardar o alcance [NOVO]:** tabela do fork `custom_role_reaches` (custom_role_id, area, reach). A alternativa sem tabela é uma string por degrau na lista de chaves (como o trio `conversation_*`), mas isso multiplica as chaves por cinco. O trio de hoje continua valendo e é lido como degrau de Conversas: `conversation_manage` = Empresa toda (nas caixas da pessoa), `conversation_unassigned_manage` = Só os meus + fila, `conversation_participating_manage` = Só os meus.

### 5.8 Mais de um cargo por pessoa (etapa posterior)

Perdeu prioridade. Um cargo com várias áreas marcadas resolve o caso comum: a pessoa de marketing que vende recebe um cargo com Marketing e CRM. Somar cargos é útil para empresa grande, que quer manter "Visão executiva" separada de "Marketing completo" e combinar os dois. Fica para depois da tela nova e não é pré-requisito de nenhuma etapa. Quando vier:

- **[NOVO]** tabela do fork `account_user_roles` (account_user_id, custom_role_id). O campo `account_users.custom_role_id` continua como está, para não quebrar nada, e entra na soma.
- **Chaves:** união de todos os cargos.
- **Alcance:** em cada área, o maior entre os cargos.
- **Exemplo do CMO:** "Visão executiva" (Só olha em tudo, menos Financeiro e Pessoas, alcance Empresa toda) + "Marketing completo" (Pode mexer em Marketing e Contatos, com disparar e exportar). Resultado: vê tudo, mexe no marketing.
- **Proteções:** a soma não pode virar atalho. Se a união de dois cargos tem chave protegida, a regra 1 já pegou na hora de atribuir cada um.

### 5.9 Cargos prontos: só atalho

Cargo pronto não é cargo fixo. É um atalho para não começar do zero:

- escolher um atalho já traz áreas, nível e alcance marcados;
- o administrador desmarca ou soma qualquer área antes de salvar, e troca o nome;
- "Montar eu" fica sempre disponível e começa do zero;
- mudar um atalho não altera cargo já salvo.

Os atalhos abaixo combinam **área + nível**. Também cabem atalhos de empresa pequena, como "Marketing e Vendas" (Marketing e CRM "Pode mexer"). A lista final sai do mockup.

**Sem hierarquia configurada,** o atalho que usa "Meu time" ou acima chega sem alcance marcado. A tela pede para escolher entre "Só os meus" e "Empresa toda". Nunca marca "Empresa toda" sozinha.

**Por área (o que abre):**

| Área | Pode mexer | Só olha | Chaves protegidas (só com o dono) |
|---|---|---|---|
| Executivo | — | tudo, menos Financeiro e Pessoas | nenhuma |
| Financeiro | Financeiro | CRM com valores, Marketing, Relatórios, Contatos | `financial_*`, `ai_cost_view`, `sales_value_view` |
| Marketing | Marketing, Contatos (+ exportar, + disparar) | Conversas, CRM, Relatórios, IA | `meta_ads_manage` |
| Vendas | CRM, Conversas, Contatos | Marketing, relatórios do CRM | `sales_value_view` |
| Pessoas | Pessoas | Relatórios de atendimento | `user_manage`, `team_manage`, `role_manage` |
| Tecnologia | IA e automações, Canais e integrações | Conversas, CRM, Relatórios | `integration_manage`, `token_manage`, `security_manage`, `audit_log_view` |
| Operações | Conversas, Contatos, IA e automações, distribuição | CRM, Marketing, Canais, Relatórios | nenhuma |

**Por nível (até onde vai):**

| Nível | Nível na área | Alcance | Ações delicadas |
|---|---|---|---|
| C-level / Head | como a área | Toda a minha área (C-level: Empresa toda) | as da área, desligadas até o dono ligar |
| Gerente | Pode mexer | Times abaixo de mim | exportar e excluir desligados |
| Supervisor | Pode mexer + reatribuir | Meu time | desligadas |
| Analista / Comercial | Pode mexer | Só os meus + fila | desligadas |

Exemplo: área Vendas + nível Gerente = "Gerente de Vendas": CRM, Conversas e Contatos "Pode mexer", relatórios do CRM "Só olha", alcance Times abaixo de mim, com os valores de venda e as metas da equipe (decisão do Rodrigo em 23/10, #2115: sem eles o gerente não acompanha quanto o time vende nem a meta). As duas chaves são protegidas: só quem pode entregá-las aplica o perfil completo; para os outros, a tela avisa que ficaram de fora.

Os 8 perfis de hoje (`permissionMatrix.js:436-507`) viram atalhos, já corrigidos (Atendente com fila; SDR sem "Liberar Campanhas"). Em 23/10 (#2115) cada atalho passou a entregar o que a frase dele promete: Marketing dispara campanhas e exporta contatos, Atendente pega da fila, Gestor comercial vê valores e define metas, Somente leitura vê também Anúncios, Agendamento e Cotação, e Operações deixa de prometer reconectar o WhatsApp (credencial fica com o administrador). Chave protegida que quem aplica não pode entregar sai do atalho com aviso, na prévia e no editor.

### 5.10 Mapa das 38 chaves atuais

Nenhuma muda de nome (decisão #452).

| Chave atual | Destino |
|---|---|
| conversation_manage, conversation_unassigned_manage, conversation_participating_manage | mantém; lidas como degraus da régua de Conversas |
| contact_view | mantém + passa a valer no servidor |
| contact_manage | mantém; exportar vai para `contact_export` (a) |
| report_manage | mantém; ganha o detalhamento, que respeita o alcance |
| knowledge_base_view, knowledge_base_manage | mantém |
| crm_view, crm_move_cards, crm_manage_pipelines, crm_manage_ai, crm_export | mantém |
| crm_view_reports | mantém; custo de IA sai para `ai_cost_view` 🔒 (c) |
| crm_manage_cards | mantém; ganha sync, remind e massa; excluir vai para `crm_delete_cards` (a) |
| crm_admin | mantém; tokens saem para `token_manage` 🔒 (c); não edita a própria linha (proteção 3) |
| autonomia_view, autonomia_manage | mantém |
| campaign_view | mantém |
| campaign_manage | mantém; disparo vai para `campaign_send` (a); domínio de envio vai para `account_settings_manage` 🔒 (c) |
| inbox_view | mantém |
| inbox_manage | mantém; credenciais e webhooks vão para `integration_manage` 🔒 (c) |
| canned_response_manage, label_manage, attribute_manage, macro_manage | mantém |
| sla_manage | mantém; pode ganhar os calendários de SLA, mantendo `crm_admin` (dúvida 7.4-8) |
| prospecting_view | mantém; exportar sai (c) |
| prospecting_manage, prospecting_view_all_searches | mantém |
| insurance_view, insurance_manage | mantém (Lia fora das mudanças gerais) |
| automation_view, automation_manage | mantém |
| agendamento_view, agendamento_manage | mantém; agora área explícita no catálogo (5.3) |
| whatsapp_templates_view, whatsapp_templates_manage | mantém; regra única para a tela de Modelos, inclusive a tela antiga `campaigns_templates_index`; "Atualizar" continua com ver |

### 5.11 Ações que hoje não têm chave e ganham uma

| Ação | Hoje | Proposta |
|---|---|---|
| Ler contatos e empresas | qualquer membro | `contact_view` (#1157) |
| Apagar mensagem | quem vê a conversa | `conversation_message_delete` para quem tem cargo |
| Ler conversa sem operar | não existe | `conversation_view` |
| Excluir contato e empresa | só admin | `contact_delete` |
| Card em massa (excluir/arquivar, atribuir, mover) | `crm_view` | `crm_delete_cards` ou `crm_manage_cards` (dúvida 7.4-2) / `crm_manage_cards` / `crm_move_cards` |
| Sincronizar e lembrar reunião | `crm_view` + funil | `crm_manage_cards`, no alcance do CRM pelo card |
| Exportar busca e lista da Prospecção | `prospecting_view` | `prospecting_manage` |
| Painel e conexão de Anúncios Meta | só admin | `meta_ads_view` / `meta_ads_manage` 🔒 |
| Catálogo de chaves da memória (#1601) | só admin | `crm_manage_pipelines` (ou `crm_admin`), se o Rodrigo delegar |
| Valor somado de vendas em R$ | `crm_view` (totais) ou só admin (receita dos links) | `sales_value_view` 🔒 |
| Calendários de atendimento | administrador ou `crm_admin` (tela e API, desde o #1618) | + `sla_manage`, mantendo `crm_admin` (dúvida 7.4-8) |
| Detalhamento dos relatórios | só admin | `report_manage`, respeitando o alcance |
| Regras de distribuição e capacidade | só admin | `assignment_manage` |
| Pessoas, times, cargos | só admin | `user_manage` / `team_manage` / `role_manage` 🔒 |
| Financeiro e faturamento | só admin | `financial_view` / `financial_manage` 🔒 |
| Integrações, webhooks, robôs, importação | só admin | `integration_manage` 🔒 |
| Tokens e segredos | só admin ou `crm_admin` | `token_manage` 🔒 |
| SAML, reputação de e-mail | só admin | `security_manage` 🔒 |
| Histórico de auditoria | só admin | `audit_log_view` 🔒 |
| Dados, layout e primeiros passos da conta | só admin | `account_settings_manage` 🔒 |

**Ficam abertas de propósito:** ver etiquetas, respostas prontas, macros, SLA, atributos, lista de pessoas e times, catálogo de integrações e apps no painel, robôs (só leitura), limites da conta, nomes de campanha.

### 5.12 "Ver" que gera efeito (registro, sem chave nova)

- "Atualizar" a lista de modelos sincroniza com a Meta com só `whatsapp_templates_view` (`whatsapp_templates_controller.rb:11,73-75`).
- Sugestão de local da Prospecção chama o Google (custo) com só `prospecting_view` (`searches_controller.rb:21,32`).
- Testar agente no playground gasta IA com só `autonomia_view` (decidido no #452, decisão 4).
- Ver saúde da conexão grava estado (`inbox_health_management.rb:5`).
- IA do dia e mensagem sugerida dos Anúncios Meta gastam IA com só `meta_ads_view` (`crm/meta_ads_ai_controller.rb:15,77-80`). Apontado pelo chat de Campanhas.

### 5.13 Brechas sem checagem ou fora da regra (só fato, ficam para o épico)

- `whatsapp/authorization` sem `inbox_id`: qualquer membro cria caixa WhatsApp (`whatsapp/authorizations_controller.rb:2-4,22-27`).
- Os três callbacks do Facebook; `reauthorize_page` troca o token da página de qualquer caixa (`callbacks_controller.rb:45-57`).
- `shopify/auth` (`shopify_controller.rb:4-8`).
- Status da IA do e-mail (`email_campaigns/ai_controller.rb:33-37`).
- `direct_uploads` não confere a conversa (`direct_uploads_controller.rb:15-21`).
- Copiloto do Captain com `conversation_id` sem conferir acesso (`copilot_threads_controller.rb:16-31`; `copilot_messages_controller.rb:13-19`).
- Ação em massa nos cards com só `crm_view` (`cards/bulk_controller.rb:7`; `bulk_action.rb:45-49`).
- Rodar macro em conversas que a pessoa não vê (`macros_controller.rb:50-54`).
- Linear acha a conversa na conta sem conferir se a pessoa a vê (`linear_controller.rb:109-111`).
- Conversas por resultado do agente de IA com `autonomia_view`: só confere a conta e mostra até 50 conversas de caixas alheias (`au/agents/analytics_controller.rb:15-33`; `app/services/autonomia/agents/analytics.rb:61-70`). Correção: `Conversations::PermissionFilterService` antes do limite.
- Caixa da campanha: o servidor aceita caixa em que a pessoa não é membro, nos 4 pontos de criação (seção 2.7).
- Agentes de IA ligados a qualquer caixa com só `autonomia_manage` (`channels_controller.rb:43-44`; `onde_atende_controller.rb:65,73`). Regra G.
- `crm_admin` pode se dar "Todos os funis" na tela Caixas (`gravador.rb:178-200`; `caixas_controller.rb:69`). A proteção 3 fecha.
- Agente de cotação nasce com só `insurance_manage` (`quote_agent_controller.rb:15-17`). Registrar sem mexer.
- Origem do contato mostra os públicos sem filtrar por `campaign_view` (`contact_origins_controller.rb:10`).

### 5.14 Lacunas não conferidas

- **Valor de vendas:** resolvido pela proposta do Multifunnel (Z1). O valor do card continua no payload (`payload_builder.rb:4`); `sales_value_view` cobre só o somado em R$.
- **Busca geral:** não conferi se aplica o acesso por funil nem `contact_view` (`search_service.rb:160`).
- **"Aceitar" do consultor de Anúncios:** não conferi se muda algo na Meta. Por isso foi para `meta_ads_manage`.
- **Rotas novas desde o inventário:** `conversa_canal/*` (#1702) ainda não está na seção 2. As de `inboxes/:id/whatsapp_conversation_assets/*` (#1716) entraram na 2.6.

### 5.15 Pendências do próprio conceito (para o épico)

1. **Excluir cargo amplia acesso.** Quem perde o cargo vira agente padrão e vê mais (`custom_role.rb:53`).
2. **Editar pessoa sem o campo do cargo apaga o cargo** (`enterprise/.../agents_controller.rb:23`).
3. **No CRM, editar não implica ver** (`crm_permissions.rb:29`). Dúvida J.
4. **Cargo de token aparece na lista e pode ser editado** (`crm/integration_token.rb:97-101`). Com `role_manage` delegado, isso piora: precisa esconder antes de entregar `role_manage` (etapa 3).

### 5.16 Regras de compatibilidade (pedidas pelos chats na etapa 2)

1. **Todo cargo que já existe nasce com CRM em "Empresa toda (nas caixas e funis dela)".** Hoje o cargo vê todos os cards das caixas em que a pessoa é membro (`app/services/crm/cards/visible_scope_query.rb:26-27`, `all_inbox_cards`). Se nascesse em "Só os meus", vendedores perderiam cards no dia do deploy. Apontado pelo Multifunnel como crítico.
2. **Spec "nada muda sem mexer no cargo".** Um request spec prova que, depois do deploy, cada cargo salvo vê e faz o mesmo que antes, até alguém editá-lo.
3. **Chave que divide uma atual nasce ligada para quem tem a atual.** É o caminho (a) da seção 5.2. Vale também para `sales_value_view`, que nasce ligada para quem tem `crm_view`: é a única protegida com essa exceção, porque só mantém os totais que esses cargos já veem hoje. A receita dos links rastreados, hoje só admin, não vem junto.
4. **Nenhuma chave protegida 🔒 antes do merge do PR #1783.** É ele que põe a regra das duas listas no `CLAUDE.md` e no `AGENTS.md`.

---

## 6. Plano em etapas

Ordem aprovada pelo Rodrigo em 17/10. Cada etapa abre uma Issue por PR, com `Refs` ao épico. Todo PR que toque rota ou menu roda `pnpm guia:build`. Todo PR que toque controller roda `autonomia:guia:formatos`.

A regra das duas listas ("só o dono" e "delegável com proteção") já está no PR #1783 (Issue #1782), no `CLAUDE.md` e no `AGENTS.md`, aguardando merge.

**Etapa 1. Inventário.** Feito: seções 2 e 3 deste documento.

**Etapa 2. Conversar com os chats donos de módulo sobre o modelo.** Concluída em 17/10 (seção 8).

**Etapa 3. Criar as chaves e fazer o servidor respeitá-las, com as proteções e o histórico de auditoria.** As brechas de cada área se fecham aqui, junto com a chave da área. Cada PR traz um request spec que reproduz a brecha antes de corrigir.

**Em lotes, um por vez** (pedido da Orquestração). Antes de cada lote, a lista de arquivos vai para a Orquestração e para o chat dono do módulo. O próximo lote só começa depois do anterior no ar. Cada chave nova segue o checklist do `CLAUDE.md` (`CustomRole::PERMISSIONS`, policy ou controller, `permissionMatrix.js`, i18n `CUSTOM_ROLE.MATRIX` em en e pt_BR, `meta.permissions` da rota, menu e `useCanManage`). Cada lote regera o Guia (`pnpm guia:build`) e os formatos (`autonomia:guia:formatos`). As regras da seção 5.16 valem em todos os lotes. Avisar os chats donos antes de mexer em `whatsapp_template_policy`, `whatsapp_template_consents_controller` ou `ConversationAssetsPolicy` (Modelos).
- 3.1 `CustomRole::Catalog` **[NOVO]**: para cada chave, área, nível, implicações, se é protegida, se é de empresa maior (dúvida Y), flag da conta e o que o agente sem cargo recebe. Já nasce com o eixo de alcance, mesmo que só Conversas use no começo.
- 3.2 `effective_permissions` no payload do usuário; o front para de recalcular.
- 3.3 policies migradas para o catálogo, com specs de caracterização antes.
- 3.4 `Conversations::AccessScope` **[NOVO]**: caixa + cargo + alcance, chamando o `ConversationScope` do funil sem reimplementar.
- 3.5 `config/permission_contract.yml` + spec + `verify_authorized`. Rota nova sem decisão quebra a CI.
- 3.6 dono da conta (`account_owners` **[NOVO]**) e as 5 ações "só o dono".
- 3.7 as 21 chaves novas, área por área. As 13 protegidas já com as quatro proteções no servidor.
- 3.8 histórico de auditoria obrigatório (cargo, chaves, papel, dono, time-pai, líder).
- 3.9 ciclo de vida: cargos de token escondidos, excluir cargo com destino, PATCH só mexe se o campo vier, cargo da mesma conta, nome único.
- 3.10 aviso ao dono sobre o que saiu de cargos antigos (caminho c).
- Brechas que fecham junto com a área (mesma lista do diagnóstico, seção 6): busca pelo filtro de função · CRM respeita `conversation_*` · massa no CRM por card · Facebook e Linear · PATCH de agente · leitura de contatos · tempo real · custo de IA. Também as da seção 5.13.

**Etapa 4. Alcance e hierarquia opcional.**
- 4.1 `custom_role_reaches` **[NOVO]**: "Só os meus" e "Empresa toda" em Conversas e CRM. Isso funciona sem nenhum time configurado.
- 4.2 `team_parents` e `team_leaders` **[NOVO]**, na tela de Equipes que já existe. Só quem configura ganha "Meu time", "Times abaixo de mim" e "Toda a minha área".
- 4.3 régua em Agendamento, Prospecção e Relatórios.

**Etapa 5. Cargos prontos como atalho.** Os 8 perfis de hoje viram atalhos corrigidos, mais os de empresa pequena (seção 5.9). Escolher um atalho só marca; o administrador desmarca ou soma. "Montar eu" sempre disponível.

**Etapa 6. Mockup navegável**, no painel local do M2, com os atalhos, a régua de alcance (com e sem hierarquia) e as telas de pessoas. Os três exemplos da seção 4 viram roteiros do mockup. Aprovado pelo Rodrigo, junto com o Multifunnel, **antes de codar**.

**Etapa 7. Tela nova com as regras de UI/UX para leigo** (flag nova ligada nas contas 1, 16 e 18 da stack hub2you)
- uma pergunta por tela;
- sem `<select>` nativo: `ChoiceSelect` e alvo de toque de 44 px;
- áreas e nível montam o cargo; ajustes sensíveis à parte; chaves de empresa maior em "Mais opções"; chaves protegidas só aparecem para o dono;
- passo "quem usa e onde" absorve a #1149 (D2 do diagnóstico);
- excluir com destino; `guia:build`, `porques.md` e `autonomia:guia:formatos`;
- manter o esqueleto do `CustomRoleEditor` (já está no padrão novo);
- a régua de alcance mostra só as opções que existem: sem hierarquia, não aparece "Meu time" em cinza;
- aviso "caiu para Só os meus", com a ação "Escolher de novo";
- aviso na tela de cargos: "trocar o cargo pode pausar páginas de agendamento" (quem deixa de poder atender sai das páginas);
- aviso ao remover usuário: "esta pessoa criou a caixa WAHA X; remover para o conector";
- quem monta campanha de e-mail sem remetente vê "peça ao administrador";
- `meta.permissions` continua nas rotas, porque é a fonte do Guia;
- menu: grupo sem nenhum item visível some; item não pisca (fica escondido até a permissão chegar); avisar antes a sessão "Reorganização do sidebar", dona do menu;
- tela de Equipes: campos novos em `components-next`, com `ChoiceSelect` para "Time acima" e "Quem lidera". Forma depende da dúvida 7.4-7. Chamar o chat de Frontend no mockup (etapa 6).

**Depois (não é pré-requisito de nenhuma etapa):**
- mais de um cargo por pessoa (`account_user_roles` **[NOVO]**, seção 5.8), útil para empresa grande;
- Modelos WhatsApp unificados (#726);
- telas só-admin de e-mail e agendamento;
- `autonomia_tools_manage` (#1430), num PR que mude `CLAUDE.md` e `AGENTS.md` juntos.

---

## 7. Dúvidas para o Rodrigo

### 7.1 Resolvidas pelo novo modelo

| Dúvida | Como ficou |
|---|---|
| **A. Exportar planilha** | resolvida: `contact_export` fica (uma das 6 mantidas). Prospecção sobe para `prospecting_manage` (c). Campanhas fica em `campaign_manage` |
| **B. Disparar separado de montar** | resolvida: `campaign_send` fica, caminho (a) |
| **C. Excluir à parte** | resolvida: `contact_delete`, `crm_delete_cards`, `conversation_message_delete`. Excluir conversa continua só admin |
| **D. crm_admin e tokens** | resolvida: tokens vão para `token_manage` 🔒; a proteção 3 impede editar a própria linha na tela Caixas |
| **E. Credenciais em inbox_manage** | resolvida: credenciais e webhooks vão para `integration_manage` 🔒. O híbrido fica em `inbox_manage` (não é credencial) |
| **F. Custo de IA** | resolvida: `ai_cost_view` 🔒 |
| **K. Regras de distribuição** | resolvida: `assignment_manage`, chave comum, para o COO |
| **L. Domínio de envio de e-mail** | resolvida: vai para `account_settings_manage` 🔒. O CMO pede ao dono ou ao CTO |
| **O. O que entra em meta_ads_view** | resolvida: painel, IA do dia e mensagem sugerida em `meta_ads_view`; conexão e consultor em `meta_ads_manage` 🔒 |
| **D3 do diagnóstico. Hierarquia** | resolvida: entra como opcional, com vários níveis via time-pai (etapa 4). Sem ela, o alcance tem só "Só os meus" e "Empresa toda" |
| **D6 do diagnóstico. conversation_view** | resolvida: entra no catálogo, etapa 3 (é peça de empresa maior, ver dúvida Y) |
| **Z1. Valor de vendas** | resolvida pela proposta do Multifunnel (17/10): `sales_value_view` cobre só o valor somado em R$ (totais do Kanban e do funil, receita dos links, relatórios em R$). O valor do próprio card continua visível. Nasce ligada para quem tem `crm_view`. A decisão final é do Rodrigo |

### 7.2 Continuam abertas

**G. Pôr agente de IA numa caixa**
- Contexto: `autonomia_manage` liga a IA em qualquer caixa da conta, sem ser membro e sem `inbox_manage`.
- Opções: (1) exigir também `inbox_manage` ou ser membro; (2) manter.
- Recomendação: (1). O cargo não escolhe caixa. O chat de Agentes IA concorda e detalhou os 4 caminhos e a lista filtrada (seção 5.3).

**H. Credencial do portal de cotação**
- Contexto: `insurance_manage` grava login e senha do portal. A Lia fica fora das mudanças gerais.
- Opções: (1) passar para `integration_manage` no épico; (2) manter.
- Recomendação: decidir com o dono da Lia. Pelo novo modelo, o lugar natural é `integration_manage`.

**I. Detalhamento dos relatórios**
- Contexto: quem tem `report_manage` abre os relatórios e toma 401 ao clicar num número. O detalhamento abre conversas.
- Opções: (1) detalhamento em `report_manage`, só das conversas no alcance da pessoa; (2) detalhamento só com o administrador.
- Recomendação: (1). O CHRO vê os números de produtividade, mas o detalhamento sai vazio para quem não vê conversas.

**J. Editar implica ver no CRM**
- Opções: (1) alinhar com o resto; (2) manter a exceção.
- Recomendação: (1). Multifunnel: de acordo. Se aprovada, `crm_manage_cards` passa a dar elegibilidade no Agendamento. A decisão final é do Rodrigo.

**M. contact_view no servidor e seletores**
- Opções: (1) fechar o módulo e liberar busca mínima para quem atende; (2) fechar tudo.
- Recomendação: (1).

**N. Histórico da conversa por e-mail livre**
- Opções: (1) `conversation_transcript`; (2) manter.
- Recomendação: (2). Dado no chat é do negócio.

**P. Compatibilidade das chaves divididas**
- Contexto: seção 5.2.
- Recomendação: (a) para disparo, exportar contatos e excluir card; (c) com aviso ao dono para tudo o que vira chave protegida.

**Q. Ligar contato a uma caixa**
- Opções: (1) manter (basta ser membro); (2) exigir `contact_manage`.
- Recomendação: (1).

**R. Quem perde o cargo**
- Contexto: excluir cargo ou editar pessoa sem o campo do cargo devolve a pessoa a agente padrão, que vê mais. Quando vier a soma de cargos (etapa posterior), perder um deles só tira as chaves dele.
- Opções: (1) quem fica sem nenhum cargo fica sem acesso até alguém escolher; (2) vira agente padrão com aviso na tela; (3) manter.
- Recomendação: (2), e corrigir o campo vazio de `agents_controller.rb:23`.

### 7.3 Novas

**S. "Não dar mais do que tem" trava o CHRO**
- Contexto: o CHRO não tem CRM. Ao pé da letra, a proteção 2 o impede de criar ou atribuir o cargo "Comercial", que tem CRM.
- Opções: (1) a proteção 2 vale só para chaves protegidas e papel de administrador; chaves comuns, quem tem `role_manage` dá livremente; (2) vale para tudo: o CHRO só atribui cargos que o dono montou; (3) vale para tudo, sem exceção.
- Recomendação: (2). O dono (ou quem tem as chaves) monta os cargos uma vez. O CHRO atribui qualquer cargo sem chave protegida, mas só cria ou edita cargos dentro do que ele tem. É o meio-termo que mantém a regra e deixa o CHRO trabalhar.

**T. O CHRO pode desativar um C-level?**
- Contexto: `user_manage` desativa pessoas. Sem trava, o CHRO desativa o CFO ou o CTO.
- Opções: (1) quem tem chave protegida só o dono desativa; (2) o CHRO desativa qualquer um menos o dono e administradores; (3) qualquer um, menos a si.
- Recomendação: (1). Segue a proteção 1: se só o dono entrega, só o dono tira. Ninguém mexe no dono.

**U. Dois sócios: quem é o dono?**
- Contexto: empresas com dois sócios querem os dois com poder total.
- Opções: (1) um só dono, o outro administrador; (2) vários donos (a tabela permite), qualquer um faz as ações do dono; (3) vários donos, e as ações "só o dono" pedem os dois.
- Recomendação: (2), com teto pequeno (ex.: 3) e tudo no histórico. (3) é seguro, mas trava a operação.

**V. "Toda a minha área" depende de mapear time → área**
- Contexto: o degrau "área" precisa saber de qual área cada time é.
- Opções: (1) área = o time do topo da árvore (ex.: "Vendas" com filhos "SDR" e "Closers"); (2) campo "área" no time, numa lista fixa (Executivo, Financeiro, Marketing...) **[NOVO]**.
- Recomendação: (1). Não cria lista nova e sai de graça da hierarquia.

**W. Conversa entra no time por qual regra?**
- Contexto: a conversa tem `team_id` (time da fila) e tem atendente (que é membro de times).
- Opções: (1) só `team_id`; (2) só o time do atendente; (3) os dois, somados.
- Recomendação: (3). Igual ao CRM, que usa o dono ou o atendente.

**X. Autorização para criar modelos com custo na Meta**
- Contexto: o #1585 diz "aceite do dono". Hoje é só admin (`whatsapp_template_consents_controller.rb:15-18`). A regra das duas listas não cita.
- Opções: (1) só o dono; (2) `financial_manage` 🔒 (CFO).
- Recomendação: (2). É gasto, e o CFO cuida do gasto. Se você entende "dono" do #1585 ao pé da letra, (1). Modelos WhatsApp: de acordo com `financial_manage`; o aceite já é só de acréscimo e grava o nome de quem aceitou (#1635); ver a autorização (GET) pode ficar em `whatsapp_templates_view`. Ver também a 7.4-6.

**Y. 21 chaves novas, não 15**
- Contexto: seção 5.4.
- Cortes possíveis: juntar `token_manage` em `integration_manage` (−1); juntar `audit_log_view` em `security_manage` (−1); juntar `financial_manage` em `financial_view` (−1, mas quem vê também compra créditos); `meta_ads_manage` dentro de `integration_manage` (−1, o CTO conecta e o CMO só usa); `assignment_manage` dentro de `inbox_manage` (−1).
- As 21 continuam como peças. O que muda é quando cada uma aparece na tela.
- **Classificação por porte [proposta]:**

| Grupo | Chaves | Por quê |
|---|---|---|
| **Toda empresa usa** (9, aparecem sempre) | `campaign_send`, `contact_export`, `contact_delete`, `crm_delete_cards`, `conversation_message_delete`, `meta_ads_view`, `meta_ads_manage` 🔒, `financial_view` 🔒, `financial_manage` 🔒 | são o dia a dia de quem vende, atende e faz marketing, mais alguém que paga a conta. Até a empresa de 3 pessoas decide quem dispara, quem exporta, quem exclui e quem vê os anúncios |
| **Só empresa maior** (12, modo avançado ou depois) | `conversation_view`, `assignment_manage`, `sales_value_view` 🔒, `ai_cost_view` 🔒, `user_manage` 🔒, `team_manage` 🔒, `role_manage` 🔒, `integration_manage` 🔒, `token_manage` 🔒, `security_manage` 🔒, `audit_log_view` 🔒, `account_settings_manage` 🔒 | só fazem sentido quando o dono passa para outros a gestão de pessoas, tecnologia, distribuição e controle. Na empresa pequena, o dono faz isso sozinho |

- Ficar no modo avançado não tira a chave do servidor: a regra vale igual, só não aparece na primeira tela. O administrador continua fazendo tudo.
- Recomendação: manter as 21 no catálogo e no servidor (etapa 3). Na tela (etapa 7), mostrar as 9 sempre e as 12 num "Mais opções". Se for cortar, os dois primeiros cortes da lista acima são os de menor custo.

**Z2. Dono nas contas que já existem**
- Contexto: hoje há só administradores. Ao criar o dono, as 5 ações saem do administrador comum.
- Opções: (1) marcar dono o administrador mais antigo da conta [HIPÓTESE: dá para saber por `account_users.created_at`]; (2) todos os administradores de hoje viram donos, e o dono tira os demais depois; (3) Rodrigo marca conta a conta.
- Recomendação: (2). Ninguém perde nada no dia do deploy. Na conta 43 (cliente real), só leitura até combinar.

### 7.4 Novas da etapa 2 (17/10)

**7.4-1. Três "só os meus"**
- Contexto: há três regras com o mesmo nome: o alcance do cargo, o `only_own` do funil e o `assigned_only` da caixa. A pessoa não sabe qual a barrou.
- Opções: (a) unificar: o alcance do cargo absorve o `assigned_only`, e o `only_own` vira exceção por caixa; (b) manter as três com nomes diferentes, e a ficha da pessoa mostra qual barrou.
- Recomendação: (a), do Multifunnel.

**7.4-2. "Excluir" em massa no CRM arquiva**
- Contexto: a ação em massa "excluir" chama `archive_card!`. O nome na tela precisa bater com a chave.
- Opções: (a) arquivar fica em `crm_manage_cards`; (b) arquivar fica em `crm_delete_cards`.
- Recomendação: o Multifunnel pede decisão, sem preferência. Usar o mesmo nome na tela nos dois casos.

**7.4-3. WhatsApp API cria e dispara junto**
- Contexto: o POST da campanha de WhatsApp API cria e dispara na mesma hora. Com `campaign_send` separado, quem só tem `campaign_manage` deixa de criar.
- Opções: (a) criar rascunho, e disparar vira um segundo passo com `campaign_send`; (b) aceitar a perda: quem só monta não cria campanha de WhatsApp API.
- Recomendação: Campanhas pede decisão explícita. (a) mantém o "montar" útil, mas é mudança de fluxo.

**7.4-4. E-mail de teste**
- Contexto: mandar o e-mail de teste para até 5 endereços.
- Opções: (a) `campaign_manage`; (b) `campaign_send`.
- Recomendação: (a), de Campanhas. É conferência de quem monta, não disparo em massa.

**7.4-5. Caixa da campanha**
- Contexto: a tela lista só as caixas em que a pessoa é membro, mas o servidor aceita qualquer caixa da conta (seção 2.7). Dar `inbox_view` não é a saída.
- Opções: (a) ser membro da caixa é o alcance da campanha, e o servidor passa a exigir; (b) lista própria de caixas por `campaign_manage`.
- Recomendação: (a), de Campanhas.

**7.4-6. "Aceite do dono" (#1585) e `financial_manage` delegável**
- Contexto: o #1585 diz que o sistema só cria modelo com custo com o aceite do dono. A dúvida X propõe `financial_manage` 🔒, que o dono pode entregar.
- Opções: (a) o aceite vale do dono ou de quem recebeu `financial_manage` dele; (b) só o dono, ao pé da letra.
- Recomendação: Modelos WhatsApp devolve a decisão ao Rodrigo. O botão v1 do Agendamento sai antes disso (#1612).

**7.4-7. Tela de Equipes**
- Contexto: a tela de Equipes é antiga (7 rotas, nota 3,5 a 4: assistente antigo, Options API, checkbox cru em `TeamForm.vue:165-166`). A hierarquia pede dois campos novos.
- Opções: (a) reformular a tela inteira; (b) um bloco "Hierarquia" no padrão novo, com o próprio Salvar.
- Recomendação: (b), do Frontend. A reformulação vira Issue própria. Trocar ao menos o checkbox cru.

**7.4-8. Calendários de SLA**
- Contexto: desde o #1618, tela e API pedem administrador ou `crm_admin`.
- Opções: (a) somar `sla_manage`, mantendo `crm_admin`; (b) manter como está.
- Recomendação: (a), do Agendamento, com a trava de ninguém editar o próprio calendário de SLA.

**7.4-9. "Meu time" restringe a lista de páginas para marcar?**
- Contexto: hoje a lista de páginas para marcar mostra todas (#1265, #1271).
- Opções: (a) "Meu time" restringe às páginas do time; (b) continua mostrando todas.
- Recomendação: o Agendamento pede decisão, sem preferência.

**7.4-10. Quem pode atender não olha funil**
- Contexto: a elegibilidade de quem atende não confere funil, e `booker.rb:185` usa o dono do card sem olhar o funil.
- Opções: (a) a elegibilidade passa a conferir o funil; (b) manter e registrar.
- Recomendação: o Agendamento registra como lacuna e pede decisão.

**Ainda em aberto de antes:** #726 (Modelos pela área de Campanhas); D1, D2, D4, D5, D7, D8 e D9 do diagnóstico local; rodízio e dona em "Só as suas" (`PLANO.md:218`).

---

## 8. Etapa 2 concluída em 17/10

Os 8 chats donos de módulo leram a versão 3. Nenhum contrariou o modelo. Tudo o que pediram está nesta versão 4.

| Chat dono | Resposta em uma linha |
|---|---|
| **Modelos WhatsApp** | regra única ok; faltava produto e carrossel pela conversa (#1749, membro da caixa, sem chave); "Atualizar" continua com ver; modelos da caixa API ficam com Campanhas; X ok, com a 7.4-6 para o Rodrigo |
| **Multifunnel / CRM** | nada contraria; cargo existente nasce em "Empresa toda" (crítico); Z1 só valor somado; excluir em massa arquiva; mover em massa pede `crm_move_cards`; três "só os meus"; J de acordo |
| **WhatsApp Híbrido** | sem conflito; WAHA e híbrido em `inbox_manage`; remover o criador da caixa WAHA para o conector |
| **Campanhas** | nada contraria; lista exata do `campaign_send`; IA paga em `meta_ads_view`; "peça ao administrador" sem remetente; caixa aceita sem ser membro em 4 pontos |
| **Frontend geral** | sem conflito; manter o esqueleto do `CustomRoleEditor`; tela de Equipes antiga; `meta.permissions` como fonte do Guia; menu sem piscar; régua só com opções que existem |
| **Agentes IA** | nada contraria a Fase 2; regra G nos 4 caminhos; vazamento nas conversas por resultado (corrige no PR dele); ferramentas depois, com chave protegida |
| **Agendamento** | faltava a área Agendamento; alcance pelo card nas reuniões; botão v1 sai (#1612, decisão do Rodrigo); calendários desatualizados no doc; aviso de páginas pausadas |
| **Orquestração** | pediu a etapa 3 em lotes, um por vez, com a lista de arquivos antes |

**Próximo passo:**
1. O Rodrigo decide as dúvidas abertas (seções 7.2, 7.3 e 7.4).
2. Abrir o épico com uma Issue por etapa, na ordem da seção 6.
3. Começar a etapa 3 pelo primeiro lote, com a lista de arquivos enviada à Orquestração e ao chat dono. Chaves protegidas só depois do merge do PR #1783.

---

## 9. Decisões do Rodrigo em 18/10 (noite)

| Dúvida | Decisão |
|---|---|
| D7 (contato dentro da conversa e do card sem `contact_view`) | **(a)** nome, telefone e e-mail do contato daquela conversa. Ficha completa, notas e demais abas exigem `contact_view` |
| 7.4-2 (excluir em massa arquiva) | **(b)** arquivar fica em `crm_delete_cards`, junto com excluir; a tela passa a dizer "Arquivar" |
| 7.4-3 (WhatsApp API cria e dispara junto) | **(a)** vira rascunho + disparar; disparo exige `campaign_send`. Mudança de fluxo: mockup antes de codar |
| 7.4-4 (e-mail de teste) | **(a)** `campaign_manage` |
| 7.4-5 (caixa da campanha) | **(a)** ser membro da caixa é o alcance da campanha; o servidor passa a exigir |

O teste completo do épico ficou para o fim, com o roteiro em `ROTEIRO-TESTE-FINAL.md`.
