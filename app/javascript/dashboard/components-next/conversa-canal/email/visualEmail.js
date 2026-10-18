// Visual da conversa de e-mail (#1786), inspirado no leitor do Gmail sem copiar a
// marca: folha clara, um cartão por e-mail separado por um fio, foto à esquerda,
// remetente em negrito, corpo alinhado ao nome. Só tokens do design system (n-*),
// que já trocam no tema escuro. As classes são literais (o Tailwind não lê
// interpolação) e entram por fora, sem editar o layout do Chatwoot.

// Na lista de mensagens: só as linhas que têm um cartão de e-mail mudam (avatar e
// margens do balão somem; o cartão desenha o dele). Notas privadas e avisos seguem
// como sempre.
export const LISTA_DO_EMAIL = [
  '!bg-n-surface-1',
  // O botão redondo do painel do contato flutua no canto: espaço para não cobrir o ⋮.
  'sm:!pe-16',
  '[&_.message-bubble-container:has([data-cartao-do-email])]:!mb-0',
  // Só a peça que tem o cartão ocupa a linha; o menu de contexto ao lado continua solto.
  '[&_.message-bubble-container>div:has([data-cartao-do-email])]:!block',
  '[&_.message-bubble-container>div:has([data-cartao-do-email])]:!w-full',
  '[&_.message-bubble-container>div:has([data-cartao-do-email])]:!flex-1',
  "[&_.message-bubble-container:has([data-cartao-do-email])_[class*='grid-area:avatar']]:!hidden",
  "[&_.message-bubble-container:has([data-cartao-do-email])_[class*='grid-area:bubble']]:!mx-0",
].join(' ');

// A caixa de resposta: o mesmo cartão do Chatwoot, alinhado com os e-mails, mais
// largo e com a sombra leve do leitor de e-mail.
export const RESPOSTA_DO_EMAIL = [
  '[&_.reply-box]:!mx-auto',
  '[&_.reply-box]:w-[calc(100%-1rem)]',
  '[&_.reply-box]:max-w-[960px]',
  '[&_.reply-box]:!rounded-2xl',
  '[&_.reply-box:not(.is-private)]:!bg-n-surface-1',
  '[&_.reply-box]:shadow-[0_1px_2px_rgba(0,0,0,0.12),0_1px_3px_1px_rgba(0,0,0,0.06)]',
].join(' ');

export const CARTAO = 'w-full max-w-[960px] mx-auto border-b border-n-weak';

export const SELO =
  'inline-flex items-center gap-1 h-5 px-1.5 rounded text-[11px] font-medium leading-none whitespace-nowrap';

export const COR_DO_SELO = {
  cliente: 'bg-n-teal-3 text-n-teal-11',
  copia: 'bg-n-amber-3 text-n-amber-11',
  agente: 'bg-n-iris-3 text-n-iris-11',
  aviso: 'bg-n-slate-3 text-n-slate-11',
  falha: 'bg-n-ruby-3 text-n-ruby-11',
};

// A nota privada, no amarelo de nota do painel.
export const PILULA_NOTA =
  'inline-flex items-center gap-2 h-10 px-5 rounded-full !border !border-solid !border-n-amber-7 bg-n-amber-2 text-sm font-medium text-n-amber-11 hover:bg-n-amber-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-amber-9';

// Botões em pílula do fim da conversa (Responder, Responder a todos, Encaminhar).
export const PILULA =
  'inline-flex items-center gap-2 h-10 px-5 rounded-full !border !border-solid !border-n-slate-7 bg-n-surface-1 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand';
