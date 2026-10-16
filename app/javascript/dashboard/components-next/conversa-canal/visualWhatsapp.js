// O visual do WhatsApp em classes do Tailwind (#1702). Cores, medidas, cantos e sombra
// seguem o WhatsApp Web; o fundo é um desenho nosso (a arte do app não é usada). Cada
// função devolve classes para a peça que já existe, sem trocar a peça.
import { MESSAGE_VARIANTS, ORIENTATION } from '../message/constants';

const SOMBRA = 'shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';

// Papel de parede (medido no WhatsApp Web de out/2026): bege claro com desenhos de
// traço fino (public/conversa-canal) ou cinza neutro no escuro. Fica parado enquanto
// as mensagens rolam e continua atrás da caixa de resposta, sem emenda.
const PAPEL_DE_PAREDE = [
  '!bg-[#F4F1EC] dark:!bg-[#161717] bg-fixed bg-[length:280px_280px]',
  'bg-[url(/conversa-canal/fundo-whatsapp-claro.svg)] dark:bg-[url(/conversa-canal/fundo-whatsapp-escuro.svg)]',
].join(' ');

// Sem avatar ao lado do balão, como no app: quem mandou aparece escrito no topo do
// balão, e a coluna vazia do avatar sai. Balões da mesma pessoa ficam a 2 px um do
// outro; quem abre a sequência ganha o respiro no próprio balão (classesDoBalao).
export const FUNDO_DA_CONVERSA = [
  PAPEL_DE_PAREDE,
  "!px-[6%] [&_[class*='grid-area:avatar']]:!hidden",
  "[&_.message-bubble-container>.grid]:!grid-cols-1 [&_.message-bubble-container>.grid]:![grid-template-areas:'bubble'_'meta']",
  '[&_.message-bubble-container]:!mb-[2px]',
].join(' ');

const TEXTO = 'text-[#0A0A0A] dark:text-[#FAFAFA]';
const SECUNDARIO = 'text-[#666666] dark:text-[#A7A8A8]';

const COR = {
  // Mensagem que a empresa mandou (atendente, robô, agente de IA, modelo).
  enviada: `!bg-[#D9FDD3] dark:!bg-[#144D37] ${TEXTO}`,
  // Mensagem do cliente.
  recebida: `!bg-white dark:!bg-[#242626] ${TEXTO}`,
  // Nota só para a equipe: nada parecido com o WhatsApp, para ninguém achar que o cliente viu.
  nota: '!bg-[#FFF3C4] dark:!bg-[#3D3214] text-[#4A3B00] dark:text-[#F5E3A3] border border-dashed border-[#D9B44A] dark:border-[#8C7426]',
  erro: '!bg-[#FDE7E9] dark:!bg-[#3B1F24] text-[#7A1F2B] dark:text-[#F4C7CD]',
  naoSuportada:
    '!bg-[#FFF3C4] dark:!bg-[#3D3214] border border-dashed border-[#D9B44A] text-[#4A3B00] dark:text-[#F5E3A3]',
};

const COR_POR_VARIANTE = {
  [MESSAGE_VARIANTS.AGENT]: COR.enviada,
  [MESSAGE_VARIANTS.BOT]: COR.enviada,
  [MESSAGE_VARIANTS.TEMPLATE]: COR.enviada,
  [MESSAGE_VARIANTS.USER]: COR.recebida,
  [MESSAGE_VARIANTS.PRIVATE]: COR.nota,
  [MESSAGE_VARIANTS.ERROR]: COR.erro,
  [MESSAGE_VARIANTS.UNSUPPORTED]: COR.naoSuportada,
};

// Botões das mensagens ricas (botão de link, opções): no app eles ficam dentro do
// balão, separados por uma linha fina, com o texto azul no meio.
// A linha vai de ponta a ponta do balão e a hora fica acima dela, junto do texto.
const BOTOES_RICOS = [
  '[&_.bg-n-solid-3]:!bg-transparent [&_.bg-n-solid-3]:!border-x-0 [&_.bg-n-solid-3]:!border-b-0 [&_.bg-n-solid-3]:!rounded-none',
  '[&_.bg-n-solid-3]:!border-t [&_.bg-n-solid-3]:!border-t-[#0A0A0A]/10 dark:[&_.bg-n-solid-3]:!border-t-white/10',
  '[&_.bg-n-solid-3]:!text-[#1A6B42] dark:[&_.bg-n-solid-3]:!text-[#6FD07E] [&_.bg-n-solid-3]:font-medium',
  '[&[data-bubble-name=rich-link-button]]:!px-[9px] [&[data-bubble-name=rich-link-button]]:!pt-[6px] [&[data-bubble-name=rich-link-button]]:!pb-0',
  '[&[data-bubble-name=rich-location-request]]:!px-[9px] [&[data-bubble-name=rich-location-request]]:!pt-[6px] [&[data-bubble-name=rich-location-request]]:!pb-0',
  '[&[data-bubble-name=rich-link-button]_.bg-n-solid-3]:!w-[calc(100%+18px)] [&[data-bubble-name=rich-link-button]_.bg-n-solid-3]:-mx-[9px] [&[data-bubble-name=rich-location-request]_.bg-n-solid-3]:!w-[calc(100%+18px)] [&[data-bubble-name=rich-location-request]_.bg-n-solid-3]:-mx-[9px] [&_.bg-n-solid-3]:!min-h-[44px]',
  '[&[data-bubble-name=rich-link-button]_.flex-col.gap-1]:pb-4 [&[data-bubble-name=rich-location-request]_.flex-col.gap-1]:pb-4',
  // "Pedimos ao cliente onde ele está" repete o botão: com o botão, sai (o cliente só vê o botão).
  '[&[data-bubble-name=rich-location-request]_.bg-n-solid-3~.text-xs]:!hidden',
  // "Abre: endereço" não existe no app: fica só para o leitor de tela (o botão mostra o endereço ao passar o mouse).
  '[&[data-bubble-name=rich-link-button]_.break-all]:sr-only',
].join(' ');

// Medidas do app: texto 14,2 px com linha de 19 px e recheio 6/7/8/9 px; foto e
// vídeo com moldura de 3 px. No fim do último parágrafo fica um espaço invisível do
// tamanho da hora, para a hora caber na última linha (o truque do próprio app).
const RECHEIO = [
  '[&[data-bubble-name=text]]:!pl-[9px] [&[data-bubble-name=text]]:!pr-[7px] [&[data-bubble-name=text]]:!pt-[6px] [&[data-bubble-name=text]]:!pb-[8px]',
  '[&[data-bubble-name=text]]:text-[14.2px] [&[data-bubble-name=text]]:leading-[19px]',
  "[&[data-bubble-name=text]_.prose-bubble>p:last-child]:after:inline-block [&[data-bubble-name=text]_.prose-bubble>p:last-child]:after:w-[64px] [&[data-bubble-name=text]_.prose-bubble>p:last-child]:after:content-['']",
  '[&[data-bubble-name=image]]:!p-[3px] [&[data-bubble-name=video]]:!p-[3px]',
  // Foto: canto de 6 px por dentro e sem os botões do painel por cima (abrir é tocar na foto).
  '[&[data-bubble-name=image]_.rounded-lg]:!rounded-[8px] [&[data-bubble-name=image]_.inset-0]:!hidden [&[data-bubble-name=image]_.right-2]:!hidden',
  // Foto até 330 px de lado; a retrato é cortada embaixo, como no app.
  '[&[data-bubble-name=image]_img]:!w-[330px] [&[data-bubble-name=image]_img]:max-w-full [&[data-bubble-name=image]_img]:!h-auto [&[data-bubble-name=image]_img]:max-h-[330px] [&[data-bubble-name=image]_img]:object-cover [&[data-bubble-name=image]_img]:object-top',
  // Documento: o cartão com 3 px de moldura, 320 px, e a hora embaixo.
  '[&[data-bubble-name=attachment]]:!p-[3px] [&[data-bubble-name=attachment]]:w-[320px] [&[data-bubble-name=attachment]]:max-w-full [&[data-bubble-name=attachment]>[class*=mt-]]:!px-[5px] [&[data-bubble-name=attachment]>[class*=mt-]]:!pb-[2px]',
  // Foto com legenda: a foto grande em cima e a legenda embaixo, como no app.
  '[&[data-bubble-name=text]>div:has(.contain-content)]:!flex-col-reverse [&[data-bubble-name=text]>div:has(.contain-content)]:!gap-1.5',
  '[&[data-bubble-name=text]:has(.contain-content)]:!pt-[3px] [&[data-bubble-name=text]:has(.contain-content)]:!pl-[3px] [&[data-bubble-name=text]:has(.contain-content)]:!pr-[3px]',
  '[&[data-bubble-name=text]_.contain-content]:!w-[330px] [&[data-bubble-name=text]_.contain-content]:!max-w-full [&[data-bubble-name=text]_.contain-content]:!h-auto [&[data-bubble-name=text]_.contain-content]:!rounded-[8px]',
  // A foto inteira, na proporção dela (como no app), até 330 px de altura.
  '[&[data-bubble-name=text]_.contain-content_img]:!h-auto [&[data-bubble-name=text]_.contain-content_img]:max-h-[330px] [&[data-bubble-name=text]_.contain-content_img]:object-top',
  '[&[data-bubble-name=text]:has(.contain-content)_.prose-bubble]:block [&[data-bubble-name=text]:has(.contain-content)_.prose-bubble]:px-1.5',
].join(' ');

// Citação (resposta a uma mensagem): faixa verde à esquerda e fundo levemente
// escurecido, como no app.
const CITACAO = [
  '[&_.bg-n-alpha-black1]:!bg-[#0A0A0A]/[0.05] dark:[&_.bg-n-alpha-black1]:!bg-[#000]/20',
  '[&_.bg-n-alpha-black1]:border-l-4 [&_.bg-n-alpha-black1]:border-[#06CF9C] [&_.bg-n-alpha-black1]:!rounded-[8px] [&_.bg-n-alpha-black1]:!mx-0',
].join(' ');

// Áudio: o tocador sem moldura, 320 px como no app (a hora fica no canto, na linha da duração).
const AUDIO = [
  '[&[data-bubble-name=audio]]:w-[320px] [&[data-bubble-name=audio]]:max-w-full [&[data-bubble-name=audio]]:!px-[6px] [&[data-bubble-name=audio]]:!py-[6px]',
  '[&[data-bubble-name=audio]_.border-n-container]:!border-0 [&[data-bubble-name=audio]_.border-n-container]:!bg-transparent [&[data-bubble-name=audio]_.border-n-container]:!shadow-none',
].join(' ');

// Localização (enviada e recebida): o mapa em cima, o nome e o endereço embaixo, sem
// a frase "fulano compartilhou" — como o cartão do app.
const LOCALIZACAO = [
  '[&[data-bubble-name$=location]]:!p-[3px] [&[data-bubble-name$=location]]:w-[300px] [&[data-bubble-name$=location]_.min-w-64]:!gap-1 [&[data-bubble-name$=location]_.gap-3]:!gap-1.5',
  '[&[data-bubble-name$=location]_.size-8]:!w-full [&[data-bubble-name$=location]_.size-8]:!h-[140px] [&[data-bubble-name$=location]_.size-8]:!rounded-[8px] [&[data-bubble-name$=location]_.size-8]:!bg-[#E3E8DD] dark:[&[data-bubble-name$=location]_.size-8]:!bg-[#1F3A33]',
  '[&[data-bubble-name$=location]_.size-8]:bg-[linear-gradient(90deg,rgba(255,255,255,0.6)_2px,transparent_2px),linear-gradient(rgba(255,255,255,0.6)_2px,transparent_2px)] [&[data-bubble-name$=location]_.size-8]:bg-[length:34px_26px] dark:[&[data-bubble-name$=location]_.size-8]:bg-[linear-gradient(90deg,rgba(255,255,255,0.07)_2px,transparent_2px),linear-gradient(rgba(255,255,255,0.07)_2px,transparent_2px)]',
  // O pino do mapa: um ponto vermelho com borda branca no meio (o ícone de seta sai).
  "[&[data-bubble-name$=location]_.size-8>*]:!hidden [&[data-bubble-name$=location]_.size-8]:after:size-5 [&[data-bubble-name$=location]_.size-8]:after:rounded-full [&[data-bubble-name$=location]_.size-8]:after:bg-[#E53935] [&[data-bubble-name$=location]_.size-8]:after:border-[3px] [&[data-bubble-name$=location]_.size-8]:after:border-white [&[data-bubble-name$=location]_.size-8]:after:shadow-md [&[data-bubble-name$=location]_.size-8]:after:content-['']",
  '[&[data-bubble-name$=location]_.space-y-1]:!px-1.5 [&[data-bubble-name$=location]_.space-y-1>div:first-child]:hidden [&[data-bubble-name$=location]_.space-y-1>div:nth-child(2)]:font-medium',
].join(' ');

// Balão: cantos de 7,5 px em todos; o primeiro de cada sequência tem o canto de cima
// reto do lado do bico, como no app.
export const classesDoBalao = ({ variante, lado, primeira }) => {
  if (variante === MESSAGE_VARIANTS.ACTIVITY) {
    return `!bg-white/95 dark:!bg-[#1D1F1F] text-[#3B3B3B] dark:text-[#A7A8A8] text-xs !rounded-lg text-center ${SOMBRA}`;
  }
  const cor = COR_POR_VARIANTE[variante] || COR.recebida;
  const cantos = ['group/balao relative !rounded-[10px]', SOMBRA];
  // Quem abre a sequência ganha 10 px acima (12 px com os 2 px entre balões).
  if (primeira) cantos.push('mt-[10px]');
  if (primeira && lado === ORIENTATION.LEFT) {
    cantos.push('ltr:!rounded-tl-none rtl:!rounded-tr-none');
  }
  if (primeira && lado === ORIENTATION.RIGHT) {
    cantos.push('ltr:!rounded-tr-none rtl:!rounded-tl-none');
  }
  return [
    cor,
    ...cantos,
    RECHEIO,
    BOTOES_RICOS,
    CITACAO,
    AUDIO,
    LOCALIZACAO,
  ].join(' ');
};

// Bico só no primeiro balão da sequência e só nos balões de conversa.
export const temBico = ({ variante, primeira }) =>
  primeira &&
  ![
    MESSAGE_VARIANTS.ACTIVITY,
    MESSAGE_VARIANTS.PRIVATE,
    MESSAGE_VARIANTS.EMAIL,
  ].includes(variante);

export const corDoBico = ({ variante }) => {
  if (variante === MESSAGE_VARIANTS.USER) {
    return 'text-white dark:text-[#242626]';
  }
  if (variante === MESSAGE_VARIANTS.ERROR) {
    return 'text-[#FDE7E9] dark:text-[#3B1F24]';
  }
  if (variante === MESSAGE_VARIANTS.UNSUPPORTED) {
    return 'text-[#FFF3C4] dark:text-[#3D3214]';
  }
  return 'text-[#D9FDD3] dark:text-[#144D37]';
};

// No balão enviado escuro o cinza do app fica abaixo de 4,5:1; o nosso puxa para o verde.
const HORA_NO_ENVIADO = 'text-[#666666] dark:text-[#B5C2BC]';
const COR_DA_HORA = {
  [MESSAGE_VARIANTS.PRIVATE]: 'text-[#4A3B00]/70 dark:text-[#F5E3A3]/70',
  [MESSAGE_VARIANTS.AGENT]: HORA_NO_ENVIADO,
  [MESSAGE_VARIANTS.BOT]: HORA_NO_ENVIADO,
  [MESSAGE_VARIANTS.TEMPLATE]: HORA_NO_ENVIADO,
};

// Foto e vídeo sem legenda: hora e tiques brancos por cima da mídia, num degradê.
const SOBRE_A_MIDIA = [
  'absolute bottom-[3px] inset-x-[3px] justify-end !mt-0 h-7 items-end pb-[5px] ltr:pr-[7px] rtl:pl-[7px]',
  'rounded-b-[8px] bg-gradient-to-t from-[#000]/45 to-transparent !text-white pointer-events-none',
].join(' ');

// Hora e tiques: 11 px, cinza. No texto, presos no canto de baixo à direita (por cima
// do espaço reservado na última linha); nos outros balões, numa linha só deles.
export const classesDaHora = ({ variante, nomeDoBalao }) => {
  if (['image', 'video'].includes(nomeDoBalao)) {
    return `${SOBRE_A_MIDIA} text-[11px] leading-[15px]`;
  }
  const cor = COR_DA_HORA[variante] || SECUNDARIO;
  const ACIMA_DO_BOTAO = [
    'rich-link-button',
    'rich-location-request',
    'contact-acao',
  ];
  let lugar = 'justify-end !mt-0.5';
  if (nomeDoBalao === 'text') {
    lugar = 'absolute bottom-[3px] ltr:right-[7px] rtl:left-[7px] !mt-0';
  } else if (nomeDoBalao === 'audio') {
    lugar = 'absolute bottom-[5px] ltr:right-[8px] rtl:left-[8px] !mt-0';
  } else if (ACIMA_DO_BOTAO.includes(nomeDoBalao)) {
    // Sem o botão (pedir localização fora da Cloud), a hora volta para o pé do balão.
    lugar =
      'absolute bottom-[48px] ltr:right-[7px] rtl:left-[7px] !mt-0 [[data-bubble-name]:not(:has(.bg-n-solid-3,button))_&]:static [[data-bubble-name]:not(:has(.bg-n-solid-3,button))_&]:!mt-0.5 [[data-bubble-name]:not(:has(.bg-n-solid-3,button))_&]:pb-1.5';
  }
  return `${lugar} text-[11px] leading-[15px] ${cor}`;
};

// Nome de quem mandou, no topo do balão enviado: no app não existe, mas aqui a
// equipe precisa saber se foi a Ana, o Pedro ou o agente de IA.
export const CLASSES_DO_REMETENTE = [
  'text-[12.8px] leading-[22px] font-medium text-[#008069] dark:text-[#06CF9C]',
  // Em foto e localização o balão tem moldura fina: o nome ganha o recuo do texto.
  '[[data-bubble-name=text]:has(.contain-content)_&]:px-1.5 [[data-bubble-name$=location]_&]:px-1.5',
].join(' ');

export const CLASSES_DO_SEPARADOR_DE_DIA = `px-3 py-[5px] rounded-[7.5px] text-[12.5px] bg-white dark:bg-[#1D1F1F] ${SECUNDARIO} ${SOMBRA}`;

// Topo da conversa: da cor do painel (branco no claro, o cinza do fundo no escuro), 64 px.
export const TOPO_DA_CONVERSA =
  '!bg-white dark:!bg-[#161717] xl:!h-16 !px-4 !border-b-[#000]/[0.06] dark:!border-b-white/[0.06]';

// Caixa de resposta como no app de out/2026: uma pílula branca de 52 px flutuando sobre
// o papel de parede, com "+", ícones, o campo e o botão da direita dentro dela. A
// pílula é feita de três peças lado a lado (ícones, campo, botão), cada uma com a sua
// ponta arredondada. A escolha "Responder / Mensagem privada" fica em cima, pequena.
// O Tailwind só gera classe escrita por extenso: cada peça tem a sua lista completa.
const PILULA_ESQUERDA = [
  '[&_.left-wrap]:order-1 [&_.left-wrap]:!gap-0 [&_.left-wrap]:ps-1.5 [&_.left-wrap]:min-h-[52px] [&_.left-wrap]:flex [&_.left-wrap]:items-center',
  '[&_.left-wrap]:bg-white dark:[&_.left-wrap]:bg-[#242626] ltr:[&_.left-wrap]:rounded-l-[26px] rtl:[&_.left-wrap]:rounded-r-[26px]',
].join(' ');
const PILULA_DIREITA = [
  '[&_.right-wrap]:order-3 [&_.right-wrap]:pe-1.5 [&_.right-wrap]:min-h-[52px] [&_.right-wrap]:flex [&_.right-wrap]:items-center',
  '[&_.right-wrap]:bg-white dark:[&_.right-wrap]:bg-[#242626] ltr:[&_.right-wrap]:rounded-r-[26px] rtl:[&_.right-wrap]:rounded-l-[26px]',
].join(' ');

export const CAIXA_DE_RESPOSTA = {
  // A alça de arrastar a altura (com degradê cinza) some: o campo já cresce sozinho.
  barra: `${PAPEL_DE_PAREDE} [&_.cursor-row-resize]:!hidden`,
  caixa: [
    '!mx-0 !mb-0 !rounded-none !border-0 !bg-transparent',
    'flex flex-wrap items-stretch gap-x-0 px-4 pb-3 [filter:drop-shadow(0_1px_1px_rgba(0,0,0,0.08))]',
    '[&>*:first-child]:basis-full [&>*:first-child]:!h-9',
    PILULA_ESQUERDA,
    // No celular os ícones ficam numa pílula própria e o campo ganha a largura toda.
    'max-md:[&_.left-wrap]:basis-full max-md:[&_.left-wrap]:!rounded-[26px] max-md:[&_.left-wrap]:mb-1.5',
    PILULA_DIREITA,
    // Ícones como no app: soltos, sem caixinha, 24 px; círculo só ao passar o mouse.
    '[&_.left-wrap_button:not([role=menuitem])]:!size-10 [&_.left-wrap_button:not([role=menuitem])]:!p-0 [&_.left-wrap_button:not([role=menuitem])]:!rounded-full [&_.left-wrap_button:not([role=menuitem])]:!bg-transparent',
    '[&_.left-wrap_button:not([role=menuitem])]:!text-[#3B3B3B] dark:[&_.left-wrap_button:not([role=menuitem])]:!text-[#FAFAFA] [&_.left-wrap_button:not([role=menuitem]):hover]:!bg-[#0A0A0A]/5 dark:[&_.left-wrap_button:not([role=menuitem]):hover]:!bg-white/5',
    "[&_.left-wrap_button:not([role=menuitem])>span[class*='i-']]:!size-6 [&_.left-wrap_.file-uploads]:!overflow-visible",
    // O campo cresce sozinho com o texto, como no app; o botão de aumentar sai.
    '[&_button:has(.i-lucide-maximize-2)]:!hidden',
  ].join(' '),
  campo: [
    'order-2 flex-1 min-w-0 !mx-0 !px-2 !py-[14px] min-h-[52px] flex items-center rounded-none !bg-white dark:!bg-[#242626]',
    'max-md:ltr:rounded-l-[26px] max-md:rtl:rounded-r-[26px] max-md:!ps-4',
    'text-[15px] text-[#0A0A0A] dark:text-[#FAFAFA]',
    '[&_.resizable-editor-body]:!h-auto [&_.resizable-editor-body]:!min-h-[24px] [&_.resizable-editor-body]:!max-h-[40vh] [&>*]:w-full',
  ].join(' '),
  // Só na resposta ao cliente: o "+" faz o papel do clipe (o seletor de arquivo, o
  // arrastar e o atalho continuam) e o microfone fica na ponta direita da pílula.
  soResposta:
    '[&_.left-wrap_.file-uploads]:!hidden [&_.left-wrap_button:has(.i-ph-microphone)]:!hidden',
  // Mensagem privada: a mesma pílula, no amarelo da nota, para ninguém achar que o cliente vê.
  nota: [
    '[&_.left-wrap]:!bg-[#FFF3C4] dark:[&_.left-wrap]:!bg-[#3D3214] [&_.right-wrap]:!bg-[#FFF3C4] dark:[&_.right-wrap]:!bg-[#3D3214]',
    '[&_.order-2]:!bg-[#FFF3C4] dark:[&_.order-2]:!bg-[#3D3214] [&_.order-2]:!text-[#4A3B00] dark:[&_.order-2]:!text-[#F5E3A3]',
  ].join(' '),
  painel: 'contents',
  // Enquanto grava, a barra inteira vira o gravador.
  gravando:
    '[&_.left-wrap]:!hidden [&_.right-wrap]:!hidden [&_:has(>[data-gravador-do-whatsapp])]:!rounded-[26px] [&_:has(>[data-gravador-do-whatsapp])]:!px-3',
  // Enviar: círculo preto, como no app (no escuro, o verde do app).
  enviar:
    '!size-10 !p-0 !rounded-full !bg-[#0A0A0A] hover:enabled:!bg-[#2B2B2B] disabled:!bg-[#0A0A0A]/40 !text-white dark:!bg-[#21C063] dark:hover:enabled:!bg-[#1DA855] dark:!text-[#0A0A0A]',
  enviarNota:
    '!size-10 !p-0 !rounded-full !bg-[#D9B44A] hover:enabled:!bg-[#C9A43A] disabled:!bg-[#D9B44A]/50 !text-[#2B2200]',
  iconeEnviar: 'i-ph-paper-plane-right-fill',
  // Microfone com o campo vazio: só o ícone, na ponta da pílula.
  microfone:
    'grid place-content-center size-10 rounded-full text-[#3B3B3B] dark:text-[#FAFAFA] hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5',
};
