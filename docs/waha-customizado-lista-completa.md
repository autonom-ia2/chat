# Customização do WAHA: lista final

**Status:** só leitura. Nenhum motor de produção foi chamado e nada foi alterado.
**Base que está no ar hoje:** WAHA PLUS 2026.9.2, com o motor GOWS na versão v1.0.48, cujo código é idêntico ao da v1.0.47 (marcação 120a614).

Como você pediu, os dois motores (wa-hub e wa-autonomia) entram no ar juntos, logo depois da implementação, da revisão e dos testes. A recomendação E saiu. Cada novidade vem com uma chave por caixa: desligada, a caixa funciona exatamente como hoje.

Termos usados na lista:
- **Caixa comum:** a caixa WAHA ligada direto ao painel.
- **Reserva do Híbrido:** o caminho que manda pelo WAHA quando a janela de 24 h da API oficial fechou.
- **Senha da conversa:** o token que o WhatsApp troca com quem já conversou com o número. Com ele, o envio não conta como "contato novo".

---

## 1. O que o nosso WhatsApp vai mandar e receber

### Mandar (do painel para o cliente)

| Recurso | Hoje | Depois da customização | Observação |
|---|---|---|---|
| Texto com negrito, itálico e riscado | Sai certo nos dois caminhos | Igual | Falta só um teste no celular para confirmar o Híbrido. |
| Responder citando a mensagem do cliente | Caixa comum: sim. Reserva do Híbrido: não | Sim nos dois | Ajuste só no chat2you, sem mexer no WAHA. |
| Apagar para todos | Caixa comum: sim. Reserva do Híbrido: não | Sim nos dois | |
| Reagir com emoji | Não | Botão de reagir no painel | O motor já faz isso. Falta o botão. |
| Editar mensagem já enviada | Não | Sim, até cerca de 15 min depois do envio | Exige ajuste na ponte. Sem edição, nada muda. |
| Foto | Só JPG e PNG saem como foto. Os outros formatos chegam como arquivo para baixar | Toda foto sai como foto | |
| Vídeo | Só MP4 toca na conversa. Os outros viram arquivo | Todo vídeo toca na conversa | Gasta um pouco mais de processamento. |
| Documento (PDF etc.) | Sim | Igual | |
| Áudio de voz | Sai como áudio de voz, com a onda | Igual, e aparece "gravando áudio…" antes | O "gravando" tem limite de 15 s. |
| Figurinha | Vira arquivo ou imagem | Figurinha de verdade | Prioridade baixa. |
| Localização fixa | Vira texto com link | Mapa nativo (#1709) | Testado: chega nativo. |
| Cartão de contato | Não | Cartão nativo (#1709) | Testado: chega nativo. |
| Lista de opções (menu) | Não | Lista nativa (#1709) | Só em conversa individual e só no atendimento, nunca em disparo frio. |
| Enquete | Não | Enquete nativa, e o voto volta ao painel | Testado: chega e volta. |
| Convite de evento (agenda) | Não | Opcional, para o Agendamento | Testar antes. Cancelar evento não funciona no motor. |
| Prévia de link (título e foto do site) | Caixa comum: desligada. Reserva do Híbrido: ligada sem querer | Desligada nos dois | |
| "Digitando…" | Caixa comum: sempre 2 s. Nada aparece antes de mídia ou de texto com 1 anexo. Híbrido: já varia com o tamanho | Varia com o tamanho nos dois, com limite de 15 s | Tem chave para voltar aos 2 s. |
| Botões | Não existem neste motor | Continuam não existindo | No lugar, lista ou enquete. No Híbrido, dentro das 24 h, a API oficial tem botões. |

### Receber (do cliente para o painel)

| Recurso | Hoje | Depois da customização | Observação |
|---|---|---|---|
| Texto | Sim | Igual | Não mexer. |
| Cliente responde citando uma mensagem antiga | O vínculo some sem aviso | Aparece um trecho da mensagem citada | Atendente e IA sabem a que o cliente respondeu. |
| Reação do cliente | Vira uma bolha nova "Reagiu com 👍" | Reação colada na mensagem original | Precisa sair junto com o ajuste da IA, que hoje lê esse texto. |
| Cliente edita uma mensagem | Aparecem as duas versões | Só a versão nova, com a antiga guardada | A IA para de responder à versão velha. |
| Cliente apaga uma mensagem | Nota privada, e a original continua visível | Selo de "apagada" na própria bolha | A original continua visível para prova. Decisão sua. |
| Foto ou arquivo que falha ao baixar | Só nota privada, e o cliente parece ignorado | Nova tentativa e aviso visível | |
| Álbum (várias fotos) | Bolha extra sem conteúdo | Sem bolha extra | |
| Áudio de voz | Chega como arquivo "no-filename" | Nome certo, marcado como voz | |
| Localização | Texto com link do Maps | Cartão de mapa igual ao da API oficial | Exige uma rota pequena no chat2you. |
| Localização ao vivo | Texto | Deixa claro que é só o ponto inicial | |
| Contato compartilhado | Texto e arquivo .vcf | Cartão com botão "criar contato" | Opcional. |
| Escolha numa lista | Só o texto da opção | Texto e código da opção | Necessário para o #1709 funcionar direito. |
| Voto em enquete | Não aparece | "Votou: X", que se atualiza se o cliente trocar o voto | |
| Ligação recebida ou perdida | Entra como mensagem do cliente, e a IA pode responder | Aviso de atividade, separando perdida de recusada | A informação para separar já chega hoje. |
| Tipo de mensagem desconhecido | Nota privada escondida | Bolha curta visível: "abra no celular" | Nenhuma mensagem fica invisível. |
| Mensagem temporária | Entra normal, sem aviso | Aviso de que a conversa é temporária | |
| Foto de visualização única | Não sabemos | Testar antes de decidir | Envolve privacidade. Decisão sua. |
| Entregue e lida (tiques) | Sim | Igual | |

---

## 2. O que blinda de verdade contra bloqueio

A lista é o que vem além do que já está decidido: #1725, proxy BR por conta, contato novo livre e sem teto diário. Só entraram itens que passaram pela verificação.

Grau de certeza:
- **Comprovado:** visto no código ou testado.
- **Provável:** código mais relato consistente.
- **(aposta):** sem medição pública.

| # | O que fazer | Ganho | Certeza |
|---|---|---|---|
| 1 | Não mexer na "senha da conversa", que o motor já usa | É o que impede que cliente antigo conte como contato novo. A causa dos 463 que sobram é restrição real, não falha do motor. | Comprovado |
| 2 | Não cortar o histórico pedido ao conectar o número | As senhas das conversas existentes chegam por esse histórico. Cortar faria clientes antigos parecerem novos. | Comprovado |
| 3 | Aviso imediato do motor quando a Meta restringe (463, 475, trava temporária, cota) | O alerta do #1725 chega na hora também na caixa comum, não só no Híbrido. | Comprovado |
| 4 | Perguntar ao motor "este contato tem senha válida?" antes de enviar | O disjuntor do #1725 passa a contar pela régua real do WhatsApp, não pela do CRM, e medimos quantos envios saem como contato novo. Só lê o banco da própria sessão; não manda nada ao WhatsApp. | Provável |
| 5 | Não reenviar depois de recusa por contato novo | Cada nova tentativa conta como mais uma abordagem. O Híbrido já faz isso. Falta conferir a caixa comum. | Comprovado no Híbrido |
| 6 | Trava no próprio motor durante a restrição: segura só envio para conversa nova; conversa que já existe passa normal | Cobre a caixa comum, onde as travas do chat2you não passam. O WhatsApp Web faz igual. Começa só registrando. | Provável |
| 7 | Registrar e avisar quando alguém tenta desconectar ou religar por QR durante uma restrição | Religar não tira a restrição e apaga as senhas das conversas. Começa só registrando. "Pausar" nunca é bloqueado. | Provável |
| 8 | Religar as sessões aos poucos depois de cada atualização, e reconectar sem laço | Como os dois motores sobem juntos, evita todas as contas reconectando no mesmo segundo pelo proxy. | Provável na estabilidade. Contra bloqueio, (aposta) |
| 9 | Proxy obrigatório: sessão sem proxy não conecta | Impede, mesmo por erro de configuração, várias contas saindo pelo mesmo IP do servidor. | Provável |
| 10 | Contato que vira "novo" depois de religar por QR: testar num número de teste se um histórico maior recupera as senhas. No Híbrido, preferir a API oficial enquanto o contato estiver sem senha | Evita recusas falsas em clientes antigos por até 7 dias depois de cada religação. O incidente de 13/10 é um caso desses. | Provável |
| 11 | Rotina para reaplicar a customização sobre cada versão nova do WAHA em dias, não em meses | Versão velha do motor é recusada pela Meta como "cliente desatualizado" e perde correções. É o principal risco novo da customização. | Obrigatório. Contra bloqueio, (aposta) |
| 12 | "Digitando…" com tempo proporcional ao texto também na caixa comum | Tira um padrão fixo de robô. | (aposta) |
| 13 | "Gravando áudio…" antes de mandar voz | Coerência humana: ninguém digita um áudio. | (aposta) |
| 14 | Prévia de link desligada também na reserva do Híbrido | A mensagem fica com cara de pessoa, não de disparo. | (aposta) |
| 15 | Cruzar as quedas "aparelho removido" (ex.: caixa 118) com os avisos de restrição | Se casarem, tratar a queda como restrição, e não religar por cima. Só leitura de log. | (aposta) |

---

## 3. O que NÃO vale a pena ou é arriscado

| Item | Por quê |
|---|---|
| Forçar botões no motor | O motor não tem botões, e é justamente o formato que a Meta passou a barrar em número não oficial. |
| Reescrever a "senha da conversa" | Já funciona. Mexer criaria risco de quebrar o envio de todas as caixas, sem ganho. |
| Copiar a "recuperação do 463" de outra biblioteca | O aplicativo oficial não faz isso, e não traz a senha do contato. |
| Fila ou intervalo forçado no motor | É um teto disfarçado, sem prova de que protege. Atrasa todas as caixas e pode duplicar mensagem. |
| Trocar o nome e o sistema do aparelho (ex.: "Chrome no Windows") | Sem prova de ganho. Cria uma identidade incoerente e muda o login de todas as sessões ao mesmo tempo. |
| Postar status "para parecer normal" | Folclore. O status vai para todos os contatos do cliente e pode gerar denúncia. |
| Desligar a sessão à noite | Cada religar é um login novo, e o Híbrido precisa estar conectado. |
| Ficar "online" o tempo todo | Corta as notificações no celular do dono, e não há prova de que protege. |
| Marcar como lida quando o atendente só abre a conversa | Tira o "não lida" do celular do dono, e não há prova de que protege. |
| Conferir número por número em massa | O Híbrido já confere um por vez. Consultar em massa parece varredura. |
| Encaminhar mensagem em automação | O motor marca como "Encaminhada", e encaminhamento em volume é sinal clássico de spam. |
| Enviar localização ao vivo, fixar mensagem, favoritar | O motor não tem. Teria de ser escrito do zero para pouco ganho. |
| Enviar visualização única ou mensagem temporária | O motor não tem, e apagaria o histórico que o atendimento precisa guardar. |
| Menções, etiquetas no celular, canais | Fora do atendimento individual. Só se virar produto. |

---

## 4. Ordem sugerida

**Pacote 1:** junto com o #1709 e o #1725. Os dois motores entram juntos no ar, depois da implementação, revisão e testes.

- **Base, antes de qualquer coisa:**
  - Travar a customização na versão exata que está no ar (marcação 120a614) e conferir a impressão digital do motor da imagem oficial. Se não bater, a montagem para.
  - Deixar pronta a rotina de atualização.
- **Blindagem:**
  - Itens 3, 4, 5 e 14.
  - Itens 6 e 7, só registrando nesta fase.
  - Item 8, religar aos poucos.
  - Itens 12 e 13, com chave.
- **Mandar:**
  - Lista, localização, contato e enquete, com o voto voltando ao painel.
  - Foto e vídeo sempre como mídia.
  - Na reserva do Híbrido: responder citando e apagar.
- **Receber:**
  - Código da opção da lista.
  - Ligação como aviso de atividade.
  - Tipo desconhecido visível, álbum sem bolha extra e áudio com nome.

**Pacote 2:** depois de umas semanas medindo o Pacote 1.

- Reações, nos dois sentidos, junto com o ajuste da IA.
- Editar, nos dois sentidos.
- Localização e contato recebidos como cartão.
- Citação antiga, mídia que falha ao baixar, selo de apagada, aviso de mensagem temporária e figurinha.
- Itens 6 e 7 passam a barrar de verdade, só com a medição na mão. O botão "reconectar" ganha a opção "forçar".
- Item 9, proxy obrigatório, ligado só depois de conferir que 100% das sessões têm proxy.
- Reconexão com espera variável.

**Depois, ou só com teste antes:**
- Convite de evento.
- Visualização única.
- Teste de histórico maior num número de teste (item 10).
- Cruzamento das quedas com as restrições (item 15).

**Decisões suas:**
1. No Híbrido, quando o contato não tiver senha válida, mandar pela API oficial em vez da reserva? O contato novo continua livre de qualquer forma.
2. Mensagem apagada pelo cliente continua visível para prova? A recomendação é que sim.
3. O que fazer com foto de visualização única.

---

## 5. O que não muda nada do que já funciona hoje

- A customização parte exatamente do motor que está no ar. Se a imagem oficial não bater, a montagem para antes de ir para o ar.
- Cada novidade tem chave por caixa. Desligada, a caixa funciona como hoje.
- Contato novo continua livre, sem teto diário e sem fila.
- Conversa que já existe nunca passa por trava nova.
- As travas novas do motor começam só registrando. Nada é barrado na primeira fase.
- "Pausar" a sessão continua funcionando sem desconectar, e o botão "reconectar" segue igual.
- As senhas das conversas ficam intactas.
- O número não fica "online" permanente, então as notificações no celular do dono continuam.
- Grupos, status e canais continuam ignorados.
- A sessão do Híbrido continua sem ponte com o painel. Tudo o que o cliente manda segue chegando pela API oficial.
- O conversor de texto não muda.
- A caixa comum continua marcando como lida e mostrando "digitando" antes de responder.
- Para voltar atrás, basta trocar de volta para a imagem oficial atual, que fica guardada.

---

**De onde vem cada fato:**
- Código público do WAHA (marcação 2026.9.2) e do motor GOWS (v1.0.47, igual à v1.0.48).
- O whatsmeow usado pelo motor (versão 22e2b8a).
- O chat2you (origin/main 5549999d11).
- A documentação waha.devlike.pro, nas páginas how-to-avoid-blocking e sessions.
- Relatos de terceiros, tratados como relato e não como fato: WAHA #2050, whatsmeow #1197, #1074 e #810, Baileys #2441.

Algumas leituras foram feitas na v1.0.49, que não está no ar. Antes de virarem código, precisam ser conferidas na versão de produção: a nova consulta de restrição depois do 463, a conexão por proxy e o tempo entre reconexões.

---

## 6. Fase 3 no chat2you (16/10/2026, branch do #1709)

Feito no chat2you, atrás da flag `whatsapp_rich_native` (desligada = igual a hoje). Na caixa comum, cada item só
funciona com o conector `c2y-rich-2`; o lado do conector é outro trabalho (`infra/waha-c2y/`). Detalhes, contrato e
desvios em `docs/audit/2026-10-16-1709-ricas-waha-fase3.md`.

| Item | Caixa comum | Reserva do Híbrido |
|---|---|---|
| Enquete e voto de volta ("Votou: X") | Sim | Sim (ligar a flag reinicia a sessão uma vez) |
| Foto e vídeo como mídia | Pedido ao conector | Foto fora de JPG/PNG vira JPEG; GIF vira vídeo |
| Responder citando | Já existia | Sim |
| Apagar para todos | Já existia | Sim |
| Ligação perdida ou recusada como aviso | Sim | Não se aplica (a Cloud recebe) |
| Mensagem desconhecida visível | Sim | Não se aplica |
| Reações nos dois sentidos | Sim (botão "Reagir") | Fora deste pacote |
| Edição nos dois sentidos | Sim (até 14 min, botão "Editar") | Fora deste pacote |
| Formatação pelo mesmo renderer da Cloud | Sim (regras completas com o #1740) | Já usava o texto do painel |
