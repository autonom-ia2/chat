# Pesquisa: como deve ser a caixa de resposta de e-mail do Chat2You

**Objetivo:** reunir como os melhores produtos desenham a caixa de resposta de e-mail e propor um desenho nota 10 para o Chat2You. Não mexi em código.

**O que foi consultado:** cerca de 30 buscas e leituras na web, com prioridade para as páginas oficiais de ajuda (Google, Microsoft, Apple, Help Scout, Zendesk, Intercom, Front, Freshdesk, Readdle, Missive, Gorgias, HubSpot). Quando só achei fonte de terceiros, está indicado. O que não achei está como "n/c" (não confirmado).

## A) Tabela comparativa

| Produto | Onde abre | Destinatários / assunto / De | Texto citado | Formatação | Anexos | Modelos | Enviar | Nota interna / colisão | IA |
|---|---|---|---|---|---|---|---|---|---|
| **Gmail web** | Embaixo da conversa; vira janela solta ou tela cheia; pode ser tela cheia por padrão [3] | Responder ou Responder a todos; dá para escolher qual é o padrão [1]; Ctrl+Shift+C abre o Cc e Ctrl+Shift+B abre o Cco [4] | Fica escondido atrás de "…" ("Show trimmed content") [2] | Barra visível por padrão: fonte, tamanho, cor, listas, alinhamento, recuo, citação, remover formatação [5]; atalhos Ctrl+Shift+7/8/9 [4] | Limite de 25 MB; acima disso vira link do Drive [6] | n/c (tem "modelos" escondidos nas configurações) | Agendar envio; desfazer de 5 a 30 s [7]; Ctrl+Enter [4] | não se aplica | "Help me write": formalizar, deixar mais amigável, encurtar, com desfazer e refazer [8] |
| **Outlook web / novo** | No painel de leitura; botão "abrir em janela separada" [9] | n/c | n/c | n/c | Limite de 20 a 25 MB conforme a fonte; aviso de "esqueceu o anexo" só para texto em inglês (EUA) [10] | n/c | Desfazer de 5 ou 10 s [11] | não se aplica | Copilot: rascunho com tom e tamanho ajustáveis, mais "Coaching"; não funciona em texto puro [12] |
| **Apple Mail (Mac)** | Janela própria | n/c | Barra de citação; níveis de citação; "Paste as Quotation"; dá para desligar a citação [13] | Menu Formatar | Mail Drop para arquivos grandes | n/c | Desfazer de 10 a 30 s [14] | não se aplica | n/c |
| **Superhuman** | Dentro da conversa | Enter responde a todos (fonte de terceiros) [15] | n/c | n/c | n/c | Snippets com anexo e Cc incluídos [16] | Desfazer; "enviar e concluir" (terceiros) [15] | não se aplica | 3 respostas prontas pré-geradas; escreve no seu tom [17] |
| **HEY** | n/c | "Reply Together": uma resposta para várias conversas [18] | n/c | n/c | n/c | n/c | n/c | não se aplica | n/c |
| **Spark** | Compositor próprio | n/c | n/c | n/c | n/c | Modelos [19] | Enviar depois; desfazer em 5 s com Cmd+Z, sem ajuste [20] | Rascunho compartilhado com comentários da equipe [21] | +AI: gerar, ajustar, inserir [22] |
| **Front** | Dentro da conversa | n/c | n/c | n/c | n/c | n/c | "Enviar e arquivar"; desfazer por cerca de 5 s (fonte de terceiros) [23] | Comentário interno; mostra quem está respondendo e sincroniza o rascunho [24] | AI Compose: tom profissional, amigável ou empático; expandir, encurtar, traduzir [25] |
| **Help Scout** | Abre embaixo com R | Cc e Cco aparecem só ao clicar no Para | n/c | Markdown enquanto digita; menu ao selecionar o texto | Até 10 MB por arquivo; acima de 8 MB no total vira link | "/" ou "+" abre as respostas salvas | Escolher status e responsável antes de enviar; enviar depois [26] | Nota com editor **amarelo**, tecla N [26]; trava o envio se houve novidade e a resposta fica "Pausada" [27] | AI Assist: tom, tamanho, gramática, tradução [28] |
| **Zendesk** | Embaixo; altura ajustável, que fica salva | Troca de canal no topo do compositor | n/c | Texto rico, tabela, cor (se o admin ligar) | Sim | Macros | "Submit"; modo rascunho que pede confirmação | Rascunho separado por canal, com bolinha azul; o rascunho sobrevive a fechar o navegador [29] | n/c |
| **Intercom** | Embaixo | n/c | n/c | n/c | n/c | Macros por "#", "\\" ou ícone; as ações da macro aparecem embaixo e rodam ao enviar [30] | Ctrl+Shift+Enter envia e fecha; Ctrl+Alt+Enter envia e adia [31] | Nota com N [31]; cor n/c | Rephrase, Expand, tom, tradução; Ctrl/Cmd+J [32] |
| **Missive** | Na conversa | Resposta pronta pode preencher Para, Cc e Cco | n/c | n/c | n/c | "#" + busca | "Enviar e fechar" e já vai para a próxima | Rascunho com cursores ao vivo [33] | Responde usando as respostas prontas [33] |
| **Freshdesk** | Embaixo | n/c | n/c | n/c | n/c | Respostas prontas | "Enviar e marcar como <status>" [34] | Mostra quem vê ou digita; trava o envio sem atualizar a página; rascunho salvo a cada ~30 s, apagado em 24 h [34][35] | n/c |
| **HubSpot** | Embaixo; pode virar janela solta | n/c | n/c | n/c | n/c | Modelos (e-mail inteiro) e snippets (trecho) | Rascunho automático [36] | Comentário interno; cor n/c | n/c |
| **Gorgias** | Embaixo | Seletor de canal | n/c | n/c | n/c | Macros com variáveis; as ações aparecem em "executado ao enviar" | "Enviar e fechar" (não existe para nota) | A nota **muda a cor** do compositor [37] | n/c |
| *Chatwoot (nossa base)* | Embaixo | Cc e Cco | n/c | Texto rico | Sim | Respostas prontas | — | Nota privada **âmbar**; Alt+P alterna resposta e nota [38] | — |

## B) O que quem usa e-mail já espera

1. **A resposta abre embaixo da última mensagem**, dentro da conversa, e pode crescer para janela solta ou tela cheia (Gmail, Outlook, HubSpot).
2. **Responder, Responder a todos e Encaminhar** no topo, com Cc e Cco escondidos atrás de um link ou atalho até serem pedidos.
3. **Histórico escondido** atrás de "…": vai junto no e-mail, mas não ocupa a tela (Gmail, Apple).
4. **Assinatura antes do texto citado.** O Gmail tem uma opção só para isso [39].
5. **Desfazer envio de 5 a 30 s.** Todos os clientes de e-mail têm. Por baixo, é um atraso no envio, não um "recall" [7].
6. **Agendar envio** no menu ao lado do botão Enviar.
7. **Ctrl/Cmd+Enter** para enviar.
8. **Rascunho salvo sozinho.** Zendesk e Freshdesk deixam explícito; o do Zendesk sobrevive a trocar de ticket e a fechar o navegador.
9. **Nos helpdesks:** "Enviar e resolver/fechar"; nota interna com **cor diferente** (amarelo ou âmbar); aviso de colisão quando outra pessoa responde; modelos por "/" ou "#".
10. **IA de reescrita** com o mesmo menu curto em todos: mais formal, mais amigável, mais curto, mais longo, corrigir, traduzir, com "desfazer" e "tentar de novo".

## C) Ideias únicas que valem nota 10

- **Help Scout: a resposta fica "pausada" se houve novidade.** Se chegou mensagem nova ou nota enquanto a pessoa escrevia, o envio é travado, a resposta fica com borda vermelha e há três saídas: Enviar mesmo assim, Editar ou Descartar [27]. É a melhor proteção contra resposta duplicada.
- **Intercom e Gorgias: as ações aparecem antes de executar.** O modelo mostra embaixo o que vai fazer ao enviar (etiqueta, atribuição, fechar), e dá para remover cada ação [30][37].
- **Zendesk: rascunho separado por modo e "modo rascunho" que pede confirmação.** Uma bolinha mostra em qual modo há texto não enviado [29].
- **Front, Missive e Spark: rascunho compartilhado ao vivo**, com cursores e comentários da equipe [21][24][33].
- **Superhuman: três respostas prontas já calculadas embaixo da conversa** [17]. Sem espera.
- **Gmail: arquivo grande vira link automaticamente** [6], e a escolha de "Responder" ou "Responder a todos" como padrão [1].
- **Help Scout: status e responsável escolhidos dentro do próprio compositor**, antes de enviar [26].
- **HEY: a mesma resposta para várias conversas** [18]. É de nicho e não recomendo agora.

## D) Recomendação de desenho para o Chat2You

**Estados**

1. **Fechado.** Uma barra fixa embaixo da conversa com três botões grandes: **Responder** (principal), **Responder a todos** (só aparece se houver mais de um destinatário) e **Encaminhar**. Ao lado, um botão separado **Nota interna**. Cada botão tem pelo menos 44 px.
2. **Aberto embaixo** (o padrão ao clicar). Ocupa cerca de 40% da altura e a conversa continua visível acima.
3. **Expandido.** Um ícone "Aumentar" faz o compositor ocupar toda a coluna da conversa. Ao sair, tudo volta como estava.
4. **Janela solta / tela cheia.** Um ícone "Abrir em janela" deixa navegar por outras conversas com o rascunho preservado. No celular, o estado aberto já é tela cheia.

**Layout, de cima para baixo**

1. **Tipo de resposta** (Responder / Responder a todos / Encaminhar), com rótulo escrito por extenso, sem depender só de ícone. Para trocar, usar o `ChoiceSelect` do projeto (regra: nunca `<select>` nativo).
2. **De:** só aparece quando há mais de uma caixa. Também `ChoiceSelect`.
3. **Para:** destinatários como "chips", com autocompletar dos contatos no padrão de combobox do WAI-ARIA [40]. Os links **"Cc"** e **"Cco"** abrem os campos; chip com e-mail inválido fica vermelho.
4. **Assunto:** escondido na resposta (mantém "Re:"). Um link "Editar assunto" mostra o campo. No Encaminhar, aparece sempre.
5. **Área de texto:** sem nada além do texto.
6. **Assinatura** da caixa entra abaixo do texto e antes do histórico, uma única vez.
7. **Histórico:** botão "… Mostrar mensagem anterior". Vai incluído por padrão; ao expandir, dá para editar ou remover ("Não incluir histórico").
8. **Anexos:** lista com nome, tamanho e "remover". Arrastar e soltar em toda a área do compositor, com a área de soltar destacada.
9. **Barra de baixo:**
   - à vista: **Enviar** (principal) com uma seta de mais opções; **Anexar**; **Modelos**; **Formatar (Aa)**; **IA (✨)**;
   - no menu da seta: Enviar e resolver, Agendar envio;
   - à direita: lixeira "Descartar", com confirmação.

**O que fica escondido:** a barra de formatação inteira fica atrás do **Aa**, com uma linha só: negrito, itálico, sublinhado, lista com marcador, lista numerada, link, citação, remover formatação. Fonte, cor e alinhamento ficam num submenu "Mais". Leigo não precisa de fonte nem de cor.

**Para a pessoa leiga**

- Uma ação principal por vez: só o Enviar é preenchido.
- O rótulo do botão diz o destino: "Enviar para Maria".
- **Nota interna:** compositor âmbar com faixa "Só a sua equipe vê isto", botão "Salvar nota" (nunca "Enviar") e rascunho separado do da resposta, como no Zendesk.
- Aviso de anexo esquecido; aviso de "ninguém em Para"; um toast "Enviando… Desfazer" com 10 s configuráveis.
- **Colisão:** avatar "Fulano está respondendo" no topo. Na hora de enviar, se chegou algo novo, pausar como o Help Scout: "Chegou uma mensagem nova. Ler antes / Enviar mesmo assim".
- **Rascunho:** salvo no servidor por conversa e por pessoa, com o texto "Rascunho salvo às 14:32" e um marcador "Rascunho" na lista de conversas.
- **Modelos:** atalho "/", busca por nome, variáveis preenchidas com prévia. Se alguma variável ficar vazia, avisar antes de enviar (o Gorgias mostra que variável vazia ou com chaves cruas é falha comum [37]).
- **IA:** menu curto com Melhorar, Mais formal, Mais amigável, Mais curto, Corrigir, Traduzir e Escrever resposta. O resultado aparece como prévia com Usar / Tentar de novo / Desfazer, sem substituir o texto direto.
- **Teclado:** Ctrl/Cmd+Enter envia; Esc recolhe sem perder o rascunho; ordem lógica de foco; `aria-live` para "rascunho salvo" e "enviado". Atalhos de uma letra só fora do texto, como no Intercom [31].

## E) Riscos e armadilhas

1. **Perder rascunho.** Só `localStorage`, trocar de conversa ou expirar a sessão. Mitigação: salvar no servidor com atraso curto e no `beforeunload`; não apagar em 24 h como o Freshdesk [34].
2. **Citação que quebra.** Cada cliente mostra a citação de um jeito: o Outlook só recua e separa mensagens com uma linha [41]. Usar `<blockquote>` com estilo inline simples; o padrão do Gmail [42] e do Outlook pede teste real nos dois.
3. **Colar do Word.** Traz muita marcação desnecessária e pesa em filtro de spam [43]. Limpar na colagem, mantendo negrito, listas e links, e oferecer "Colar como texto" com Ctrl+Shift+V.
4. **HTML pesado.** O Gmail corta mensagens acima de ~102 KB de HTML ("Mensagem cortada") [44]. Histórico longo e assinatura com imagem embutida pioram isso.
5. **Assinatura duplicada.** Inserir de novo a cada troca de remetente ou a cada modelo. Guardar a assinatura como bloco único e trocá-lo, sem acumular. O Gmail ainda esconde assinatura repetida [2].
6. **Nota enviada ao cliente.** É a falha mais grave nos helpdesks; uma macro do Zendesk pode trocar Nota por Público sem a pessoa perceber [45]. Usar cor, rótulo e botão diferentes, e modelo nunca troca o modo sozinho.
7. **Ctrl+Enter acidental.** Envia e-mail pela metade [4]. O desfazer envio resolve.
8. **Anexo acima do limite** do servidor de quem recebe: avisar o tamanho total antes de enviar.
9. **"Responder a todos" esquecido ou indevido.** Mostrar os chips sempre e avisar quando houver gente de fora.
10. **IA que não funciona em texto puro** (limitação do Copilot [12]). Decidir o formato antes.

## Fontes

[1] https://support.google.com/mail/answer/6585 · [2] https://labnol.org/internet/gmail-trimming-signature/28762 · [3] https://www.pcworld.com/article/447166/google-retires-the-classic-gmail-composition-interface-how-to-make-the-new-one-more-usable.html · [4] https://zapier.com/blog/gmail-shortcuts.md · [5] https://it.lbl.gov/gmail-compose-mode-new-options/ · [6] https://tomsguide.com/how-to/how-to-send-large-files-with-gmail · [7] https://oit.ncsu.edu/2022/03/15/unsend-an-email-in-gmail/ · [8] https://support.google.com/mail/answer/13955415?hl=en · [9] https://support.microsoft.com/en-us/outlook/create-and-respond-to-messages-in-outlook-web-app · [10] https://wus.prod.support.services.microsoft.com/en-gb/office/attach-files-in-outlook-48b8dca1-7a76-43ce-97d1-e1cf73893f55 · [11] https://support.microsoft.com/topic/35027f88-d655-4554-b4f8-6c0729a723a0 · [12] https://support.microsoft.com/office/draft-an-email-message-with-copilot-in-outlook-3eb1d053-89b8-491c-8a6e-746015238d9b · [13] https://support.apple.com/guide/mail/mlhlp1010/mac · [14] https://support.apple.com/guide/mail/unsend-emails-with-undo-send-mlhlbf24d020/15.0/mac/13.0 · [15] https://www.pie-menu.com/shortcuts/superhuman · [16] https://danielmiessler.com/blog/my-favorite-superhuman-shortcuts · [17] https://superhuman.com/ai · [18] https://updates.37signals.com/post/new-in-hey-reply-to-everyone · [19] https://support.readdle.com/spark/sending-emails/use-email-templates · [20] https://support.readdle.com/spark/tips-tricks/undo-the-last-action · [21] https://support.readdle.com/spark/spark-for-teams-and-billing/shared-drafts-write-emails-together-with-your-team · [22] https://support.readdle.com/spark/tips-tricks/spark-ai · [23] https://itsupport.life.church/a/1941344-front-how-to-respond-to-a-conversation · [24] https://help.front.com/en/articles/2403 · [25] https://community.front.com/product-updates/refine-drafts-with-ai-compose-1361 · [26] https://docs.helpscout.com/article/69-respond-to-conversations · [27] https://docs.helpscout.com/article/99-traffic-cop · [28] https://docs.helpscout.com/article/1513-use-ai-assist · [29] https://support.zendesk.com/hc/en-us/articles/4408831849882 · [30] https://intercom.com/help/en/articles/6584504-using-macros-in-the-inbox · [31] https://www.intercom.com/help/en/articles/6272267-how-to-use-command-k-in-the-inbox · [32] https://www.intercom.com/help/en/articles/6955446-ai-assist-for-inbox · [33] https://missiveapp.com/docs/core-features/conversations/drafts e https://missiveapp.com/features/responses/overview · [34] https://crmsupport.freshworks.com/en/support/solutions/articles/37562-replying-to-a-ticket · [35] https://crmsupport.freshworks.com/en/support/solutions/articles/218073-agent-collision-detection · [36] https://knowledge.hubspot.com/inbox/compose-and-reply-to-emails-in-the-conversations-inbox · [37] https://docs.gorgias.com/en-US/macro-actions-81913 e https://www.getmacha.com/blog/gorgias-macro-variables-not-working · [38] https://www.chatwoot.com/features/private-notes · [39] https://www.bettercloud.com/monitor/the-academy/insert-gmail-signature-before-quoted-text/ · [40] https://www.w3.org/WAI/ARIA/apg/patterns/combobox/ · [41] https://support.mozilla.org/zh-TW/questions/1372836 · [42] https://lists.freron.com/mailmate/2018-April/009722.html · [43] https://www.mailpro.com/faq/copy-text-as-plaintext · [44] https://help.activecampaign.com/hc/en-us/articles/115001060524 · [45] https://support.zendesk.com/hc/en-us/articles/4408831849882/comments/4649731939354

**Lacunas:**
- **Celular:** só confirmei a resposta embaixo da conversa no Android do Gmail, que foi pausada para contas Workspace em out/2024 [3].
- **Acessibilidade:** não achei documentação de leitor de tela de nenhum dos produtos. A recomendação segue o padrão do WAI-ARIA [40].
- **Front:** não confirmei a janela solta nem o atalho "/".
- **Intercom e HubSpot:** não confirmei a cor da nota interna.
- **Superhuman:** os atalhos vêm de listas de terceiros.

**Projeto e próximo passo:** nada foi criado (era só pesquisa). O próximo passo natural é transformar a seção D em um protótipo navegável em tela real para aprovação antes de implementar.