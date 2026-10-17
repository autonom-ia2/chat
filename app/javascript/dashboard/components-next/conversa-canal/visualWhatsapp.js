// O visual do WhatsApp em classes do Tailwind (#1702). Cores, medidas, cantos e sombra
// seguem o WhatsApp Web; o fundo é um desenho nosso (a arte do app não é usada). Cada
// função devolve classes para a peça que já existe, sem trocar a peça.
import { MESSAGE_VARIANTS, ORIENTATION } from '../message/constants';

const SOMBRA = 'shadow-[0_1px_0.5px_rgba(11,20,26,0.13)]';

// Fundo da conversa: bege com desenhos de traço fino (public/conversa-canal), que
// rolam junto com as mensagens. Sem avatar ao lado do balão, como no app: quem mandou
// aparece escrito no topo do balão.
export const FUNDO_DA_CONVERSA = [
  '!bg-[#EFEAE2] dark:!bg-[#0B141A] bg-local bg-[length:280px_280px]',
  'bg-[url(/conversa-canal/fundo-whatsapp-claro.svg)] dark:bg-[url(/conversa-canal/fundo-whatsapp-escuro.svg)]',
  "!px-[6%] [&_[class*='grid-area:avatar']]:!hidden",
].join(' ');

const TEXTO = 'text-[#111B21] dark:text-[#E9EDEF]';

const COR = {
  // Mensagem que a empresa mandou (atendente, robô, agente de IA, modelo).
  enviada: `!bg-[#D9FDD3] dark:!bg-[#005C4B] ${TEXTO}`,
  // Mensagem do cliente.
  recebida: `!bg-white dark:!bg-[#202C33] ${TEXTO}`,
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
  '[&_.bg-n-solid-3]:!border-t [&_.bg-n-solid-3]:!border-t-[#111B21]/10 dark:[&_.bg-n-solid-3]:!border-t-white/10',
  '[&_.bg-n-solid-3]:!text-[#027EB5] dark:[&_.bg-n-solid-3]:!text-[#53BDEB] [&_.bg-n-solid-3]:font-medium',
  '[&[data-bubble-name=rich-link-button]]:!px-[9px] [&[data-bubble-name=rich-link-button]]:!pt-[6px] [&[data-bubble-name=rich-link-button]]:!pb-0',
  '[&[data-bubble-name=rich-location-request]]:!px-[9px] [&[data-bubble-name=rich-location-request]]:!pt-[6px] [&[data-bubble-name=rich-location-request]]:!pb-0',
  '[&[data-bubble-name=rich-link-button]_.bg-n-solid-3]:!w-[calc(100%+18px)] [&[data-bubble-name=rich-link-button]_.bg-n-solid-3]:-mx-[9px] [&[data-bubble-name=rich-location-request]_.bg-n-solid-3]:!w-[calc(100%+18px)] [&[data-bubble-name=rich-location-request]_.bg-n-solid-3]:-mx-[9px] [&_.bg-n-solid-3]:!min-h-[44px]',
  '[&[data-bubble-name=rich-link-button]_.flex-col.gap-1]:pb-4 [&[data-bubble-name=rich-location-request]_.flex-col.gap-1]:pb-4',
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
  // Foto com legenda: a foto grande em cima e a legenda embaixo, como no app.
  '[&[data-bubble-name=text]>div:has(.contain-content)]:!flex-col-reverse [&[data-bubble-name=text]>div:has(.contain-content)]:!gap-1.5',
  '[&[data-bubble-name=text]:has(.contain-content)]:!pt-[3px] [&[data-bubble-name=text]:has(.contain-content)]:!pl-[3px] [&[data-bubble-name=text]:has(.contain-content)]:!pr-[3px]',
  '[&[data-bubble-name=text]_.contain-content]:!w-[300px] [&[data-bubble-name=text]_.contain-content]:!max-w-full [&[data-bubble-name=text]_.contain-content]:!h-[220px] [&[data-bubble-name=text]_.contain-content]:!rounded-[6px]',
  '[&[data-bubble-name=text]:has(.contain-content)_.prose-bubble]:block [&[data-bubble-name=text]:has(.contain-content)_.prose-bubble]:px-1.5',
].join(' ');

// Citação (resposta a uma mensagem): faixa verde à esquerda e fundo levemente
// escurecido, como no app.
const CITACAO = [
  '[&_.bg-n-alpha-black1]:!bg-[#111B21]/[0.05] dark:[&_.bg-n-alpha-black1]:!bg-black/20',
  '[&_.bg-n-alpha-black1]:border-l-4 [&_.bg-n-alpha-black1]:border-[#06CF9C] [&_.bg-n-alpha-black1]:!rounded-[6px] [&_.bg-n-alpha-black1]:!mx-0',
].join(' ');

// Áudio: o tocador sem moldura, na largura do app, com a barra verde.
const AUDIO = [
  '[&[data-bubble-name=audio]]:min-w-[280px] md:[&[data-bubble-name=audio]]:min-w-[340px] [&[data-bubble-name=audio]]:!p-1',
  '[&[data-bubble-name=audio]_.border-n-container]:!border-0 [&[data-bubble-name=audio]_.border-n-container]:!bg-transparent [&[data-bubble-name=audio]_.border-n-container]:!shadow-none',
  '[&[data-bubble-name=audio]_input]:!accent-[#00A884] [&[data-bubble-name=audio]_button>span]:!text-[#54656F] dark:[&[data-bubble-name=audio]_button>span]:!text-[#AEBAC1]',
].join(' ');

// Localização (enviada e recebida): o mapa em cima, o nome e o endereço embaixo, sem
// a frase "fulano compartilhou" — como o cartão do app.
const LOCALIZACAO = [
  '[&[data-bubble-name$=location]]:!p-[3px] [&[data-bubble-name$=location]]:w-[300px] [&[data-bubble-name$=location]_.min-w-64]:!gap-1 [&[data-bubble-name$=location]_.gap-3]:!gap-1.5',
  '[&[data-bubble-name$=location]_.size-8]:!w-full [&[data-bubble-name$=location]_.size-8]:!h-[140px] [&[data-bubble-name$=location]_.size-8]:!rounded-[6px] [&[data-bubble-name$=location]_.size-8]:!bg-[#E3E8DD] dark:[&[data-bubble-name$=location]_.size-8]:!bg-[#1F3A33]',
  '[&[data-bubble-name$=location]_.size-8]:bg-[linear-gradient(90deg,rgba(255,255,255,0.6)_2px,transparent_2px),linear-gradient(rgba(255,255,255,0.6)_2px,transparent_2px)] [&[data-bubble-name$=location]_.size-8]:bg-[length:34px_26px] dark:[&[data-bubble-name$=location]_.size-8]:bg-[linear-gradient(90deg,rgba(255,255,255,0.07)_2px,transparent_2px),linear-gradient(rgba(255,255,255,0.07)_2px,transparent_2px)]',
  // O pino do mapa: um ponto vermelho com borda branca no meio (o ícone de seta sai).
  "[&[data-bubble-name$=location]_.size-8>*]:!hidden [&[data-bubble-name$=location]_.size-8]:after:size-5 [&[data-bubble-name$=location]_.size-8]:after:rounded-full [&[data-bubble-name$=location]_.size-8]:after:bg-[#E53935] [&[data-bubble-name$=location]_.size-8]:after:border-[3px] [&[data-bubble-name$=location]_.size-8]:after:border-white [&[data-bubble-name$=location]_.size-8]:after:shadow-md [&[data-bubble-name$=location]_.size-8]:after:content-['']",
  '[&[data-bubble-name$=location]_.space-y-1]:!px-1.5 [&[data-bubble-name$=location]_.space-y-1>div:first-child]:hidden [&[data-bubble-name$=location]_.space-y-1>div:nth-child(2)]:font-medium',
].join(' ');

// Contato: foto redonda cinza e o nome ao lado, sem a frase "fulano compartilhou".
const CONTATO = [
  '[&[data-bubble-name=rich-contact]_.gap-3]:!flex [&[data-bubble-name=rich-contact]_.gap-3]:items-center [&[data-bubble-name=rich-contact]]:w-[280px]',
  '[&[data-bubble-name=rich-contact]_.size-8]:!size-12 [&[data-bubble-name=rich-contact]_.size-8]:!rounded-full [&[data-bubble-name=rich-contact]_.size-8]:!bg-[#DFE5E7] dark:[&[data-bubble-name=rich-contact]_.size-8]:!bg-[#6A7175] [&[data-bubble-name=rich-contact]_.size-8>*]:!size-7',
  '[&[data-bubble-name=rich-contact]_.space-y-1>div:first-child]:hidden [&[data-bubble-name=rich-contact]_.space-y-1>div:nth-child(2)]:font-medium [&[data-bubble-name=rich-contact]_.space-y-1>div:nth-child(2)]:text-[15px]',
].join(' ');

// Balão: cantos de 7,5 px em todos; o primeiro de cada sequência tem o canto de cima
// reto do lado do bico, como no app.
export const classesDoBalao = ({ variante, lado, primeira }) => {
  if (variante === MESSAGE_VARIANTS.ACTIVITY) {
    return `!bg-white/95 dark:!bg-[#182229] text-[#54656F] dark:text-[#8696A0] text-xs !rounded-lg text-center ${SOMBRA}`;
  }
  const cor = COR_POR_VARIANTE[variante] || COR.recebida;
  const cantos = ['relative !rounded-[7.5px]', SOMBRA];
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
    CONTATO,
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
    return 'text-white dark:text-[#202C33]';
  }
  if (variante === MESSAGE_VARIANTS.ERROR) {
    return 'text-[#FDE7E9] dark:text-[#3B1F24]';
  }
  if (variante === MESSAGE_VARIANTS.UNSUPPORTED) {
    return 'text-[#FFF3C4] dark:text-[#3D3214]';
  }
  return 'text-[#D9FDD3] dark:text-[#005C4B]';
};

const COR_DA_HORA = {
  [MESSAGE_VARIANTS.PRIVATE]: 'text-[#4A3B00]/70 dark:text-[#F5E3A3]/70',
  [MESSAGE_VARIANTS.USER]: 'text-[#667781] dark:text-[#FFFFFF]/60',
};

// Hora e tiques: 11 px, cinza. No texto, presos no canto de baixo à direita (por cima
// do espaço reservado na última linha); nos outros balões, numa linha só deles.
export const classesDaHora = ({ variante, nomeDoBalao }) => {
  const cor = COR_DA_HORA[variante] || 'text-[#667781] dark:text-[#FFFFFF]/60';
  const ACIMA_DO_BOTAO = ['rich-link-button', 'rich-location-request'];
  let lugar = 'justify-end !mt-0.5';
  if (nomeDoBalao === 'text') {
    lugar = 'absolute bottom-[3px] ltr:right-[7px] rtl:left-[7px] !mt-0';
  } else if (ACIMA_DO_BOTAO.includes(nomeDoBalao)) {
    lugar = 'absolute bottom-[48px] ltr:right-[7px] rtl:left-[7px] !mt-0';
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

export const CLASSES_DO_SEPARADOR_DE_DIA = `px-3 py-[5px] rounded-[7.5px] text-[12.5px] bg-white dark:bg-[#182229] text-[#54656F] dark:text-[#8696A0] ${SOMBRA}`;

// Topo da conversa: a faixa cinza do app.
export const TOPO_DA_CONVERSA =
  '!bg-[#F0F2F5] dark:!bg-[#202C33] xl:!h-[60px] !px-4 !border-b-[#E9EDEF] dark:!border-b-[#2A3942]';

// Caixa de resposta numa linha só, como no app: ícones à esquerda, o campo branco
// arredondado no meio e o enviar redondo à direita. A escolha "Responder / Mensagem
// privada" continua em cima, pequena. Nada some: só muda de lugar.
export const CAIXA_DE_RESPOSTA = {
  barra: '!bg-[#F0F2F5] dark:!bg-[#202C33]',
  caixa: [
    '!mx-0 !mb-0 !rounded-none !border-0 !bg-[#F0F2F5] dark:!bg-[#202C33]',
    'flex flex-wrap items-end gap-x-1 px-2.5 pb-2.5',
    '[&>*:first-child]:basis-full [&>*:first-child]:!h-10',
    '[&_.left-wrap]:order-1 [&_.left-wrap]:!gap-0.5 [&_.left-wrap]:pb-1',
    // No celular os ícones ficam numa linha própria e o campo ganha a largura toda.
    'max-md:[&_.left-wrap]:basis-full max-md:[&_.left-wrap]:pb-1.5',
    '[&_.right-wrap]:order-3 [&_.right-wrap]:pb-1',
    // Ícones como no app: soltos, sem caixinha, 24 px, cinza do WhatsApp; círculo só ao passar o mouse.
    '[&_.left-wrap_button:not([role=menuitem])]:!size-11 [&_.left-wrap_button:not([role=menuitem])]:!p-0 [&_.left-wrap_button:not([role=menuitem])]:!rounded-full [&_.left-wrap_button:not([role=menuitem])]:!bg-transparent',
    '[&_.left-wrap_button:not([role=menuitem])]:!text-[#54656F] dark:[&_.left-wrap_button:not([role=menuitem])]:!text-[#AEBAC1] [&_.left-wrap_button:not([role=menuitem]):hover]:!bg-[#111B21]/5 dark:[&_.left-wrap_button:not([role=menuitem]):hover]:!bg-white/5',
    "[&_.left-wrap_button:not([role=menuitem])>span[class*='i-']]:!size-6 [&_.left-wrap_.file-uploads]:!overflow-visible",
    // O "+" faz o papel do clipe (o seletor de arquivo, o arrastar e o atalho continuam) e o
    // microfone fica no botão redondo da direita, como no app.
    '[&_.left-wrap_.file-uploads]:!hidden [&_.left-wrap_button:has(.i-ph-microphone)]:!hidden',
    // O campo cresce sozinho com o texto, como no app; o botão de aumentar sai.
    '[&_button:has(.i-lucide-maximize-2)]:!hidden',
  ].join(' '),
  campo: [
    'order-2 flex-1 min-w-0 !mx-1 !px-3 !py-[3px] rounded-lg !bg-white dark:!bg-[#2A3942] text-[15px] text-[#111B21] dark:text-[#D1D7DB]',
    '[&_.resizable-editor-body]:!h-auto [&_.resizable-editor-body]:!min-h-[24px] [&_.resizable-editor-body]:!max-h-[40vh]',
  ].join(' '),
  painel: 'contents',
  // Enquanto grava, a barra inteira vira o gravador.
  gravando: '[&_.left-wrap]:!hidden [&_.right-wrap]:!hidden',
  enviar:
    '!size-11 !p-0 !rounded-full !bg-[#00A884] hover:enabled:!bg-[#008F72] disabled:!bg-[#00A884]/50 !text-white dark:!text-[#111B21]',
  iconeEnviar: 'i-ph-paper-plane-right-fill',
};
