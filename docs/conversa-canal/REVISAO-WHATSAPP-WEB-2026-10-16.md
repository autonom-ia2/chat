# Revisão da conversa: WhatsApp Web × nossa pele (#1702)

16/10/2026. Objetivo: deixar a nossa área de conversa o mais parecida possível com o WhatsApp Web de hoje.

## De onde vêm os dados

| Fonte | O que deu | Confiança |
|---|---|---|
| Vídeo `~/Documents/whatsapp_video.mov` (3 min, 2926×1760, tema claro e escuro) | 362 quadros a cada 0,5 s; 179 diferentes entre si foram lidos um a um, em 4 lotes | Medidas e cores **estimadas** (quadro em JPEG, 1 px ≈ 1 px CSS) |
| REA (`rea-agents` 6.5.0) no Chrome do Rodrigo, aba WhatsApp Business, só leitura | Duas capturas exatas (3024×1610, escala 2), uma no escuro e outra no claro, e a árvore de acessibilidade com os rótulos reais dos controles | Cores dos dois temas **medidas no pixel**; rótulos **observados** |
| Inventário do código da branch `feat/1702-conversa-whatsapp` (HEAD `d554fad090`) | O que a pele desenha hoje, com arquivo e linha | Leitura do código |

Os catálogos completos, quadro a quadro, ficaram no scratchpad da sessão (`watch-wa/catalogo-1..4.md`); este documento é a síntese.

## A mudança grande: o WhatsApp Web de 2026 não é o de 2023

A nossa pele copiou a paleta e o layout do WhatsApp Web antigo. O de hoje mudou em pontos que se veem de longe:

1. **Tema escuro é cinza neutro, não azul-petróleo.** Medido pelo REA: fundo e cabeçalho `#161717`, balão recebido `#242626`, compositor `#242626`. Nós usamos `#0B141A` (fundo), `#202C33` (cabeçalho e balão recebido) e `#005C4B` (enviado). O enviado de hoje no escuro fica perto de `#144D37` (medido `#184A2D`–`#194A2F` no vídeo).
2. **Cabeçalho da cor do fundo.** Claro: branco `#FFFFFF` com linha quase invisível. Escuro: `#161717`, sem faixa. Nós pintamos a faixa cinza antiga (`#F0F2F5` / `#202C33`).
3. **Compositor é uma pílula flutuante** de ~48 px, raio total, sobre o próprio papel de parede (sem faixa atrás). Dentro dela: "+", figurinha, "Digite uma mensagem" e microfone. Nós temos a faixa cinza com campo branco `rounded-lg` e ícones fora do campo.
4. **Botões de ação são pretos, não verdes.** Enviar, gravar (hover), FAB da lista e da enquete e o botão "Convidar": círculo preto `#111` com ícone branco. Nós usamos verde `#00A884` no microfone e no enviar.
5. **Enquete em preto:** rádio marcado e barra cheia em preto no claro (`#161616`) e branco no escuro (`#FAFAFA`, medido). Trilho `#E1E1E1` / `#3A3C3C`.
6. **Separador de data com dd/mm/aaaa** para datas antigas e dia da semana **em minúsculas** ("sábado", "terça-feira"); "Hoje" e "Ontem". E ele **gruda no topo** enquanto rola.

## Tema claro medido pelo REA (16/10, 14:10)

Segunda captura, com o WhatsApp Web no claro (mesma conversa: enquete, localização e contato). Viewport 1512×805 px CSS, escala 2.

- **O claro também ficou neutro.** Texto `#0A0A0A` e cinza secundário `#666666`, sem o azulado antigo (`#111B21` / `#667781`). Papel de parede `#F4F1EC` com o desenho em `#EDE7DE`.
- Barra lateral de ícones `#F7F5F3`; chip de filtro ativo ("Tudo") `#F0EEEB`. Lista de conversas branca.
- Enquete: ✔ e barra cheia `#171616`; trilho e linha acima de "Mostrar votos" `#E5E5E5`; "Mostrar votos" e o link da localização no mesmo verde (`#418559` no pixel mais escuro).
- Contato: círculo do avatar padrão `#E0FCD6` com ícone verde; nome 15 px semibold.
- **Encaminhar ↪ fica visível também ao lado da localização e do contato**, não só de mídia e link.
- Cabeçalho 64 px; compositor 52 px de altura, raio total, branco, sem faixa atrás.
- Bolhas recebidas começam ~60 px depois da borda do painel da conversa nesta largura.

Medição: cor = moda da área (fundos) ou pixel mais escuro do traço (texto, ícone); tamanho = sequência de pixels brancos dividida pela escala. Texto com antialias pode ser um pouco mais escuro que o medido.

## Paleta de referência

| Peça | Claro | Escuro | Nós hoje (claro / escuro) |
|---|---|---|---|
| Papel de parede | `#F4F1EC` com desenho `#EDE7DE` (REA) | `#161717` (REA) | `#EFEAE2` / `#0B141A` |
| Cabeçalho | `#FFFFFF` (REA), 64 px | `#161717` (REA) | `#F0F2F5` / `#202C33` |
| Balão enviado | `#D9FDD3` | ~`#144D37` | `#D9FDD3` / `#005C4B` |
| Balão recebido | `#FFFFFF` (REA) | `#242626` (REA) | branco / `#202C33` |
| Cartão dentro do balão (documento, prévia de link, ligação) | enviado `#D1F4CC`; recebido `#F4F2F3` | enviado ~`#123C26` | não existe |
| Texto | `#0A0A0A` neutro (REA) | `#E9EDEF` | `#111B21` (azulado) |
| Texto secundário, hora, rádio vazio | `#666666` neutro (REA) | `#8696A0` | `#667781` (azulado) |
| Tique lido | `#53BDEB` | `#53BDEB` | `#7EB6FF` (lucide) |
| Tique entregue | `#8696A0` | `#8696A0` | `text-n-slate-10` |
| Link no texto | verde sublinhado `#418559` (REA, pixel mais escuro) | `#21C063` | estilo do Chatwoot |
| Separador de data | fundo `#FFFFFF`, texto `#54656F` | fundo ~`#1D1F1F`, texto `#8696A0` | branco / `#182229` |
| Compositor (pílula) | `#FFFFFF`, 52 px de altura (REA) | `#242626` (REA) | faixa `#F0F2F5` + campo branco |
| Botão de descer | `#FFFFFF` (REA) + sombra | `#242626` (REA) | não existe |
| Botões de ação (enviar, FAB) | `#111111` | (não visto) | verde `#00A884` |
| Enquete: barra cheia, ✔ marcado / trilho e linha do rodapé | `#171616` / `#E5E5E5` (REA) | `#FAFAFA` / `#3A3C3C` (REA) | — |
| "Mostrar votos", "Ver opções", "Conversar" | verde `#418559` (REA, pixel mais escuro) | `#5CBD6D` (REA) | azul `#027EB5` nos botões |
| Áudio: ponto e microfone "não ouvido" | `#53BDEB` / `#3DC6FA` | `#53BDEB` | verde `#00A884` (ponto) e azul depois de ouvido |
| Aviso da Meta (empresa) | caixa `#D5F4EE` | — | não existe |
| Aviso de criptografia | — | texto amarelo `#D1B161` em caixa escura | não existe |

## Medidas de referência

| Peça | WhatsApp Web | Nós hoje |
|---|---|---|
| Cabeçalho | 60–62 px, avatar 40 px, nome 16 px, subtítulo 13 px | 60 px, conteúdo do Chatwoot |
| Margem das bolhas até a borda do painel | ~58 px (recebida) / ~50 px (enviada) | `px-[6%]` + coluna do avatar escondido (~32 px a mais do lado do enviado) |
| Largura máxima de texto | ~57–65% do painel (~503–527 px num painel de 918 px) | `max-w-lg` (512 px) fixo |
| Largura de mídia, áudio, documento, enquete, contato | ~320 px (imagem retrato ~233 px; altura máx. ~330 px) | foto 300 px; áudio 280/340 px; contato 280 px; opções 300 px |
| Raio do balão / do cartão interno | 7,5–8 px / 6 px | 7,5 px / — |
| Bico | 8×13 px, só no 1º balão da sequência | igual (SVG 8×13) |
| Espaço entre balões do mesmo remetente | 2–4 px | 8 px (`mb-2`) em todos |
| Espaço na troca de remetente | ~12 px | 8 px |
| O que quebra a sequência | troca de remetente (e separador de dia) | troca de remetente **ou de minuto** |
| Texto | 14,2 px / 19 px; recheio 6/7/8/9 | igual |
| Hora | 11 px, inline no fim da última linha; sobre a foto quando não há legenda | inline no texto; nos outros tipos em linha própria; nunca sobre a foto |
| Separador de data | ~24–26 px, recheio 5×12, raio 7,5, 12,5 px | igual no tamanho; texto e "grudar no topo" diferentes |
| Compositor | pílula 48 px, raio 24 px, ~10 px das bordas | faixa + campo |
| Botão de descer | círculo 40–42 px, ~15–20 px da direita, ~38 px acima do compositor | não existe |
| Menu "+" | **~156 px de largura, itens de ~34,5 px, texto 14,5 px, ícone 18–20 px, raio 12–16 px** | 272 px (`17rem`), itens de 48 px, texto 16 px, ícone 24 px |

## Tipo por tipo

Legenda: **Igual** (já bate), **Ajustar** (existe, mas difere), **Falta** (não existe).

| Tipo | WhatsApp Web (o que ver) | Nós | Situação |
|---|---|---|---|
| Texto curto e longo | Hora inline; quebrou, a hora vai para o canto da última linha | Igual | Igual |
| Texto longo com "Ler mais" | Não apareceu no vídeo | Não existe | Sem prova; fora |
| Só emoji | Emoji grande (~52 px) **sem balão**; hora pequena embaixo | Balão normal | Falta |
| Link | Verde sublinhado; abre em aba nova | Estilo do Chatwoot | Ajustar |
| Prévia de link | Cartão dentro do balão (fundo mais escuro): imagem OG em cima (opcional), título 14 px semibold, descrição 13 px, domínio; abaixo a URL verde e a hora | Não existe (o servidor não guarda a prévia) | Falta |
| Foto | Moldura de 3 px, raio interno 6 px, retrato corta em ~330 px; **hora e tiques brancos sobre a foto** com degradê; selo "HD"; ao passar o mouse, chevron no canto | Moldura certa; hora numa linha embaixo; botões expandir/baixar do Chatwoot | Ajustar |
| Foto com legenda | Foto em cima (~316 px), legenda embaixo, hora na linha da legenda | 300×220 px fixo, resto igual | Ajustar (proporção real) |
| Vídeo | Miniatura com play central de 48 px, "HD" + duração embaixo à esquerda, hora sobre o vídeo; abre no visualizador | `<video controls>` nativo | Falta (miniatura + play) |
| Álbum | 2+ fotos no mesmo balão, uma hora só | Fotos separadas | Falta |
| Documento | Cartão interno: ícone por tipo (PDF vermelho com "PDF"), nome 15 px, "12 páginas • PDF • 107 KB" 12 px, botão baixar à direita (some depois de baixado); legenda e hora embaixo | Cartão do Chatwoot ("fulano compartilhou um arquivo"), botão vira linha azul por engano | Falta (cartão do WhatsApp) |
| Áudio recebido | Play · ponto azul · onda cinza · **foto à direita** com microfone azul (não ouvido); duração e hora embaixo | Foto à direita, microfone verde; ponto verde; hora numa terceira linha | Ajustar |
| Áudio enviado | **Foto à esquerda** com microfone; onda verde-acinzentada | Foto sempre à direita | Ajustar (espelhar) |
| Áudio tocando | A foto vira "1,0× / 1,5× / 2,0×"; pausa; ponto andando; tempo decorrido | Igual (1× / 1,5× / 2×) | Ajustar o rótulo para "1,0×" |
| Áudio enviando | Círculo com × e anel de progresso; tamanho ("11 KB") no lugar da duração; relógio | Não existe | Falta |
| Ligação perdida | Cartão interno com círculo branco e telefone vermelho, "Ligação de voz perdida", "Clique para retornar" | Não chega como balão | Falta (depende do servidor) |
| Citação (resposta) | Faixa colorida à esquerda **com o nome de quem foi citado** (cor por contato; "Você" em verde) e 1 linha cinza; áudio citado vira "🎤 0:04"; o balão encolhe para o conteúdo | Faixa verde, sem nome e sem miniatura | Ajustar |
| Encaminhada | Não apareceu no vídeo | Não existe | Sem prova; fora |
| Apagada | 🚫 + "Mensagem apagada" em itálico cinza, sem tiques | Texto do servidor, sem itálico nem ícone | Ajustar |
| Reação | Não apareceu aplicada no vídeo (só o botão de reagir) | Não existe | Ver "Ações ao passar o mouse" |
| Figurinha | Não apareceu | Vira foto dentro do balão | Sem prova; fora |
| Enquete | Título 16 px negrito; "Selecione uma opção" / "uma ou mais opções"; opções de ~54 px com rádio, contagem e barra; "Mostrar votos" separado por linha (cinza quando 0 votos); painel lateral "Dados da enquete" | Não existe | Falta |
| Localização | Mapa real (Google estático) ~258×144 px, pino; nome como link verde sublinhado; abre o Google Maps | Mapa falso (grade + pino) e "Ver no mapa" em linha azul; recebida sem `shared_location` fica no cartão do Chatwoot | Ajustar |
| Contato | Foto 46 px, nome 15 px semibold; rodapé com **"Conversar" e "Salvar contato"** lado a lado em verde | Enviado: foto 48 px e nome; recebido: cartão do Chatwoot | Ajustar |
| Lista ("Ver opções") | Cabeçalho negrito, corpo, rodapé cinza; botão "☰ Ver opções" verde; abre **janela por cima** (fundo escurecido, ~417 px, raio 16–20 px) com seção, linhas com descrição e rádio à direita; escolher mostra o FAB preto de enviar | Botão de linha; a lista abre **logo abaixo**, sem janela | Ajustar |
| Resposta da lista | Balão enviado citando a lista (nome do remetente colorido) + título e descrição da linha escolhida | Linha "escolhida" no balão de opções | Ajustar |
| Botões de resposta | Não apareceram no vídeo | Caixas separadas por botão | Sem prova nova |
| Modelo com botões | Não apareceu no vídeo | Botões dentro do balão | Sem prova nova |
| Aviso da Meta / criptografia | Caixa centralizada ~458 px (verde-água no claro; amarela no escuro) | Não existe | Falta (só se o canal mandar) |
| Mensagem que falhou | Não apareceu | Balão rosa + erro solto sobre o fundo | Ajuste já anotado no HANDOFF (131047) |

## Ações ao passar o mouse

| Peça | WhatsApp Web | Nós |
|---|---|---|
| Chevron ⌄ do menu | **Dentro** do balão, canto superior direito, só no hover (branco com degradê sobre mídia) | Não existe; menu só com clique direito |
| Reagir 🙂 | Círculo ~26–30 px **fora** do balão, centralizado na altura: à esquerda do enviado, à direita do recebido; só no hover | Não existe |
| Encaminhar ↪ | Mesmo círculo, ao lado do reagir; **sempre visível** em mídia e link, nunca em texto | Não existe |
| Botões da foto | Só o chevron | Expandir + baixar do Chatwoot |

Reagir e encaminhar dependem de o produto aceitar reação e encaminhamento pelo canal. Sem isso, entra só o chevron, que abre o nosso menu.

## Compositor e menus

- **Repouso:** pílula com "+" (24 px), figurinha, campo e microfone. Hover nos ícones: círculo cinza de ~36 px.
- **Com texto:** o microfone vira enviar (círculo preto).
- **Gravando** (já está parecido): lixeira, ponto vermelho `#EA0038`, tempo, onda ao vivo **cinza**, pausa vermelha num círculo rosado, "1" de visualização única e enviar preto. Pausado: play para ouvir, tempo à direita e o microfone vermelho para continuar. Diferenças nossas: enviar verde; sem visualização única.
- **Menu "+"**: itens Documento, Fotos e vídeos, Câmera, Áudio, Contato, Enquete, Nova figurinha, linha, Catálogo, Resposta rápida. As cores dos nossos itens batem com as do original. O tamanho não: o original é bem mais compacto (ver tabela de medidas).
- **Janelas** (Enviar contatos, Criar enquete, Ver opções): cartão branco de ~418×704 px, raio 24 px, **preso à esquerda do painel da conversa**, fundo escurecido, campos só sublinhados, FAB preto de enviar. A nossa `JanelaDoMais` usa outro desenho.
- **Prévia antes de enviar foto**: editor no painel inteiro com ferramentas, legenda e miniaturas. Nós usamos a prévia de anexo do Chatwoot dentro do campo.

## Acessibilidade (rótulos reais, lidos pelo REA)

| Controle | Rótulo no WhatsApp Web |
|---|---|
| Hora e status do balão | botão "12:57 Entregue" |
| Lista de mensagens | grade (`grid` → `row` → `gridcell`) |
| "+" | "Anexar" |
| Figurinha | "Emojis, GIFs, figurinhas" |
| Microfone | "Mensagem de voz" |
| Campo | "Digite uma mensagem para {contato}" |
| Áudio | botão "Reproduzir mensagem de voz"; controle deslizante "Controle deslizante de progresso do recado de voz"; botão "Mudar velocidade de reprodução, no momento 1,5×" |
| Ligação | botão "Ligação de voz perdida Clique para retornar 10:06" |
| Topo da conversa | botão "Clique neste aviso para carregar mensagens mais antigas…" |

Vale copiar: a hora e o status como um único texto acessível ("12:57 Entregue") e o rótulo da velocidade com o valor atual.

## O que fazer, por ordem

### P1: muda a percepção de "é o WhatsApp" (só visual, sem servidor)

1. Paleta nova do tema escuro (fundo e cabeçalho `#161717`, recebido `#242626`, enviado ~`#144D37`) e cabeçalho da cor do fundo no claro.
2. Compositor em pílula flutuante; enviar e microfone ativo em preto.
3. Sequência: espaço de 2–4 px dentro do grupo e ~12 px na troca; parar de quebrar a sequência a cada minuto; tirar a coluna vazia do avatar do lado do enviado.
4. Tiques: azul `#53BDEB` e cinza `#8696A0`, no desenho do WhatsApp. Texto `#0A0A0A` e hora `#666666` no claro (neutros, sem azulado).
5. Hora sobre a foto e o vídeo sem legenda, com degradê.
6. Separador de data: "sábado" em minúsculas, dd/mm/aaaa para datas antigas e grudar no topo enquanto rola.
7. Botão de descer (círculo de 40 px).
8. Menu "+" no tamanho real: ~156 px, itens de ~34 px, texto 14,5 px.
9. Chevron do menu dentro do balão no hover.

### P2: tipos que já existem no Chatwoot, com o desenho certo

1. Cartão de documento do WhatsApp (ícone por tipo, nome, "PDF • 14 KB", baixar).
2. Vídeo com miniatura e play central, "HD" e duração.
3. Citação com o nome de quem foi citado e a faixa da cor dele.
4. Áudio: foto à esquerda no enviado, ponto e microfone azuis, rótulo "1,0×", estado enviando.
5. Apagada em itálico com 🚫.
6. Só emoji sem balão.
7. Lista "Ver opções" em janela por cima; resposta da lista como balão citando a lista.
8. Contato com "Conversar" e "Salvar contato"; localização recebida e contato recebido com a pele (hoje caem no cartão do Chatwoot).

### P3: precisam do servidor ou de produto

Enquete (envio e leitura); prévia de link; álbum; reagir e encaminhar; ligação perdida; aviso da Meta; mapa real (custo da API do Google); editor de foto antes do envio; visualizador de mídia em tela cheia.

## Achados do inventário do nosso código (conferir na tela)

1. O estilo de botão em linha azul pega qualquer botão `bg-n-solid-3`: "Baixar" do documento e "Ver no mapa"/"Conversar" dos cartões do Chatwoot também mudam (`visualWhatsapp.js:44-47`).
2. Localização sem `shared_location` e contato recebido ficam com o cartão do Chatwoot (o seletor só pega `rich-location`/`received-location`).
3. Em localização e contato, `.space-y-1>div:first-child` está escondido; sem nome de remetente, o que some é o título (`visualWhatsapp.js:93, 100`).
4. "Pedir localização" fora da Cloud não tem botão, mas a hora continua a 48 px do fundo e deve tampar o texto.
5. Coluna do avatar escondido deixa ~32 px vazios do lado do enviado (`Message.vue:268-273`).
6. Modelo com botões: a hora vai para linha própria, mas o espaço de 64 px reservado no texto continua.
7. Nota privada ganha o canto reto sem ter bico (`visualWhatsapp.js:111-116`).
8. A sequência quebra a cada minuto (`MessageList.vue:129`): bicos e nomes a mais.
