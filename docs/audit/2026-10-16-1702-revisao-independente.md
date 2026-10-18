# #1702 — revisão independente da conversa com a cara do WhatsApp

Data: 16/10/2026. Quatro revisores em paralelo, pedidos "bem críticos": R1 ganchos no
Chatwoot, R2 servidor e segurança, R3 lógica, R4 UX. Abaixo, cada achado com o destino.

## Corrigido

| Revisor | Severidade | Achado | Correção |
|---|---|---|---|
| R1, R3 | Bloqueia | A seta do gravador não enviava (o watcher não via `push`) | O envio sai do `attachFile`, só na mesma conversa; o pedido é esquecido em cancelar, erro e troca de conversa. 3 specs |
| R3 | Bloqueia | Formulário podia sair em dobro, ou depois de cancelar | Trava de envio, número por abertura da janela, resposta atrasada ignorada, `:key` por abertura |
| R3 | Bloqueia | Recusa do servidor (422) nunca aparecia | O "+" espera `sendMessageWithData` e mostra o motivo dentro da janela, que só fecha com 2xx. Spec |
| R3 | Bloqueia | Spec do telefone vermelho | Regra nova (+ e código do país, 8 a 15 dígitos) e spec atualizado |
| R3 | Alta | Limites da Meta não conferidos na tela | Todos conferidos: botão 20, URL http(s) até 2000, opções 20/24, repetidas, até 10, lista 20, mensagem 1024/4096, lugar 100/300, contato 100, botão do formulário 30, nome cortado em 60. Specs |
| R3 | Alta | Link do Maps lia o centro da tela (@) antes do ponto (!3d!4d) | Ordem invertida; decimal estrito (sem `1e1`, `0x10`, `Infinity`); `decodeURIComponent` protegido. Specs |
| R3 | Alta | Corrida e erro ao escolher endereço | Número por pedido, coordenada limpa antes, erro mostrado |
| R3 | Alta | Formulário aparecia no modo texto | Só aparece quando sai nativo (Cloud API e fora do número reserva) |
| R1, R3 | Média | 360dialog tratado como nativo | Tudo que não é Cloud API sai em texto e a prévia mostra o texto |
| R3 | Média | Busca com corrida e Esc fechando a janela | Buscas antigas descartadas ao escolher/apagar; Esc fecha só a lista |
| R3 | Média | Clique no "+" reabria o menu; foco perdido | Clique-fora ignora o "+"; foco volta ao "+" ao fechar a janela |
| R1 | Alta | Assinatura escondia o microfone | Usa `hasMeaningfulEditorContent` (a assinatura não conta) e anexos |
| R1 | Média | "+" fora do `setReplyToInPayload` | Resposta citada e assunto do CRM vão juntos. Spec |
| R1 | Média | "Escolher modelo" sem modelo na caixa | Botão só aparece com modelo sincronizado |
| R1 | Média | Custo por mensagem com a chave desligada | Carrossel com `v-if`; fuso fornecido uma vez pela conversa (sem `useAccount` por mensagem); dias em `computed`; formatadores reaproveitados |
| R3 | Média | "Hoje" não virava "Ontem" à meia-noite | Relógio único compartilhado, de minuto em minuto |
| R3 | Baixa | Botões de modelo de outro idioma; botões em mensagem que falhou | Só o idioma gravado; nada em mensagem com falha; `role=group` |
| R3 | Baixa | Pausa por palpite local | Lê `isPaused()` do gravador |
| R3 | Baixa | Texto do WAHA com link diferente do servidor | Usa `mapHrefOf`, o mesmo do servidor |
| R3 | Baixa | Idioma `pt_BR` → Intl | `idiomaDoPainel` |
| R2 | Alta | Download do formulário sem trava (SSRF), erros de rede viravam 500 | Só https da Meta, sem redirecionamento, teto de 2 MB; erros viram frase. Specs |
| R2 | Média | Custo do Google, ids sem validação, sem WABA, paginação, logs | `sessionToken`, limite por IP, cache, id validado, recusa sem WABA, limite 100, código da Meta no log. Specs |
| Híbrido | — | Fora das 24 h só texto | Menu avisa, "Foto, vídeo ou documento" some, microfone some |

## Não corrigido agora, com motivo

| Achado | Motivo |
|---|---|
| Seletores de classe frágeis (R4) | Os ganchos são classes do Chatwoot; trocar por `data-*` exige editar mais arquivos do Chatwoot, contra a regra de construção aditiva. Fica no plano de atualização |
| Erro 131047 em inglês (R4) | Já tratado pelo PR #1663 (MessageError) |
| Nome "Agente de IA" no balão do robô (R4) | Mantido pela decisão #1668 (Agentes IA e Rodrigo) |
| Mídia real no carrossel, "Termina em" da oferta, foto dos botões no envio | Dependem de dado que a mensagem não guarda; follow-up combinado com Modelos WhatsApp |
| Caixa de resposta em 3 faixas no celular, tokens no lugar de hex | Ajuste visual, próxima rodada |
| ReplyBox (+~80) e ReplyBottomPanel (+~55) acima da meta de 20 linhas (R1) | Toda a lógica nova está em arquivos próprios; o que ficou são os pontos de ligação. Reduzir mais exige reescrever trechos do Chatwoot |
| Specs de componente com a pele ligada no ReplyBox | O hook está coberto com a pele ligada e desligada (`usePeleDaResposta.spec.js`); o ReplyBox com a chave desligada também. O visual ligado está nos prints |

## Validação

- vitest focado: conversa-canal 25/25; ReplyBox 99/99 (6 novos).
- rspec no M2 (snapshot): conversa_canal + modelo usado 20/20; rubocop 11 arquivos sem ofensa.
- eslint sem erro; `i18n:fork:check` ok.
