# Roteiro de teste em produção: caixa WAHA (#1709)

**Quem:** o Rodrigo, com o celular pessoal no papel de **cliente**, e o chat2you de produção na **conta 16**, numa caixa WAHA, no papel de **empresa**.
**Objetivo:** confirmar no aparelho real que tudo o que a empresa envia chega certo ao cliente, e que tudo o que o cliente envia aparece certo no chat2you.

---

## 0. Antes de começar (eu preparo e confirmo com você)

| # | O que | Quem | Como saber que está ok |
|---|---|---|---|
| 0.1 | O #1741 está no ar nas duas stacks | Orquestração | Mensagem "no ar" com o SHA |
| 0.2 | O motor da caixa roda o WAHA customizado c2y-rich-5 | eu | Já está: wa-hub e wa-autonomia desde 17/10 |
| 0.3 | O motor da caixa entrou na lista de motores ricos (`WAHA_RICH_NATIVE_ENGINES`) | eu, com o seu OK | A capacidade do motor aparece no painel |
| 0.4 | O dono do token está gravado na caixa WAHA da conta 16 | eu, com o seu OK (banco de produção, com backup) | Consulta de conferência devolve 0 caixas sem dono |
| 0.5 | A flag `whatsapp_rich_native` está ligada **só na conta 16** | eu, com o seu OK | O painel da conta 16 mostra "Reagir" e "Editar" no menu da mensagem |
| 0.6 | A caixa escolhida está **sem agente de IA**, para a IA não responder no meio do teste (a IA tem a parte F, separada) | você | Na aba "Agente de IA" da caixa: ninguém |
| 0.7 | O aviso de visualização única está ligado nessa caixa (opção do motor) | eu, com o seu OK | Confirmo antes de começar |

**Regras durante o teste:**
- Espere uns **20 a 30 segundos entre um passo e outro**, como uma pessoa faria. Nada de mandar tudo de uma vez.
- **Seu celular pessoal manda a primeira mensagem.** A empresa nunca começa a conversa.
- Em cada passo, olhe **os dois lados**: o celular e o painel. Marque ✅ ou ❌ e, se der ❌, me mande um print dos dois lados.
- Se o WhatsApp mostrar qualquer aviso de restrição ou bloqueio no número da empresa, **pare** e me avise.

---

## A. Começo da conversa

| # | No celular (cliente) | No painel (empresa) | Resultado esperado | ✅/❌ |
|---|---|---|---|---|
| A1 | Mande "Oi, quero testar" para o número da caixa | Abra a conversa nova | A mensagem aparece no painel, do seu contato, com hora certa | |
| A2 | — | Responda "Oi! Vamos testar." | Chega no celular. No painel aparecem os tiques: ✓ enviado, ✓✓ entregue e ✓✓ azul quando você abrir | |

---

## B. Envio pela plataforma (empresa → cliente)

### B1. Texto e formatação
| # | Ação no painel | No celular, deve aparecer | ✅/❌ |
|---|---|---|---|
| B1.1 | Mande: `*negrito* _itálico_ ~riscado~ ` + "`código`" | Negrito, itálico, riscado e código **formatados**, sem símbolos sobrando | |
| B1.2 | Mande um texto com várias linhas e uma lista (- item 1 / - item 2) | Quebras de linha e lista certas | |

### B2. Mídia
| # | Ação no painel | No celular, deve aparecer | ✅/❌ |
|---|---|---|---|
| B2.1 | Anexe uma **foto JPG** com legenda | Foto com a legenda (não como arquivo) | |
| B2.2 | Anexe uma foto em **WEBP ou PNG grande** | Sai como **foto**, não como documento | |
| B2.3 | Anexe um **vídeo** (MP4 ou MOV) | Sai como **vídeo** que toca no WhatsApp | |
| B2.4 | Anexe um **PDF** | Documento com o nome do arquivo | |
| B2.5 | Grave um **áudio** pelo microfone do painel | Áudio que toca | |

### B3. Mensagens ricas
Use o **"+"** da barra de digitar. Ele vem com a pele nova, que está ligada na conta 16. Os itens marcados com 🔧 eu disparo pela API enquanto você olha o celular, porque ainda não estão no "+".

| # | Como criar | No celular, deve aparecer | No painel | ✅/❌ |
|---|---|---|---|---|
| B3.1 | "+" → **Opções**: cabeçalho "Vistoria", pergunta "Qual período fica melhor?", opções Manhã, Tarde e Noite. A tela exige o cabeçalho. | Mensagem com o botão **"Ver horários"**; ao tocar, abrem as 3 opções | Bolha da lista com as opções | |
| B3.2 | 🔧 **Lista sem cabeçalho**, só para provar a proteção (a tela não deixa criar assim) | Chega como **texto**, com as opções numeradas (1. 2. 3.) | Marca "Enviado como texto" | |
| B3.3 | **Enquete** ("Qual dia prefere?" Segunda, Quarta, Sexta): pelo "+" se o PR curto do Max já estiver no ar; senão 🔧 | Enquete nativa com as bolinhas de voto | Bolha da enquete | |
| B3.4 | "+" → **Localização** (endereço da empresa) | Mapa clicável com nome e endereço | Cartão de mapa | |
| B3.5 | "+" → **Contato** (cartão de um atendente) | Cartão com "Conversar" e "Adicionar contato" | Cartão de contato | |
| B3.6 | 🔧 **Convite de evento** (data futura e local). Vai entrar no "+" num PR do Max depois. | Convite com data, hora, local e "Vou" / "Não vou" | Bolha do convite | |
| B3.7 | "+" → **Botão de link** ("Acessar proposta" com o endereço) | Cartão de prévia do link (título, imagem, descrição) | Bolha do link | |
| B3.8 | "+" → **Pedir localização** | Na caixa WAHA sai como texto pedindo a localização: o pedido nativo só existe na API oficial | Texto | |

### B4. Ações sobre mensagens já enviadas
| # | Ação no painel | No celular, deve aparecer | ✅/❌ |
|---|---|---|---|
| B4.1 | **Citar** uma mensagem sua (cliente) e responder | A resposta aparece citando a sua mensagem | |
| B4.2 | **Reagir** com 👍 a uma mensagem sua (menu da mensagem → Reagir) | 👍 na sua mensagem | |
| B4.3 | Trocar a reação para ❤️ | 👍 troca por ❤️ (fica só uma) | |
| B4.4 | **Editar** uma mensagem da empresa enviada há menos de 15 min | Texto novo, com "Editada" | |
| B4.5 | **Apagar para todos** uma mensagem da empresa (o menu diz "Apagar para todos") | "Esta mensagem foi apagada" | |

---

## C. Recebimento na plataforma (cliente → empresa)

| # | No celular (cliente) | No painel, deve aparecer | ✅/❌ |
|---|---|---|---|
| C1 | Toque em **"Ver horários" → Tarde** na lista do B3.1 | "O cliente tocou em 'Tarde'", ligado à lista | |
| C2 | **Vote** "Quarta" na enquete do B3.3 | Na enquete: "Votou: Quarta" | |
| C3 | **Troque o voto** para "Sexta" | A enquete passa a mostrar Sexta (não fica voto em dobro) | |
| C4 | Responda **"Vou"** ao convite do B3.6 | No convite: "Vou: 1" | |
| C5 | **Reaja** com 😂 a uma mensagem da empresa | 😂 colado na mensagem da empresa | |
| C6 | Mande um texto e depois **edite** ele no celular | Só o texto novo, com "Editada" (o antigo fica guardado) | |
| C7 | Mande um texto e **apague para todos** | Selo "Apagada pelo cliente", **com o conteúdo guardado** | |
| C8 | Mande uma **localização** | Cartão de mapa | |
| C9 | Mande a **localização em tempo real** | Mapa com "Localização em tempo real" e a legenda | |
| C10 | Mande um **contato** | Cartão de contato com o telefone | |
| C11 | Grave um **áudio de voz** (segurando o microfone) | Mensagem de voz com player | |
| C12 | Mande um **arquivo de áudio** (MP3) | Áudio como arquivo (diferente da voz) | |
| C13 | Mande **uma foto** | Foto | |
| C14 | Mande **3 fotos de uma vez** (álbum) | Fotos agrupadas, sem bolha vazia | |
| C15 | Mande uma **figurinha** | Figurinha (sem balão de foto) | |
| C16 | Mande um **vídeo** | Vídeo | |
| C17 | Mande um **documento** (PDF) | Documento | |
| C18 | **Responda citando** uma mensagem antiga da empresa | Sua resposta ligada à mensagem citada | |
| C19 | **Encaminhe** uma mensagem de outra conversa | Marca "Encaminhada" | |
| C20 | Mande uma foto de **visualização única** (ícone do "1" ao enviar) | Aviso: "Você recebeu uma mensagem de visualização única. Por motivos de privacidade, você só pode abrir essa mensagem no seu celular." | |
| C21 | Ligue a **mensagem temporária** na conversa e mande um texto | Aviso de conversa temporária, e o texto **fica guardado** | |
| C22 | Desligue a mensagem temporária | Aviso de temporária desligada | |
| C23 | Faça uma **ligação de voz** e desligue antes de atenderem | "Ligação de voz perdida" | |
| C24 | Ouça um áudio que a empresa mandou (B2.5) | No painel, o áudio fica marcado como ouvido | |

---

## D. Conversa resolvida

| # | Ação | Esperado | ✅/❌ |
|---|---|---|---|
| D1 | No painel, **resolva** a conversa. No celular, **reaja** a uma mensagem antiga | A reação vai para a **mesma** conversa (não abre conversa nova vazia) | |
| D2 | Com a conversa resolvida, faça uma **ligação perdida** | A conversa **reabre** | |

---

## E. Conferências finais

| # | O que olhar | Esperado | ✅/❌ |
|---|---|---|---|
| E1 | A conversa inteira no painel | Nenhuma mensagem **duplicada** | |
| E2 | A conversa inteira no celular | Nenhuma mensagem duplicada, nada faltando | |
| E3 | Tiques das mensagens da empresa | Entregue / lida corretos | |
| E4 | Outra caixa WAHA de **outra conta** (sem a flag) | Tudo igual a antes (texto e mídia normais, sem nada novo) | |

---

## F. (Opcional, depois) Agente de IA na caixa

Ligue um agente de IA na caixa e repita alguns passos para ver como a IA reage:

| # | No celular | Esperado da IA | ✅/❌ |
|---|---|---|---|
| F1 | Vote numa enquete | A IA responde levando em conta o voto | |
| F2 | Troque o voto rápido | A IA responde **uma vez só**, à escolha final | |
| F3 | Mande só uma figurinha ou algo que o sistema não abre | A IA **fica calada** (aparece em "Quando {nome} não respondeu") | |
| F4 | Apague uma mensagem logo depois de mandar | A IA não responde ao texto apagado | |
| F5 | Mande uma localização | A IA entende o lugar (nome e endereço, sem coordenadas) | |
| F6 | Mande "2002" e edite para "2022" | A IA **não responde à edição**, mas na próxima resposta usa "2022" | |

---

## Se algo der errado

- **Mensagem não chegou:** me mande o número do passo e um print do painel e do celular. Eu olho o registro do motor e o banco (só leitura).
- **Sinal de restrição no número:** pare tudo. A volta da flag é imediata (desligo na conta 16). A volta do motor é um comando pronto no servidor.
- **Comportamento estranho só na conta 16:** desligo a flag e tudo volta a ser como antes do #1709.
