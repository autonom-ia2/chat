# #1709: mensagens ricas pelo WhatsApp API (Híbrido e WAHA customizado)

Escopo e termos de aceite aprovados pelo Rodrigo em 16/10/2026.

**Onde vale:**
- caixa **WhatsApp Híbrida**, quando a mensagem sai pelo número conectado fora das 24 h;
- caixa **WAHA**, com o motor WAHA customizado (`infra/waha-c2y/`).

Tudo fica atrás da flag por conta `whatsapp_rich_native`. **Sem a flag, nada muda.**

Situação: **Pronto** = no PR #1741 · **Rodada 1** = em construção · **Rodada 2** = começa ao fim da rodada 1.

## 1. Envio pelo chat2you

| O atendente ou a IA manda no chat2you… | O cliente recebe no WhatsApp | Situação |
|---|---|---|
| Pergunta com opções | Lista de verdade ("Ver opções"): o WhatsApp não aceita botões de número não oficial | Pronto |
| Localização | Mapa clicável | Pronto |
| Contato | Cartão de contato | Pronto |
| Enquete | Enquete nativa para votar | Rodada 1 |
| Foto ou vídeo, qualquer formato | Sempre como foto ou vídeo, nunca como arquivo | Rodada 1 |
| Resposta citando mensagem (híbrida) | A resposta citando a mensagem dele | Rodada 1 |
| Apagar mensagem enviada (híbrida) | A mensagem some do WhatsApp dele | Rodada 1 |
| Reação com emoji | A reação na mensagem dele | Rodada 1 |
| Edição até ~15 min depois | A mensagem corrigida, marcada "editada" | Rodada 1 |
| Negrito, itálico, riscado, código | Formatação certa no celular | Rodada 1 |
| Botão de link ("Acessar site") | Cartão de prévia do link (título, imagem, descrição) | Rodada 2 |
| Convite de evento (data e hora) | Convite com "Vou / Não vou" (depende de teste no motor) | Rodada 2 |

**Limites do WhatsApp para número não oficial.** Estes casos continuam como hoje e só funcionam pela API oficial:
- botões de resposta (pelo WAHA viram lista);
- pedido de localização (pelo WAHA sai como texto pedindo);
- formulário (Flow): recusado;
- modelos aprovados com botões.

## 2. Recebimento no chat2you

**Caixa híbrida:** o que o cliente manda chega pela API oficial e aparece como na oficial. Nada muda.

**Caixa WAHA:**

| O cliente manda no WhatsApp… | Aparece no chat2you | Situação |
|---|---|---|
| Escolha numa lista | "O cliente tocou em X", ligado à pergunta | Pronto |
| Voto em enquete | "Votou: X", que muda se ele trocar | Rodada 1 |
| Reação | Colada na mensagem; a IA não responde | Rodada 1 |
| Mensagem editada | Só a nova, com a antiga guardada; a IA não responde à velha | Rodada 1 |
| Ligação não atendida | Aviso: ligação perdida ou recusada | Rodada 1 |
| Algo que o sistema não reconhece | Bolha visível "abra no celular" | Rodada 1 |
| Áudio de voz | Mensagem de voz com player | Rodada 2 |
| Várias fotos de uma vez | Fotos agrupadas, sem bolha vazia | Rodada 2 |
| Localização | Cartão de mapa, igual à oficial | Rodada 2 |
| Localização ao vivo | Mapa com aviso "ponto inicial" | Rodada 2 |
| Contato | Cartão de contato | Rodada 2 |
| Resposta citando mensagem antiga | Ligada à mensagem citada, ou com o trecho dela | Rodada 2 |
| Foto ou arquivo que falha ao baixar | Nova tentativa e, se falhar, aviso visível "peça para reenviar" | Rodada 2 |
| Mensagem que o cliente apagou | Selo "apagada pelo cliente"; conteúdo mantido para prova | Rodada 2 |
| Mensagem temporária | Aviso de conversa temporária; conteúdo mantido | Rodada 2 |
| Figurinha | Figurinha | Rodada 2 |
| Visualização única | Recebida e **gravada**, com selo (decisão de negócio). Se o WhatsApp não entregar a mídia ao motor: bolha visível "abra no celular", com a prova da limitação | Rodada 2 |

## 3. Termos de aceite: quando consideramos tudo entregue

A entrega só está concluída quando **todos** os itens abaixo estiverem cumpridos e registrados com evidência na Issue #1709.

### A. Construído e revisado
- [ ] Todos os itens das tabelas 1 e 2 implementados no chat2you e no conector WAHA.
- [ ] Revisão adversarial independente de cada rodada, com todos os achados críticos, altos e médios fechados (ou recusados com justificativa registrada).
- [ ] Revisão final do branch inteiro aprovada.

### B. Testado sem tocar produção
- [ ] Testes automáticos de cada item, no chat2you e no conector, passando.
- [ ] Suíte ampla do chat2you sem falha nova em relação à `main`.
- [ ] Imagem do WAHA montada sobre a waha-plus de produção, com os arquivos alterados conferidos por hash dentro da imagem.

### C. "Nada do que existe quebra"
- [ ] Com a flag desligada, enviar e receber continua igual à `main`, provado por testes, inclusive com o conector novo.
- [ ] Caixas WAHA de contas sem a flag: texto, mídia, ack (tiques) e a IA funcionando como hoje depois da troca de imagem.
- [ ] Outros usos da API de caixa (n8n, integrações) inalterados.

### D. Testado de verdade no celular
Motor de teste ou número descartável, nunca número de cliente. Para cada linha das tabelas 1 e 2:
- [ ] Envio: o cliente recebe como descrito, no Android, no iPhone e no WhatsApp Web.
- [ ] Recebimento: o que o cliente manda aparece no chat2you como descrito.
- [ ] Sem mensagem duplicada; tiques de entregue e lida funcionando.
- [ ] Falhas simuladas (motor recusa ou não responde) se comportam como prometido: texto uma vez, ou "não confirmada" sem reenvio.
- [ ] Visualização única: resultado documentado (gravada, ou limitação provada).
- [ ] Convite de evento: resultado documentado (funciona, ou limitação provada).

### E. Produção, com OK do Rodrigo em cada passo
- [ ] Merges na ordem da Orquestração (#1729 → #1726 → #1724 → #1741), cada um com "ok merge N".
- [ ] Deploy do chat2you com a flag desligada; conferência de que nada mudou.
- [ ] Troca da imagem nos motores wa-hub e wa-autonomia, com cópia de segurança, volta escrita e conferência de saúde das sessões.
- [ ] **Pré-requisito da flag:** o dono do token gravado em cada caixa WAHA das contas piloto
  (`channel_api.additional_attributes.account_token_owner_user_id`, operação 8: `psql` com backup antes, OK do Rodrigo).
  Com a flag ligada, a caixa sem esse registro não aceita evento do conector de ninguém, nem de administrador
  (`Waha::RichNative::Inbound.from_connector?`): reação, edição, voto e o resto chegam como texto comum.
- [ ] Motores habilitados (`WAHA_RICH_NATIVE_ENGINES`) e flag ligada nas contas piloto.
- [ ] Teste final no piloto, em envio e recebimento, aprovado pelo Rodrigo.
- [ ] Pendente, fora deste PR: prévia de link (`linkPreview`) na caixa WAHA, como operação separada com o OK do Rodrigo,
  só depois de confirmar no código do GOWS como o motor busca a página (rede, proxy, bloqueio de IP privado; risco de
  SSRF se o robô repetir um link do cliente).

### F. Fechamento
- [ ] Documentação atualizada: resumo do Híbrido, README do motor, rotina para reaplicar o ajuste em cada versão nova do WAHA.
- [ ] Limpeza feita: worktrees, snapshots e bancos de teste; Docker temporário do M2 removido.
- [ ] Projeto Autonom.ia Dev atualizado e Issue #1709 fechada.
