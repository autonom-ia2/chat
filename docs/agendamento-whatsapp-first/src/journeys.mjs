
/* ---------- blocos de tela ---------- */
const sb = () => '<div class="sb"><span>9:41</span><span>5G ▮▮▮</span></div>';
const phone = inner => `<div class="phone">${sb()}<div class="bd">${inner}</div></div>`;
const bkHead = (sub) => `<div class="who"><div class="av">C</div><div><h5>Camila · Clínica Aurora</h5><div class="meta">${sub}</div></div></div>`;
const days = (on) => `<div class="days">${[['Seg',12],['Ter',13],['Qua',14],['Qui',15],['Sex',16]].map(([n,d])=>`<div class="day ${d===on?'on':''}">${n}<b>${d}</b></div>`).join('')}</div>`;
const slots = (on) => `<div class="slots">${['09:00','10:30','14:00','15:00','16:30','17:00'].map(s=>`<div class="slot ${s===on?'on':''} ${s==='10:30'?'off':''}">${s}</div>`).join('')}</div>`;
const desk = (inner, side=1) => `<div class="desk"><div class="sd"><i></i><i class="${side===1?'on':''}"></i><i class="${side===2?'on':''}"></i><i></i><i class="${side===3?'on':''}"></i></div><div class="mn">${inner}</div></div>`;
const loc = (ic,t,s,on,tg='') => `<div class="loc ${on?'on':''}"><div class="ic">${ic}</div><div><b>${t}</b><small>${s}</small></div>${tg?`<span class="tg">${tg}</span>`:''}</div>`;

const J = [];

/* J1 */
J.push({
  id:'1', t:'Agente gera o link e o cliente agenda', s:'Fase 1 · principal', who:'Agente e cliente',
  goal:'Em um toque o agente gera o link do cliente, manda no WhatsApp ou em qualquer outro canal, e o cliente escolhe sem digitar nada.',
  steps:[
   {n:'Gera o link', diff:'Hoje só existe o link geral da página, copiado de uma gaveta de configuração e igual para todo mundo. Aqui o agente gera o link do cliente em um toque, a qualquer hora, na conversa ou no card.', screen:()=>desk(`
      <div class="row"><h5>Marcos Lima</h5><span class="pill g">WhatsApp</span></div>
      <div class="lead">Conversa aberta · Clínica Aurora</div>
      <div class="mini">Marcos: Oi! Quero marcar uma conversa sobre o plano.</div>
      <div class="mini" style="align-self:flex-end;background:#E7F0FE">Camila: Claro! Vou te mandar os horários.</div>
      <div style="margin-top:auto" class="mini"><div class="row" style="justify-content:space-between"><span class="lead">Escreva uma mensagem…</span><span class="pbtn alt">Agendar</span></div></div>
      <div class="mini" style="border-color:#2781F6"><b>Link de agenda para Marcos</b><div class="lead" style="margin:2px 0 6px">Página: Conversa de 30 min · vale 7 dias</div><div class="box" style="margin-bottom:8px">Oi, Marcos! Escolha o melhor horário por aqui: <b style="display:inline">[link]</b> <span style="color:#0A5BC4;font-weight:700">Editar texto</span></div><div class="row"><span class="pbtn">Enviar na conversa</span><span class="pbtn alt">Copiar link</span></div></div>`,1),
   },
   {n:'Ou manda por outro canal', diff:'Novo: o link copiado vale em qualquer lugar, como e-mail, Instagram, SMS ou o WhatsApp pessoal. Ele continua sendo o link do Marcos.', screen:()=>desk(`
      <div class="row"><h5>Marcos Lima</h5><span class="pill">Card · Vendas</span></div>
      <div class="mini" style="border-color:#0B7A5A"><b>Link copiado</b><div class="lead">chat.exemplo.com/b/Xk4p9Q · vale até 16/10</div></div>
      <div class="mini"><div class="lead">Novo e-mail para marcos@exemplo.com</div><b>Escolha o melhor horário</b><div style="margin-top:6px">Oi, Marcos! Marque a nossa conversa por aqui:<br><span style="color:#0A5BC4;text-decoration:underline">chat.exemplo.com/b/Xk4p9Q</span></div></div>
      <div class="lead">O mesmo botão "Agendar" existe no card e na conversa de qualquer canal.</div>`,1),
   },
   {n:'Cliente recebe', diff:'Hoje o cliente recebe um link genérico, sem nome. Aqui o link já sabe quem ele é, seja qual for o canal em que chegou.', screen:()=>phone(`
      <div class="wahead"><div class="av">C</div><div><b>Clínica Aurora</b><span>online</span></div></div>
      <div class="chat">
        <div class="msg out">Oi! Quero marcar uma conversa sobre o plano.<small>14:02</small></div>
        <div class="msg in">Oi, Marcos! Escolha o melhor horário por aqui:<br><span class="lnk">chat.exemplo.com/book/a1b2…</span><small>14:03</small></div>
      </div>`),
   },
   {n:'Escolhe o dia', diff:'Hoje pede nome e e-mail. Aqui abre já com "Oi, Marcos" e vai direto aos dias.', screen:()=>phone(`<div class="bk">${bkHead('Conversa de 30 min · vídeo no WhatsApp')}<div class="hello">Oi, Marcos! Qual dia fica bom?</div><div class="mini" style="border-color:#2781F6"><b>Mais cedo: terça, 13 às 15:00</b><div class="btn alt" style="margin-top:8px">Escolher este</div></div>${days(13)}<div class="meta">Horário de Brasília</div></div>`),
   },
   {n:'Escolhe a hora', diff:'Mesmo cálculo de horários livres de hoje; horários ocupados aparecem riscados.', screen:()=>phone(`<div class="bk">${bkHead('Terça, 13 de outubro')}<div class="q">Qual horário?</div>${slots('15:00')}<div class="btn">Continuar</div></div>`),
   },
   {n:'Confirma', diff:'Novo: a página diz como será a conversa. Sem verificação por e-mail porque o link foi enviado a ele.', screen:()=>phone(`<div class="bk">${bkHead('Confira antes de confirmar')}<div class="box"><b>Terça, 13 de outubro, 15:00</b>A Camila vai te chamar por vídeo no WhatsApp <b style="display:inline">(11) 91234-5678</b></div><div class="btn">Confirmar</div><div class="btn ghost">Mudar o número</div></div>`),
   },
   {n:'Pronto', diff:'Hoje: "verifique seu e-mail". Aqui: confirmado na hora, mensagem na conversa e reunião no card que já existe.', screen:()=>phone(`<div class="bk center"><div class="okmark">✓</div><div class="hello">Tudo certo, Marcos!</div><div class="box" style="text-align:left"><b>Terça, 13 de outubro, 15:00</b>Vídeo no WhatsApp com a Camila</div><div class="btn alt">Salvar na minha agenda</div><div class="meta">Avisamos a Camila.</div></div>`),
   },
  ],
  accept:[
   ['J1-A1','Dado uma conversa de qualquer canal com um contato, <em>quando</em> o agente toca em "Agendar" e depois em "Enviar na conversa", <em>então</em> a mensagem com o link sai na conversa e o link identifica o contato e a conversa.'],
   ['J1-A2','Dado o link válido, <em>quando</em> o cliente abre, <em>então</em> vê o nome dele e não é pedido e-mail nem verificação.'],
   ['J1-A3','<em>Quando</em> o cliente confirma, <em>então</em> a reunião entra no card existente, sem criar card duplicado; se o contato não tem card, cria um no funil padrão da página.'],
   ['J1-A4','Do abrir o link ao confirmar, o cliente faz no máximo 4 toques (dia, hora, confirmar e, se quiser, mudar o número).'],
   ['J1-A5','Dado dois clientes no mesmo horário, <em>então</em> o segundo vê "Esse horário acabou de ser reservado" com os outros horários (trava atual preservada).'],
   ['J1-A6','Dado link expirado ou alterado, <em>então</em> aparece mensagem simples pedindo um novo link ao atendente, sem expor dado nenhum.'],
   ['J1-A7','<em>Quando</em> confirma, <em>então</em> uma mensagem de confirmação aparece na conversa (se o link foi enviado por uma conversa).'],
   ['J1-A8','<em>Quando</em> o agente toca em "Copiar link", no card ou na conversa, <em>então</em> o link do cliente vai para a área de transferência e pode ser colado em qualquer canal, a qualquer hora.'],
   ['J1-A9','O link é curto, não adivinhável, vale 7 dias (a confirmar), o agente pode cancelá-lo e, depois de usado, vira o link de gestão da reunião (J5).'],
   ['J1-A10','O card mostra o estado do link: enviado, aberto ou agendado.'],
   ['J1-A12','O texto do convite já vem pronto, com o nome do cliente e o link, e o agente pode editar antes de enviar; o texto padrão é definido por conta.'],
   ['J1-A13','A página mostra o próximo horário livre no topo com o botão "Escolher este".'],
   ['J1-A11','Dado um contato sem WhatsApp cadastrado e local "vídeo no WhatsApp", <em>então</em> a página pede o número antes de confirmar.'],
  ]
});

/* J2 */
J.push({
  id:'2', t:'Cliente agenda pelo link público', s:'Fase 1', who:'Cliente novo',
  goal:'Quem chega por bio, anúncio ou QR code marca sozinho, só com nome e WhatsApp, e nunca fica sem saída.',
  steps:[
   {n:'Abre a página', diff:'Hoje exige que a página esteja ligada a uma caixa Google/MS e não tem a cara da empresa. Aqui qualquer conta publica, com logo, foto e cor, e o próximo horário livre já aparece no topo.', screen:()=>phone(`<div class="bk">${bkHead('Conversa de 30 min')}<div class="box"><b>Como será</b>Vídeo no WhatsApp. A Camila chama você no horário marcado.</div><div class="mini" style="border-color:#2781F6"><b>Mais cedo: amanhã, 10:00</b><div class="btn alt" style="margin-top:8px">Escolher este</div></div><div class="q">Ou escolha outro dia</div>${days(14)}</div>`),
   },
   {n:'Escolhe a hora', diff:'Sem mudança no cálculo de horários livres. Ganha antecedência mínima (hoje só existe o intervalo entre reuniões).', screen:()=>phone(`<div class="bk">${bkHead('Quarta, 14 de outubro')}<div class="q">Qual horário?</div>${slots('14:00')}<div class="btn">Continuar</div></div>`),
   },
   {n:'Seus dados', diff:'Hoje: nome e e-mail obrigatórios. Aqui: só nome e WhatsApp; e-mail é opcional. O aviso sobre as mensagens aparece antes do botão.', screen:()=>phone(`<div class="bk">${bkHead('Quarta, 14 de outubro, 14:00')}<label class="fld">Seu nome<div>Ana Souza</div></label><label class="fld">Seu WhatsApp<div>+55 (11) 98888-0000</div></label><label class="fld">E-mail (se quiser)<div class="ph">voce@exemplo.com</div></label><div class="meta">Ao confirmar, você aceita receber os avisos desta conversa no WhatsApp. Você pode parar quando quiser.</div><div class="btn">Confirmar</div></div>`),
   },
   {n:'Pronto', diff:'Hoje o cliente precisa abrir o e-mail e clicar. Aqui confirma na hora, salva na agenda dele com um toque e pode falar com a empresa.', screen:()=>phone(`<div class="bk center"><div class="okmark">✓</div><div class="hello">Agendado, Ana!</div><div class="box" style="text-align:left"><b>Quarta, 14 de outubro, 14:00</b>Vídeo no WhatsApp com a Camila</div><div class="btn">Salvar na minha agenda</div><div class="btn ghost">Falar com a Camila no WhatsApp</div><div class="meta">Enviamos a confirmação para o seu WhatsApp.</div></div>`),
   },
   {n:'Sem horário bom?', diff:'Hoje, sem horário que sirva, o visitante vai embora e o lead se perde. Aqui vira um pedido de contato que chega ao card.', screen:()=>phone(`<div class="bk">${bkHead('Conversa de 30 min')}<div class="hello">Nenhum horário serve?</div><div class="box">Sem problema. Deixe seu WhatsApp e a Camila chama você para combinar.</div><label class="fld">Seu nome<div>Ana Souza</div></label><label class="fld">Seu WhatsApp<div>+55 (11) 98888-0000</div></label><div class="btn">Pedir contato</div></div>`),
   },
  ],
  accept:[
   ['J2-A1','Dado uma conta sem Google/MS, <em>quando</em> o admin publica a página, <em>então</em> o link público abre e mostra horários.'],
   ['J2-A2','<em>Quando</em> o cliente informa nome e WhatsApp válidos, <em>então</em> a reunião é criada sem e-mail; e-mail é opcional.'],
   ['J2-A3','O número é validado em formato E.164 pela biblioteca de telefone do sistema; número inválido mostra erro simples no campo.'],
   ['J2-A4','Dado um bot (honeypot, time-trap, rate-limit ou captcha), <em>então</em> a tentativa é recusada sem dizer o motivo.'],
   ['J2-A5','Dado o mesmo número com 2 reuniões abertas, <em>então</em> a terceira é recusada com mensagem simples.'],
   ['J2-A6','<em>Se</em> o envio no WhatsApp não puder sair (fora da janela e sem modelo aprovado), <em>então</em> a reunião continua confirmada, o agente é avisado e a tela de sucesso não promete mensagem que não saiu.'],
   ['J2-A7','O card nasce com origem "link público" e o funil, a etapa e o responsável configurados na página.'],
   ['J2-A8','A página mostra no topo o próximo horário livre com um botão "Escolher este"; o cliente chega à confirmação em até 4 toques.'],
   ['J2-A9','O aviso sobre os lembretes no WhatsApp aparece antes do botão Confirmar. Toda mensagem automática tem como parar de receber, e quem parar não recebe mais.'],
   ['J2-A10','<em>Quando</em> o cliente toca em "Nenhum horário serve?" e informa nome e WhatsApp, <em>então</em> nasce um card com origem "pediu contato" e o agente é avisado.'],
   ['J2-A11','A tela de sucesso oferece "Salvar na minha agenda" (arquivo de calendário que abre no Google, Apple e Outlook) e um botão para falar com a empresa no WhatsApp.'],
   ['J2-A12','Logo, foto e cor do dono aparecem na página sem prejudicar a leitura: se a cor escolhida não tiver contraste suficiente, a página ajusta sozinha.'],
  ]
});

/* J3 */
J.push({
  id:'3', t:'Admin cria a página de agendamento', s:'Fase 1', who:'Administrador',
  goal:'Publicar a página em minutos: o primeiro passo já deixa tudo pronto, e o admin só ajusta.',
  steps:[
   {n:'Escolha um modelo', diff:'Hoje é um formulário vazio, escondido num botão da barra do Kanban. Aqui começa pronto: o modelo preenche nome, duração, local, horários e a mensagem.', screen:()=>desk(`
      <div class="stepdots"><span class="on"></span><span></span><span></span><span></span><span></span><span></span></div>
      <h5>O que você quer marcar?</h5>
      ${loc('☎','Conversa de vendas','30 minutos · vídeo no WhatsApp',true,'Mais usado')}
      ${loc('✚','Consulta ou atendimento','45 minutos · no local',false)}
      ${loc('⌂','Visita','60 minutos · no local do cliente',false)}
      ${loc('＋','Começar do zero','Você preenche tudo',false)}
      <div style="margin-top:auto"><span class="pbtn">Usar este modelo</span></div>`,3),
   },
   {n:'Conte', diff:'Já vem preenchido pelo modelo. O admin só confere ou troca.', screen:()=>desk(`
      <div class="stepdots"><span class="on"></span><span class="on"></span><span></span><span></span><span></span><span></span></div>
      <h5>Como se chama a conversa?</h5>
      <label class="fld">Nome que o cliente vê<div>Conversa de 30 min</div></label>
      <label class="fld">Quanto tempo dura?<div>30 minutos</div></label>
      <label class="fld">Quem atende?<div>Camila Torres</div></label>
      <div style="margin-top:auto"><span class="pbtn">Continuar</span></div>`,3),
   },
   {n:'Onde acontece', diff:'Hoje só mostra caixas Google/MS e o erro "nenhuma caixa com agenda". Aqui mostra só o que dá para usar agora.', screen:()=>desk(`
      <div class="stepdots"><span class="on"></span><span class="on"></span><span class="on"></span><span></span><span></span><span></span></div>
      <h5>Onde vai ser a conversa?</h5>
      ${loc('▶','Vídeo no WhatsApp','Você chama o cliente no horário',true,'Recomendado')}
      ${loc('☎','Ligação no WhatsApp','Só voz',false)}
      ${loc('🔗','Meu link','Zoom, Meet ou outro que você já usa',false)}
      ${loc('⌖','No local','Cliente vai até o endereço',false)}
      <div class="lead">Google Meet e Teams aparecem aqui quando você conecta uma caixa de e-mail.</div>
      <div style="margin-top:auto"><span class="pbtn">Continuar</span></div>`,3),
   },
   {n:'Dias e horas', diff:'Mesmos campos de hoje. Ganha "avisar com antecedência", que antes não existia, e (Fase 2) feriados nacionais fechados.', screen:()=>desk(`
      <div class="stepdots"><span class="on"></span><span class="on"></span><span class="on"></span><span class="on"></span><span></span><span></span></div>
      <h5>Quando você atende?</h5>
      <div class="row"><span class="pill g">Seg</span><span class="pill g">Ter</span><span class="pill g">Qua</span><span class="pill g">Qui</span><span class="pill g">Sex</span><span class="pill">Sáb</span><span class="pill">Dom</span></div>
      <div class="kv"><span>Das</span><b>09:00</b><span>Até</span><b>17:00</b><span>Avisar com</span><b>2 horas de antecedência</b><span>Intervalo</span><b>10 minutos entre conversas</b><span>Feriados</span><b>Fechado (Fase 2)</b></div>
      <div style="margin-top:auto"><span class="pbtn">Continuar</span></div>`,3),
   },
   {n:'Cara e avisos', diff:'Novo: a página ganha a cara da empresa e o admin escolhe quando o cliente é avisado.', screen:()=>desk(`
      <div class="stepdots"><span class="on"></span><span class="on"></span><span class="on"></span><span class="on"></span><span class="on"></span><span></span></div>
      <h5>Deixe com a sua cara</h5>
      <div class="row"><div class="loc" style="flex:1"><div class="ic">▣</div><div><b>Logo</b><small>Enviar imagem</small></div></div><div class="loc" style="flex:1"><div class="ic">☺</div><div><b>Sua foto</b><small>Enviar imagem</small></div></div></div>
      <div class="row"><span class="lead">Cor</span><span class="pill" style="background:#0D2344;color:#fff">Azul</span><span class="pill" style="background:#0B7A5A;color:#fff">Verde</span><span class="pill" style="background:#B3263E;color:#fff">Vermelho</span><span class="pill" style="background:#8A5200;color:#fff">Âmbar</span></div>
      <div class="lead" style="margin-top:4px">Quando avisar o cliente no WhatsApp?</div>
      <div class="row"><span class="pill g">Ao marcar</span><span class="pill g">1 dia antes</span><span class="pill g">1 hora antes</span></div>
      <div style="margin-top:auto"><span class="pbtn">Ver como fica</span></div>`,3),
   },
   {n:'Prévia e publicar', diff:'Novo: o admin vê a página do cliente antes de publicar, confere para onde vai o lead e sai com o link e o QR code.', screen:()=>desk(`
      <div class="stepdots"><span class="on"></span><span class="on"></span><span class="on"></span><span class="on"></span><span class="on"></span><span class="on"></span></div>
      <h5>Assim o cliente vai ver</h5>
      <div class="mini"><b>Conversa de 30 min</b><div class="lead">Vídeo no WhatsApp · Seg a sex, 9h às 17h</div></div>
      <div class="mini">Quem marcar vai para o funil <b>Vendas</b>, etapa <b>Conversa agendada</b>, com a <b>Camila</b>. <span style="color:#0A5BC4;font-weight:700">Alterar</span></div>
      <div class="row"><div class="qr"></div><div><div class="lead">Seu link</div><b>chat.exemplo.com/book/9f3c…</b><div class="row" style="margin-top:6px"><span class="pbtn alt">Copiar link</span><span class="pbtn alt">Testar no meu WhatsApp</span></div></div></div>
      <div style="margin-top:auto"><span class="pbtn">Publicar</span></div>`,3),
   },
  ],
  accept:[
   ['J3-A1','Dado uma conta sem caixa Google/MS, <em>quando</em> o admin conclui os seis passos, <em>então</em> consegue publicar e receber o link e o QR code.'],
   ['J3-A2','A lista de locais mostra apenas o que está disponível na conta; Meet e Teams só aparecem com caixa conectada.'],
   ['J3-A3','Todas as escolhas usam o componente <code>ChoiceSelect</code> (nenhum <code>&lt;select&gt;</code> nativo), com teclado e leitor de tela.'],
   ['J3-A4','Cada passo tem uma ação principal; o admin pode voltar sem perder o que digitou.'],
   ['J3-A5','A prévia é a mesma página que o cliente vê, com os dados que o admin acabou de preencher.'],
   ['J3-A6','Dado a flag desligada, <em>então</em> a tela antiga continua como hoje (RA-03).'],
   ['J3-A7','O acesso segue o padrão de funções personalizadas do CRM; agente comum sem função não vê a tela.'],
   ['J3-A8','Ao escolher um modelo, nome, duração, local, horários e a mensagem do convite vêm preenchidos; "Começar do zero" também existe.'],
   ['J3-A9','O admin envia logo e foto e escolhe uma cor entre opções prontas; a página aplica tudo e corrige sozinha qualquer cor com pouco contraste.'],
   ['J3-A10','Funil, etapa e responsável já vêm com valores padrão sensatos e aparecem em uma frase na prévia, com o botão "Alterar" bem visível.'],
   ['J3-A11','"Testar no meu WhatsApp" envia ao próprio admin um link igual ao do cliente.'],
   ['J3-A12','Depois de publicada, há um botão "Pausar página". Página pausada mostra um aviso simples e um botão para falar no WhatsApp; nenhum horário é oferecido.'],
   ['J3-A13','(Fase 2) A opção "Fechar feriados nacionais" vem ligada por padrão e o admin pode desligá-la.'],
  ]
});

/* J4 */
J.push({
  id:'4', t:'Agente atende no dia da reunião', s:'Fase 1 e 2', who:'Agente',
  goal:'Ver quem confirmou, chamar o cliente no WhatsApp com um toque, registrar como foi e dar o próximo passo.',
  steps:[
   {n:'Agenda de hoje', diff:'Hoje a reunião aparece no calendário e o lembrete push vai ao agente. Aqui cada reunião mostra o local e se o cliente confirmou (Fase 2).', screen:()=>desk(`
      <div class="row"><h5>Hoje · terça, 13</h5><span class="pill">Calendário</span></div>
      <div class="evt"><b>15:00 · Marcos Lima</b><span class="lead">Vídeo no WhatsApp · Conversa de 30 min</span><div style="margin-top:4px"><span class="pill g">Confirmou</span></div></div>
      <div class="evt" style="border-left-color:#8A5200"><b>16:30 · Ana Souza</b><span class="lead">Ligação no WhatsApp</span><div class="row" style="margin-top:4px"><span class="pill a">Sem resposta</span><span class="pbtn alt" style="min-height:30px;font-size:12px">Lembrar</span></div></div>
      <div class="mini" style="margin-top:auto">Lembrete: sua conversa com Marcos começa em 15 minutos.</div>`,2),
   },
   {n:'Chama o cliente', diff:'Novo: botão que abre a conversa do cliente no WhatsApp. O agente toca no ícone de vídeo do próprio WhatsApp.', screen:()=>desk(`
      <h5>Marcos Lima</h5>
      <div class="kv"><span>Quando</span><b>Hoje, 15:00 (30 min)</b><span>Como</span><b>Vídeo no WhatsApp</b><span>Número</span><b>(11) 91234-5678</b><span>Origem</span><b>Link na conversa</b></div>
      <div class="row"><span class="pbtn gr">Chamar no WhatsApp</span><span class="pbtn alt">Ver card</span></div>
      <div class="lead">O WhatsApp abre a conversa. Toque no ícone de vídeo para chamar.</div>`,2),
   },
   {n:'Registra o resultado', diff:'Reaproveita o registro de resultado de hoje, agora em uma pergunta só. Se o cliente faltou, o agente remarca com um toque.', screen:()=>desk(`
      <h5>Como foi a conversa com a Ana?</h5>
      <div class="loc"><div class="ic">✓</div><div><b>Aconteceu</b><small>O cliente compareceu</small></div></div>
      <div class="loc on"><div class="ic">✕</div><div><b>Cliente faltou</b><small>Vamos ajudar a marcar de novo</small></div></div>
      <div class="mini" style="border-color:#2781F6"><b>Enviar link para a Ana marcar outro horário</b><div class="row" style="margin-top:6px"><span class="pbtn">Enviar link</span><span class="pbtn alt">Agora não</span></div></div>`,2),
   },
   {n:'Depois da conversa', diff:'Novo: o sistema pergunta se o card avança de etapa. O admin pode deixar isso automático.', screen:()=>desk(`
      <h5>Marcos Lima · conversa feita</h5>
      <div class="mini"><b>Mover para a etapa "Proposta"?</b><div class="lead" style="margin:2px 0 8px">Assim ele não fica esquecido na etapa "Conversa agendada".</div><div class="row"><span class="pbtn">Mover</span><span class="pbtn alt">Agora não</span></div></div>
      <div class="lead">Quem decide se isso é automático é o administrador, nas configurações da página.</div>`,2),
   },
  ],
  accept:[
   ['J4-A1','Reunião <code>internal</code> aparece no calendário e no card com horário, local e número do cliente.'],
   ['J4-A2','O botão "Chamar no WhatsApp" abre a conversa com o número da reunião; o texto explica que a chamada de vídeo é iniciada no próprio WhatsApp.'],
   ['J4-A3','O resultado (compareceu ou faltou) usa o serviço de resultado existente e atualiza o card.'],
   ['J4-A4','O lembrete ao agente (push e e-mail) continua funcionando como hoje, sem depender de caixa de calendário.'],
   ['J4-A5','(Fase 2) O card e o calendário mostram se o cliente confirmou, pediu para mudar ou não respondeu, com um botão "Lembrar" para o agente.'],
   ['J4-A6','(Fase 2) Quando o cliente faltou, o botão "Enviar link para marcar outro horário" envia o link do cliente em um toque. Nada é enviado sem o agente tocar.'],
   ['J4-A7','(Fase 2) Depois de "Aconteceu", o sistema oferece mover o card para a etapa escolhida pelo admin; o admin pode ligar o modo automático ou deixar sempre perguntar.'],
  ]
});

/* J5 */
J.push({
  id:'5', t:'Avisos e confirmação pelo cliente', s:'Fase 2', who:'Cliente',
  goal:'O cliente é lembrado no momento certo, confirma com um toque e, se precisar, muda ou cancela sozinho.',
  steps:[
   {n:'Recebe o aviso', diff:'Hoje o cliente só tem o convite por e-mail. Aqui recebe três avisos no WhatsApp: ao marcar, 1 dia antes e 1 hora antes (o admin pode ajustar).', screen:()=>phone(`
      <div class="wahead"><div class="av">C</div><div><b>Clínica Aurora</b><span>online</span></div></div>
      <div class="chat"><div class="msg in">Oi, Marcos! Lembrando da nossa conversa amanhã, terça às 15:00, por vídeo aqui no WhatsApp.<br>Confirma ou muda aqui: <span class="lnk">chat.exemplo.com/r/7d2…</span><br><small style="text-align:left">Para parar os avisos, toque em "Parar avisos" na página.</small><small>14:00</small></div></div>`),
   },
   {n:'Sua conversa', diff:'Novo: página própria da reunião, com um link único. Três botões grandes, um por decisão.', screen:()=>phone(`<div class="bk">${bkHead('Sua conversa')}<div class="box"><b>Terça, 13 de outubro, 15:00</b>Vídeo no WhatsApp com a Camila</div><div class="btn">Vou estar lá</div><div class="btn alt">Mudar o horário</div><div class="btn ghost">Cancelar</div></div>`),
   },
   {n:'Confirmou', diff:'Novo: um toque avisa o agente e o card passa a mostrar "Confirmou".', screen:()=>phone(`<div class="bk center"><div class="okmark">✓</div><div class="hello">Presença confirmada</div><div class="box" style="text-align:left"><b>Terça, 13 de outubro, 15:00</b>Vídeo no WhatsApp com a Camila</div><div class="btn">Salvar na minha agenda</div><div class="meta">A Camila foi avisada.</div></div>`),
   },
   {n:'Escolhe outro horário', diff:'Novo. O horário antigo é liberado quando o novo é confirmado.', screen:()=>phone(`<div class="bk">${bkHead('Quinta, 15 de outubro')}<div class="q">Qual horário?</div>${slots('09:00')}<div class="btn">Confirmar novo horário</div></div>`),
   },
   {n:'Horário atualizado', diff:'O agente é avisado e o card mostra o histórico (horário antigo e novo).', screen:()=>phone(`<div class="bk center"><div class="okmark">✓</div><div class="hello">Horário atualizado</div><div class="box" style="text-align:left"><b>Quinta, 15 de outubro, 09:00</b>Vídeo no WhatsApp com a Camila</div><div class="meta">Avisamos a Camila.</div></div>`),
   },
  ],
  accept:[
   ['J5-A1','A reunião gera três avisos por padrão (ao marcar, 1 dia antes e 1 hora antes); dentro da janela de 24h sai texto, fora dela sai modelo aprovado.'],
   ['J5-A2','O link de gestão é único por reunião, assinado e expira depois do horário; não dá para abrir a reunião de outra pessoa.'],
   ['J5-A3','Cancelar ou remarcar libera o horário antigo na hora e avisa o agente (limite: até 2 horas antes, a confirmar).'],
   ['J5-A4','Falha de envio do aviso é registrada e avisa o agente; nunca cancela nem altera a reunião.'],
   ['J5-A5','Número de WAHA não envia aviso fora da janela de 24h (risco de bloqueio).'],
   ['J5-A6','Ao tocar em "Vou estar lá", o card passa a mostrar "Confirmou" e o agente é avisado; confirmar duas vezes não gera dois avisos.'],
   ['J5-A7','"Parar avisos" interrompe todas as mensagens automáticas ao cliente e fica registrado; a reunião continua valendo.'],
   ['J5-A8','O admin escolhe entre três jogos de avisos prontos (padrão: ao marcar, 1 dia antes, 1 hora antes) sem digitar horários.'],
  ]
});

/* J6 */
J.push({
  id:'6', t:'IA oferece horários na conversa', s:'Fase 3', who:'Cliente e agente de IA',
  goal:'O cliente pede para marcar e o agente de IA resolve na própria conversa, com horários reais.',
  steps:[
   {n:'Cliente pede', diff:'Hoje os agentes só coletam o pedido e passam para uma pessoa. Não existe ferramenta de agenda.', screen:()=>phone(`
      <div class="wahead"><div class="av">C</div><div><b>Clínica Aurora</b><span>online</span></div></div>
      <div class="chat"><div class="msg out">Queria marcar uma conversa essa semana<small>14:10</small></div></div>`),
   },
   {n:'IA oferece', diff:'Novo: a IA consulta a agenda e oferece só horários livres de verdade.', screen:()=>phone(`
      <div class="wahead"><div class="av">C</div><div><b>Clínica Aurora</b><span>online</span></div></div>
      <div class="chat"><div class="msg out">Queria marcar uma conversa essa semana<small>14:10</small></div><div class="msg in">Claro! Tenho terça às 15:00, quarta às 14:00 ou quinta às 09:00. Qual prefere?<small>14:10</small></div></div>`),
   },
   {n:'Cliente escolhe', diff:'A IA entende a resposta com o modelo; não há lista de palavras nem regra escrita à mão.', screen:()=>phone(`
      <div class="wahead"><div class="av">C</div><div><b>Clínica Aurora</b><span>online</span></div></div>
      <div class="chat"><div class="msg in">Tenho terça às 15:00, quarta às 14:00 ou quinta às 09:00. Qual prefere?<small>14:10</small></div><div class="msg out">A de quarta<small>14:11</small></div><div class="msg in">Fechado! Quarta, 14 de outubro, às 14:00, por vídeo aqui no WhatsApp. Te lembro um dia antes.<small>14:11</small></div></div>`),
   },
   {n:'Agente vê', diff:'A reunião cai no card com a marca "agendada pela IA", e uma pessoa pode assumir a conversa quando quiser.', screen:()=>desk(`
      <div class="row"><h5>Marcos Lima</h5><span class="pill a">Agendado pela IA</span></div>
      <div class="evt"><b>Quarta, 14 · 14:00</b><span class="lead">Vídeo no WhatsApp · 30 min</span></div>
      <div class="mini">A IA ofereceu 3 horários e o cliente escolheu quarta às 14:00.</div>
      <div class="row" style="margin-top:auto"><span class="pbtn alt">Assumir conversa</span></div>`,1),
   },
  ],
  accept:[
   ['J6-A1','A IA só oferece horários que a página ofereceria ao cliente naquele momento (mesma regra de disponibilidade).'],
   ['J6-A2','A intenção do cliente é interpretada pelo modelo; nenhuma lista de palavras ou expressão regular decide o que a pessoa quis dizer (RA-09).'],
   ['J6-A3','Dois pedidos para o mesmo horário: o segundo recebe novas opções, nunca uma dupla reserva.'],
   ['J6-A4','A reunião criada pela IA é identificável no card e uma pessoa pode assumir a conversa a qualquer momento.'],
   ['J6-A5','Se a página estiver desligada ou sem horários, a IA diz isso e passa para uma pessoa.'],
  ]
});


/* J7 */
J.push({
  id:'7', t:'Dono acompanha os números', s:'Fase 2', who:'Dono ou administrador',
  goal:'Ver em cinco números se a agenda está dando resultado e quem abriu o link e não marcou.',
  steps:[
   {n:'Painel', diff:'Hoje só existe o calendário. Aqui o dono vê o caminho inteiro, do link enviado até quem compareceu (dados fictícios).', screen:()=>desk(`
      <div class="row"><h5>Agendamento · últimos 30 dias</h5></div>
      <div class="row" style="gap:6px"><div class="mini" style="flex:1;text-align:center"><b style="font-size:22px">48</b><div class="lead">Links enviados</div></div><div class="mini" style="flex:1;text-align:center"><b style="font-size:22px">31</b><div class="lead">Abriram</div></div><div class="mini" style="flex:1;text-align:center"><b style="font-size:22px">19</b><div class="lead">Marcaram</div></div></div>
      <div class="row" style="gap:6px"><div class="mini" style="flex:1;text-align:center"><b style="font-size:22px;color:#0B7A5A">15</b><div class="lead">Compareceram</div></div><div class="mini" style="flex:1;text-align:center"><b style="font-size:22px;color:#B3263E">4</b><div class="lead">Faltaram</div></div></div>
      <div class="mini"><b>De onde vieram os agendamentos</b><div class="kv" style="margin-top:6px"><span>Conversa</span><b>12</b><span>Link da bio</span><b>5</b><span>Anúncio</span><b>2</b></div></div>`,1),
   },
   {n:'Quem não marcou', diff:'Novo: lista de quem abriu o link e não marcou, com um botão para mandar de novo. Uma pessoa decide, nada sai sozinho.', screen:()=>desk(`
      <h5>Abriram o link e não marcaram</h5>
      <div class="evt"><b>Paula Reis</b><span class="lead">Abriu há 2 dias · link enviado por WhatsApp</span><div style="margin-top:6px"><span class="pbtn alt" style="min-height:32px;font-size:12px">Enviar de novo</span></div></div>
      <div class="evt"><b>Rui Alves</b><span class="lead">Abriu há 4 dias · link enviado por e-mail</span><div style="margin-top:6px"><span class="pbtn alt" style="min-height:32px;font-size:12px">Enviar de novo</span></div></div>
      <div class="lead">Mostramos só quem recebeu o seu link. Ninguém recebe mensagem sem você tocar.</div>`,1),
   },
  ],
  accept:[
   ['J7-A1','O painel mostra cinco números do período (7 ou 30 dias): links enviados, abriram, marcaram, compareceram e faltaram, com uma frase explicando cada um.'],
   ['J7-A2','Os números vêm de eventos registrados (enviado, aberto, agendado, compareceu, faltou) e batem com o que aparece nos cards; o painel agregado não mostra dados pessoais.'],
   ['J7-A3','Os agendamentos aparecem separados por origem: conversa, link público e pedido de contato.'],
   ['J7-A4','A lista "abriram e não marcaram" tem botão "Enviar de novo" por pessoa; nada é enviado sem o agente tocar.'],
   ['J7-A5','Só quem tem permissão do módulo vê o painel, no padrão de funções personalizadas.'],
  ]
});

/* J8 */
const lvlRow = (name, sel, note) => `<div class="mini"><div class="row" style="justify-content:space-between"><b>${name}</b><span class="row" style="gap:4px">${['Sem acesso','Ver','Gerenciar'].map((l,i)=>`<span class="pill ${i===sel?'g':''}" style="${i===sel?'':'background:#F3F6FB;color:#55627A'}">${l}</span>`).join('')}</span></div>${note?`<div class="lead" style="margin-top:4px">${note}</div>`:''}</div>`;
const who = (n, cells) => `<div style="display:grid;grid-template-columns:1.5fr repeat(4,1fr);gap:4px;align-items:center;font-size:12px"><b style="font-size:12px">${n}</b>${cells.map(c=>`<span style="text-align:center;font-weight:700;color:${c==='✓'?'#0B7A5A':(c==='—'?'#9AA6B8':'#8A5200')}">${c}</span>`).join('')}</div>`;
J.push({
  id:'8', t:'Quem pode o quê: administrador, funções e agentes', s:'Fase 1 e 2', who:'Administrador e agentes',
  goal:'Cada pessoa vê e faz só o que cabe a ela. Funções personalizadas ganham um módulo "Agendamento", e quem sai da equipe não deixa links ativos para trás.',
  steps:[
   {n:'Módulo na função', diff:'Hoje só administrador cria e edita páginas de agendamento; uma função personalizada não consegue. Aqui "Agendamento" vira uma linha na tela de funções, como Campanhas e Automações.', screen:()=>desk(`
      <div class="row"><h5>Função: Coordenação comercial</h5></div>
      ${lvlRow('CRM', 1, 'Ver os cards e mexer nos seus')}
      ${lvlRow('Agendamento', 2, 'Gerenciar: cria, publica e pausa páginas. Ver: só enxerga páginas e números.')}
      ${lvlRow('Campanhas', 0, '')}
      <div class="lead">Não entram nesta linha: conectar caixas, usuários, funções, integrações e faturamento.</div>
      <div style="margin-top:auto"><span class="pbtn">Salvar função</span></div>`,3),
   },
   {n:'O que cada um vê', diff:'Novo: as quatro pessoas típicas e o que cada uma faz. O agente comum continua agendando para os clientes dele.', screen:()=>desk(`
      <h5>Quem faz o quê</h5>
      <div style="display:grid;grid-template-columns:1.5fr repeat(4,1fr);gap:4px;font-size:11px;color:#55627A;font-weight:700"><span></span><span style="text-align:center">Admin</span><span style="text-align:center">Gerencia</span><span style="text-align:center">Só vê</span><span style="text-align:center">Agente</span></div>
      ${who('Criar e publicar páginas',['✓','✓','—','—'])}
      ${who('Pausar uma página',['✓','✓','—','—'])}
      ${who('Ver páginas e números da equipe',['✓','✓','✓','—'])}
      ${who('Agendar para um cliente',['✓','✓','✓','✓'])}
      ${who('Ver a própria agenda e números',['✓','✓','✓','✓'])}
      ${who('Conectar caixas e WhatsApp',['✓','—','—','—'])}
      <div class="lead">Agente é quem não tem função personalizada. "Agendar para um cliente" vale só para clientes que a pessoa já pode ver.</div>`,3),
   },
   {n:'Quando alguém sai', diff:'Hoje, se um agente sai, o link individual dele continua de pé e as reuniões ficam sem dono. Aqui o link pausa na hora e o admin recebe o aviso.', screen:()=>desk(`
      <div class="row"><h5>Atenção</h5><span class="pill a">Precisa de você</span></div>
      <div class="mini" style="border-color:#8A5200"><b>Rui saiu da equipe</b><div class="lead" style="margin:2px 0 8px">Os links do Rui foram pausados. Ele tem 3 reuniões marcadas para os próximos dias.</div><div class="row"><span class="pbtn">Passar para a Camila</span><span class="pbtn alt">Escolher outra pessoa</span></div></div>
      <div class="evt"><b>Qua, 14 · 14:00 · Paula Reis</b><span class="lead">Responsável: Rui (saiu)</span></div>
      <div class="evt"><b>Qui, 15 · 09:00 · Marcos Lima</b><span class="lead">Responsável: Rui (saiu)</span></div>
      <div class="lead">Ao passar para outra pessoa, conferimos se ela está livre nesses horários.</div>`,1),
   },
   {n:'Meus horários', diff:'Novo: cada agente ajusta só os próprios dias e horas, dentro do que a página permite, e pode pausar a própria agenda sem pedir ao admin.', screen:()=>desk(`
      <h5>Meus horários</h5>
      <div class="row"><span class="pill g">Seg</span><span class="pill g">Ter</span><span class="pill g">Qua</span><span class="pill">Qui</span><span class="pill g">Sex</span></div>
      <div class="kv"><span>Das</span><b>10:00</b><span>Até</span><b>16:00</b><span>Limite da página</span><b>9h às 17h</b></div>
      <div class="loc"><div class="ic">⏸</div><div><b>Pausar a minha agenda</b><small>Ninguém marca com você até você voltar</small></div></div>
      <div class="lead">O admin vê quando alguém pausa, mas não precisa liberar.</div>`,2),
   },
  ],
  accept:[
   ['J8-A1','Existe o módulo de função <code>agendamento</code> com níveis Sem acesso, Ver e Gerenciar; <code>agendamento_manage</code> implica <code>agendamento_view</code>. O checklist de chave nova do CRM é cumprido por inteiro: lista de permissões, policy, matriz da tela de funções, i18n pt_BR e en, <code>meta.permissions</code> da rota, item do menu e <code>useCanManage</code> nos botões de escrita.'],
   ['J8-A2','O administrador mantém acesso total, como hoje.'],
   ['J8-A3','Agente sem função não vê "Configurações › Agendamento", mas vê "Agendar" nos cards e conversas que já pode editar, a própria agenda e os próprios números.'],
   ['J8-A4','Função com <code>agendamento_view</code> vê páginas e números da equipe sem poder editar: os botões de escrita ficam escondidos e a API recusa o acesso (401, padrão do sistema).'],
   ['J8-A5','Função com <code>agendamento_manage</code> cria, edita, publica e pausa páginas, escolhe modelos, marca e avisos. Não inclui conectar caixas e modelos de WhatsApp, usuários, funções, integrações nem faturamento.'],
   ['J8-A6','Função sem o módulo: a API recusa o acesso (401, padrão do sistema) em toda rota de gestão, mesmo conhecendo o endereço.'],
   ['J8-A7','Quem gera um link de cliente só consegue para clientes e conversas que já pode ver; o agente vê e cancela só os próprios links, e admin ou <code>agendamento_view</code> vê todos.'],
   ['J8-A8','A reunião tem um responsável. A agenda respeita o escopo atual de cards e o filtro "Meus ou Todos".'],
   ['J8-A9','<em>Quando</em> uma pessoa sai da conta, muda de função ou perde acesso ao que a página exige, <em>então</em> os links individuais dela pausam na hora e o admin recebe aviso com as reuniões futuras sem responsável.'],
   ['J8-A10','(Fase 2) O admin passa as reuniões para outra pessoa com um toque; o sistema confere se a nova pessoa está livre em cada horário e avisa os conflitos, sem criar dupla reserva.'],
   ['J8-A11','(Fase 2) "Meus horários": o agente ajusta só os próprios dias e horas dentro dos limites da página e pausa a própria agenda, sem precisar de <code>agendamento_manage</code>. Antes de criar, verificar se o horário por agente do SLA v2 pode ser reaproveitado.'],
   ['J8-A12','O painel (J7) mostra "Meus números" ao agente e a equipe a quem tem <code>agendamento_view</code> ou é admin; a lista "abriram e não marcaram" só mostra clientes que a pessoa pode ver.'],
   ['J8-A13','Os links individuais por agente funcionam sem caixa de e-mail: quem pode atender passa a ser uma pessoa da conta escolhida na página, e não mais membro da caixa.'],
   ['J8-A14','Existe um teste de permissões com a matriz completa: administrador, só vê, gerencia, agente sem função e função sem o módulo, contra configuração, convite, agenda e painel.'],
   ['J8-A15','O Guia da Plataforma explica quem pode o quê (<code>porques.md</code>) e <code>pnpm guia:build</code> e <code>guia:check</code> passam.'],
  ]
});

export default J;
