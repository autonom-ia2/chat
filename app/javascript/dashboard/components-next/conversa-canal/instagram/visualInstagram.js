// O visual do Instagram Direct (web) na conversa do painel (#2079). As cores são as
// variáveis `--ig-*` do próprio instagram.com, medidas em 22/10/2026 nos modos claro e
// escuro (a especificação completa está na Issue). O Tailwind só gera classe escrita por
// extenso, então cada combinação fica aqui inteira.

export const FUNDO = 'bg-white dark:bg-[#0C1014]';
export const TEXTO = 'text-[#0C1014] dark:text-[#F5F5F5]';
export const SECUNDARIO = 'text-[#6A717A] dark:text-[#A8A8A8]';
export const FONTE =
  "font-['-apple-system','system-ui','Segoe_UI',Roboto,Helvetica,Arial,sans-serif]";

// Balões: recebido no cinza do app, enviado no azul-violeta.
export const RECEBIDO = `bg-[#F3F5F7] dark:bg-[#25292E] ${TEXTO}`;
export const ENVIADO = 'bg-[#4A5DF9] text-white';
export const BALAO_DE_TEXTO =
  'px-3 py-2 text-[15px] leading-5 max-w-[564px] whitespace-pre-wrap break-words [overflow-wrap:anywhere]';

// Cabeçalho do post compartilhado, pílula de reação e barra de citação.
export const ELEVADO = 'bg-[#F3F5F7] dark:bg-[#262626]';
export const BARRA_DE_CITACAO =
  'w-1 shrink-0 rounded-sm bg-[#F3F5F7] dark:bg-[#262626]';

// Selo de reação (#2113): a pílula no canto de baixo do balão, com a borda na cor do
// fundo do app, como no Direct.
export const PILULA_DE_REACAO = `${ELEVADO} ${TEXTO} border-2 border-white dark:border-[#0C1014]`;

// No lugar da foto ou do vídeo que não abre (sem a nossa cópia, o endereço da Meta expira).
export const INDISPONIVEL = `flex items-center justify-center gap-1.5 px-3 text-center text-[13px] leading-4 ${ELEVADO} ${SECUNDARIO}`;

// Rótulos pequenos: horário entre as mensagens, "Visto", "Mencionou você no story".
export const ROTULO = `text-xs leading-4 ${SECUNDARIO}`;
export const HORARIO = `text-xs leading-4 font-light ${SECUNDARIO}`;

// Lista da conversa (a própria <ul> da MessageList): fundo do app; o respiro entre as
// linhas é da LinhaDoInstagram (2 px no grupo, 8 px entre grupos).
export const LISTA = [
  '!bg-white dark:!bg-[#0C1014]',
  FONTE,
  '[&_.message-bubble-container]:!mb-0',
].join(' ');

// Barra da resposta: fundo do app, sem a alça de arrastar a altura (o campo cresce sozinho).
export const BARRA_DA_RESPOSTA =
  '!bg-white dark:!bg-[#0C1014] !border-t-0 [&_.cursor-row-resize]:!hidden';

// Ícones da pílula: soltos, 24 px, na cor do texto, como no app.
const ICONES = [
  '[&_.left-wrap_button:not([role=menuitem])]:!size-9 [&_.left-wrap_button:not([role=menuitem])]:!p-0 [&_.left-wrap_button:not([role=menuitem])]:!rounded-full [&_.left-wrap_button:not([role=menuitem])]:!bg-transparent',
  '[&_.left-wrap_button:not([role=menuitem])]:!text-[#0C1014] dark:[&_.left-wrap_button:not([role=menuitem])]:!text-[#F5F5F5]',
  "[&_.left-wrap_button:not([role=menuitem])>span[class*='i-']]:!size-6 [&_.left-wrap_.file-uploads]:!overflow-visible",
].join(' ');

// Caixa de escrever: a pílula de 46 px, raio 22 e borda de 1 px do app, a 16 px das
// bordas. Responder / Mensagem privada ficam numa linha fina em cima; na pílula, o
// emoji à esquerda, o campo no meio e os outros ícones e o "Enviar" à direita. A
// pílula é desenhada por trás (before), porque os ícones e o campo são irmãos.
// As chaves são as mesmas da pele do WhatsApp (usePeleDaResposta).
export const CAIXA_DO_INSTAGRAM = {
  barra: '',
  caixa: [
    '!mx-0 !mb-0 !rounded-none !border-0 !bg-transparent !shadow-none',
    'relative isolate flex flex-wrap items-center gap-x-0 px-7 pb-4',
    '[&>*:first-child]:basis-full [&>*:first-child]:!h-9',
    // Respondendo a uma mensagem (#2113): a citação numa linha própria no topo da pílula,
    // no cinza dos elementos do app, com o texto na cor da conversa.
    '[&>[data-resposta-do-instagram]]:basis-full [&>[data-resposta-do-instagram]]:!rounded-xl [&>[data-resposta-do-instagram]]:!bg-[#F3F5F7] dark:[&>[data-resposta-do-instagram]]:!bg-[#262626]',
    '[&>[data-resposta-do-instagram]]:!text-[#0C1014] dark:[&>[data-resposta-do-instagram]]:!text-[#F5F5F5]',
    "before:content-[''] before:absolute before:-z-10 before:start-4 before:end-4 before:top-9 before:bottom-4 before:rounded-[22px] before:border before:border-[#DBDFE4] dark:before:border-[#363636] before:pointer-events-none",
    // Ordem do app: emoji, campo, microfone, fotos e vídeos; os demais ícones depois.
    '[&_.left-wrap]:!contents [&_.left-wrap>*]:order-5 [&_[data-emoji-da-resposta]]:!order-1',
    '[&_.left-wrap>button:has(.i-ph-microphone)]:!order-3 [&_.left-wrap>.file-uploads]:!order-4',
    '[&_.right-wrap]:order-6 [&_.right-wrap]:ps-1',
    ICONES,
    '[&_button:has(.i-lucide-maximize-2)]:!hidden',
    // Com texto no campo, só o emoji e o Enviar ficam na pílula (o painel marca data-com-texto).
    '[&_[data-com-texto]_.left-wrap>*:not([data-emoji-da-resposta])]:!hidden',
  ].join(' '),
  campo: [
    'order-2 flex-1 min-w-0 !mx-0 !px-2 !py-3 min-h-[46px] flex flex-wrap content-center items-center !bg-transparent',
    'text-[15px] text-[#0C1014] dark:text-[#F5F5F5]',
    // 22 px de linha + 12 px em cima e embaixo = os 46 px da pílula.
    '[&_.ProseMirror_p]:!leading-[22px] [&_.ProseMirror_p]:!my-0 [&_.popover-prosemirror-menu_.ProseMirror_p:last-child]:!mb-0',
    '[&_.resizable-editor-body]:!h-auto [&_.resizable-editor-body]:!min-h-[20px] [&_.resizable-editor-body]:!max-h-[40vh] [&>*]:w-full',
  ].join(' '),
  soResposta: '',
  // Mensagem privada: a mesma pílula, no amarelo da nota, para ninguém achar que o cliente vê.
  nota: 'before:!bg-[#FFF3C4] dark:before:!bg-[#3D3214] before:!border-[#E8D58A] dark:before:!border-[#5A4A1E]',
  painel: 'contents',
  // Gravando: a pílula inteira vira o gravador (sem emoji, ícones e Enviar de texto).
  gravando: '[&_.left-wrap>*]:!hidden [&_.right-wrap]:!hidden',
  // Enviar: pílula azul de 49 × 32 com o aviãozinho; com o campo vazio some e voltam
  // os ícones, como no app.
  enviar:
    '!h-8 !w-[49px] !p-0 !rounded-full !bg-[#4A5DF9] hover:enabled:!bg-[#3D4FE0] !text-white disabled:!hidden',
  enviarNota: '',
  iconeEnviar: 'i-ph-paper-plane-tilt-fill',

  microfone: '',
};

// Topo da conversa: fundo do app e o separador de 1 px.
export const TOPO =
  '!bg-white dark:!bg-[#0C1014] !border-b-[#DBDFE4] dark:!border-b-[#262626]';

// Gravador de áudio na pílula (#2079): os controles do gravador do WhatsApp (lixeira,
// tempo, onda, pausar/continuar e enviar) nas cores do Direct.
export const GRAVADOR_DO_INSTAGRAM = {
  barra: 'min-h-[46px]',
  botao:
    'grid place-content-center size-9 rounded-full flex-shrink-0 text-[#0C1014] dark:text-[#F5F5F5] hover:bg-[#0C1014]/5 dark:hover:bg-white/5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#4A5DF9]',
  tempo: 'text-[15px] leading-5 text-[#0C1014] dark:text-[#F5F5F5]',
  onda: '',
  pausa:
    'grid place-content-center size-9 rounded-full flex-shrink-0 text-[#4A5DF9] hover:bg-[#4A5DF9]/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#4A5DF9]',
  pausado: 'bg-[#4A5DF9]/10',
  enviar:
    'grid place-content-center h-8 w-[49px] rounded-full flex-shrink-0 bg-[#4A5DF9] hover:bg-[#3D4FE0] text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#4A5DF9]',
  iconeEnviar: 'i-ph-paper-plane-tilt-fill',
};
