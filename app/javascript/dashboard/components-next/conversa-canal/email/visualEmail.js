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
  // A barra de responder fica presa no rodapé: sem recuo embaixo, nada vaza por baixo.
  '!pb-0',
  // A faixa de 64 px que o Chatwoot reserva no começo da lista ("carregando
  // anteriores") vira só o que precisa: o assunto fica logo abaixo da barra de cima.
  '[&>li:has(+[data-topo-do-email])]:!min-h-0',
  // Ela também empurra conversa curta para baixo (margem automática): no e-mail o
  // assunto fica no alto e só a barra de responder desce (mt-auto no AcoesDoEmail).
  '[&>li:has(+[data-topo-do-email])]:!mt-0',
  '[&_.message-bubble-container:has([data-cartao-do-email])]:!mb-0',
  // Só a peça que tem o cartão ocupa a linha; o menu de contexto ao lado continua solto.
  '[&_.message-bubble-container>div:has([data-cartao-do-email])]:!block',
  '[&_.message-bubble-container>div:has([data-cartao-do-email])]:!w-full',
  '[&_.message-bubble-container>div:has([data-cartao-do-email])]:!flex-1',
  "[&_.message-bubble-container:has([data-cartao-do-email])_[class*='grid-area:avatar']]:!hidden",
  "[&_.message-bubble-container:has([data-cartao-do-email])_[class*='grid-area:bubble']]:!mx-0",
].join(' ');

// Os botões redondos da barra de baixo do e-mail (#1786), no padrão da caixa do
// WhatsApp: sem fundo, ícone de 22 px, círculo ao passar o mouse, contorno só no
// teclado e azul quando ligado. Valem para a `.left-wrap` da resposta e para a da
// gaveta "Escrever" (#1809); o tamanho do botão fica com cada uma.
export const BOTOES_DA_BARRA = [
  '[&_.left-wrap]:!gap-0.5',
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre])]:!p-0',
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre])]:!rounded-full',
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre])]:!bg-transparent',
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre])]:!text-n-slate-12',
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre]):hover]:!bg-n-alpha-2',
  "[&_.left-wrap_button:not([role=menuitem]):not([data-livre])_span[class*='i-']]:!size-[22px]",
  // Contorno só no teclado (o clique não deixa anel), como na caixa do WhatsApp.
  '[&_.left-wrap_button:focus]:!outline-none',
  '[&_.left-wrap_button:focus-visible]:!outline',
  '[&_.left-wrap_button:focus-visible]:!outline-2',
  '[&_.left-wrap_button:focus-visible]:!outline-offset-1',
  '[&_.left-wrap_button:focus-visible]:!outline-n-brand',
  // Botão que liga e desliga (assinatura, formatação) mostra quando está ligado. O
  // seletor repete os :not() de cima: com menos peso, o fundo transparente ganhava.
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre])[data-ligado]]:!bg-n-blue-3',
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre])[data-ligado]]:!text-n-blue-11',
].join(' ');

// A caixa de resposta do e-mail (#1786, desenho aprovado em 18/10): o cartão do
// Chatwoot alinhado aos e-mails, com os botões de baixo no padrão da caixa do WhatsApp
// (redondos de 40 px, ícone maior, círculo ao passar o mouse) e o Enviar em pílula.
export const RESPOSTA_DO_EMAIL = [
  '[&_.reply-box]:!mx-auto',
  '[&_.reply-box]:w-[calc(100%-1rem)]',
  '[&_.reply-box]:max-w-[960px]',
  '[&_.reply-box]:!rounded-2xl',
  '[&_.reply-box:not(.is-private)]:!bg-n-surface-1',
  '[&_.reply-box]:shadow-[0_1px_2px_rgba(0,0,0,0.12),0_1px_3px_1px_rgba(0,0,0,0.06)]',
  // Caixa alta (modelo, histórico aberto) rola por dentro, sem levar a conversa de
  // trás junto, e a barra de baixo (Enviar) fica sempre à vista.
  '[&_.reply-box]:max-h-[calc(100dvh-5rem)]',
  '[&_.reply-box]:overflow-y-auto',
  '[&_.reply-box]:overscroll-contain',
  '[&_.reply-box_div:has(>.left-wrap)]:sticky',
  '[&_.reply-box_div:has(>.left-wrap)]:bottom-0',
  '[&_.reply-box_div:has(>.left-wrap)]:z-10',
  // Rodapé fixo de verdade: fundo sólido (o que rola por baixo não aparece através)
  // e um fio em cima, na cor da caixa (resposta ou nota amarela).
  '[&_.reply-box:not(.is-private)_div:has(>.left-wrap)]:!bg-n-surface-1',
  '[&_.reply-box.is-private_div:has(>.left-wrap)]:!bg-n-solid-amber',
  '[&_.reply-box_div:has(>.left-wrap)]:border-t',
  '[&_.reply-box_div:has(>.left-wrap)]:border-n-weak',
  '[&_.reply-box_div:has(>.left-wrap)]:rounded-b-2xl',
  // Botões da barra de baixo: o desenho comum e o tamanho desta caixa.
  BOTOES_DA_BARRA,
  '[&_.left-wrap_button:not([role=menuitem]):not([data-livre])]:!size-10',
  // No celular o fio que separa os grupos sobra.
  'max-sm:[&_[data-separador-da-barra]]:!hidden',
  // No celular o botão redondo do painel do contato flutua sobre o canto da caixa.
  'max-sm:[&_[data-cabeca-da-resposta]]:!pe-12',
  '[&_.right-wrap]:!items-center',
  '[&_.right-wrap]:!gap-1',
  // No celular a barra de baixo quebra em duas linhas: ferramentas em cima, Enviar
  // inteiro embaixo, à direita.
  'max-sm:[&_div:has(>.left-wrap)]:!flex-wrap',
  'max-sm:[&_div:has(>.left-wrap)]:!gap-y-2',
  'max-sm:[&_.left-wrap]:!flex-wrap',
  'max-sm:[&_.right-wrap]:!w-full',
  'max-sm:[&_.right-wrap]:!justify-end',
  // Enviar: pílula de 40 px com o destino escrito ("Enviar para Marina").
  '[&_.right-wrap_button[type=submit]]:!h-10',
  '[&_.right-wrap_button[type=submit]]:!px-5',
  '[&_.right-wrap_button[type=submit]]:!rounded-full',
  '[&_.right-wrap_button[type=submit]]:!text-sm',
  '[&_.right-wrap_button[type=submit]]:!font-medium',
].join(' ');

// Aumentar: a resposta ocupa o lugar da conversa (a lista some), com o texto alto.
export const RESPOSTA_EXPANDIDA = [
  '!flex-1',
  '[&_.cursor-row-resize]:!hidden',
  // Altura do texto = tela menos topo do painel, cabeçalho da caixa e barra de baixo.
  '[&_.resizable-editor-body]:!h-[calc(100vh-30rem)]',
  '[&_.resizable-editor-body]:!min-h-[8rem]',
  // O botão redondo do painel do contato flutua no canto direito.
  'sm:!pe-16',
  '[&_.resizable-editor-body]:!max-h-none',
].join(' ');

// Janela: a resposta flutua no canto, e a conversa fica à vista e rolável por trás.
export const RESPOSTA_EM_JANELA = [
  '!fixed',
  '!z-40',
  '!bottom-4',
  '!end-4',
  '!w-[min(720px,calc(100vw-2rem))]',
  '!bg-transparent',
  '[&_.reply-box]:!w-full',
  '[&_.reply-box]:!shadow-[0_8px_30px_rgba(0,0,0,0.25)]',
  '[&_.cursor-row-resize]:!hidden',
  '[&_.resizable-editor-body]:!h-[40vh]',
  '[&_.resizable-editor-body]:!max-h-none',
].join(' ');

// Botões da régua do Chatwoot que o e-mail novo não usa (prop `hiddenMenuOptions` do
// editor). Imagem no texto: o "+" da barra de baixo já anexa (#1786/#1809). O ✨ fica: ele
// usa a IA do cliente (#1872), e o editor só o mostra onde o copiloto da Autonom.ia está
// disponível (prop `copilotAvailable`), nunca pelo Captain.
export const FORA_DA_REGUA = ['imageUpload'];

// "Aa" desligado: nenhuma régua. O Chatwoot abre a barra flutuante ao selecionar texto,
// presa logo abaixo da seleção, e ela tapava a linha de baixo (#1809). No e-mail a
// formatação mora no "Aa", como no Gmail; os atalhos (Ctrl+B, Ctrl+I) seguem valendo.
export const REGUA_SO_NO_AA =
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!hidden';

// "Aa": a barra de formatação do editor, que o Chatwoot só mostra sobre o texto
// selecionado, vira uma régua fixa acima do texto, no padrão dos botões da caixa: em
// grupos (✨ | negrito, itálico, código | link | listas | desfazer, refazer), com fio
// entre eles, botão ativo em azul e desligado apagado. Presa no topo da área que rola,
// com fundo sólido e borda, na resposta e na gaveta "Escrever". Os fios dependem de o ✨
// estar na régua ou não (o menu do e-mail sem FORA_DA_REGUA, com e sem ele; o teste confere).
export const FORMATACAO_FIXA = [
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!flex',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!flex-wrap',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!items-center',
  // Fixa no topo da área que rola (#1809): o texto passa por baixo, a régua fica.
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!sticky',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!top-0',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!z-20',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!w-full',
  // Presa no topo, um aro da cor da caixa esconde o texto que passa por trás dos cantos.
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!outline',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!outline-[6px]',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!outline-n-surface-1',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!bg-n-surface-1',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!border',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!border-solid',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!border-n-weak',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!rounded-2xl',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!shadow-[0_1px_2px_rgba(0,0,0,0.06)]',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!gap-0.5',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!px-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!py-1.5',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar]:!mb-3',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem]:!size-9',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem]:!grid',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem]:!place-content-center',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem]:!rounded-full',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem]:!text-n-slate-11',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem:hover]:!bg-n-alpha-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem:hover]:!text-n-slate-12',
  '[&_.popover-prosemirror-menu_.ProseMirror-menuitem_svg]:!size-[18px]',
  // Sem o ✨ (copiloto indisponível): fios antes do 4º, 5º e 7º botão.
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:!ms-3',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:relative',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:before:absolute',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:before:-start-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:before:top-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:before:bottom-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:before:w-px',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:before:bg-n-weak',
  "[&_.popover-prosemirror-menu_.ProseMirror-menubar:not(:has(.ProseMirror-copilot))_.ProseMirror-menuitem:is(:nth-child(4),:nth-child(5),:nth-child(7))]:before:content-['']",
  // Com o ✨ na frente (#1872): um fio depois dele, e os outros um botão adiante.
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:!ms-3',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:relative',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:before:absolute',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:before:-start-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:before:top-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:before:bottom-2',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:before:w-px',
  '[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:before:bg-n-weak',
  "[&_.popover-prosemirror-menu_.ProseMirror-menubar:has(.ProseMirror-copilot)_.ProseMirror-menuitem:is(:nth-child(2),:nth-child(5),:nth-child(6),:nth-child(8))]:before:content-['']",
  '[&_.popover-prosemirror-menu_.ProseMirror-menu-active]:!bg-n-blue-3',
  '[&_.popover-prosemirror-menu_.ProseMirror-menu-active]:!text-n-blue-11',
  '[&_.popover-prosemirror-menu_.ProseMirror-menu-disabled]:!opacity-40',
  // Botão que não se aplica ali (as listas, com o cursor numa lista) o ProseMirror
  // esconde com `display: none` no ícone, e a régua ficava com um buraco (#1809).
  // Na régua fixa ele fica no lugar, apagado e sem clique, como os desligados.
  // Depende do `display: none` que o ProseMirror escreve no ícone: se o Chatwoot mudar
  // isso, o buraco volta. A causa raiz é o menu do editor não ter estado "desligado"
  // para esses itens; o conserto definitivo é o Editor.vue marcar o item como desligado.
  "[&_.popover-prosemirror-menu_.ProseMirror-menuitem>.ProseMirror-icon[style*='none']]:!flex",
  "[&_.popover-prosemirror-menu_.ProseMirror-menuitem>.ProseMirror-icon[style*='none']]:!opacity-40",
  "[&_.popover-prosemirror-menu_.ProseMirror-menuitem>.ProseMirror-icon[style*='none']]:!pointer-events-none",
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
