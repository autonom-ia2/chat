// Classes do menu novo (#1617) nos dois visuais: o padrão (claro e escuro pelos tokens n-*) e a barra com cor de
// marca (useBrandedSidebar, fundo navy no claro). Na barra de marca o Sidebar.vue repinta algumas classes n-*
// com `:deep(...)`; aqui elas não são usadas nesse visual, para o ativo não ficar ilegível.
const PADRAO = {
  texto: 'text-n-slate-12',
  textoFilho: 'text-n-slate-11',
  icone: 'text-n-slate-11',
  passar: 'hover:bg-n-alpha-2 hover:text-n-slate-12',
  ativo: 'bg-n-blue-3 text-n-blue-11 font-semibold',
  iconeAtivo: 'text-n-blue-11',
  iconePai: 'text-n-blue-11',
  paiAtivo: 'font-semibold text-n-slate-12',
  paiFechadoAtivo:
    'bg-n-blue-3/70 font-semibold text-n-blue-11 hover:bg-n-blue-3',
  tituloGrupo: 'text-n-slate-11',
  linha: 'border-n-weak',
  foco: 'focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand',
  contador: 'bg-n-slate-4 text-n-slate-12 dark:bg-n-slate-5',
  contadorAtivo: 'bg-n-blue-9 text-white',
  pendencia: 'bg-n-amber-3 text-n-amber-11 ring-1 ring-inset ring-n-amber-6',
  trilho: 'bg-n-slate-4',
  progresso: 'bg-n-brand',
  esmaecidoCima: 'bg-gradient-to-b from-n-background',
  esmaecidoBaixo: 'bg-gradient-to-t from-n-background',
  seta: 'text-n-slate-11 drop-shadow-[0_2px_6px_rgba(0,0,0,0.25)]',
  setaPassar: 'group-hover:text-n-slate-12 group-hover:scale-110',
};

const MARCA = {
  texto: 'text-white/90',
  textoFilho: 'text-white/75',
  icone: 'text-white/70',
  passar: 'hover:bg-white/10 hover:text-white',
  ativo:
    'bg-white text-[var(--sidebar-background-color)] font-semibold shadow-sm',
  iconeAtivo: 'text-[var(--sidebar-background-color)]',
  iconePai: 'text-white',
  paiAtivo: 'font-semibold text-white',
  paiFechadoAtivo: 'bg-white/15 font-semibold text-white hover:bg-white/20',
  tituloGrupo: 'text-white/60',
  linha: 'border-white/15',
  foco: 'focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-white',
  contador: 'bg-white/15 text-white',
  contadorAtivo: 'bg-[var(--sidebar-background-color)] text-white',
  pendencia: 'bg-n-amber-9 text-n-amber-12 ring-0',
  trilho: 'bg-white/20',
  progresso: 'bg-white/80',
  esmaecidoCima: 'bg-gradient-to-b from-[var(--sidebar-background-color)]',
  esmaecidoBaixo: 'bg-gradient-to-t from-[var(--sidebar-background-color)]',
  seta: 'text-white/70 drop-shadow-[0_2px_6px_rgba(0,0,0,0.45)]',
  setaPassar: 'group-hover:text-white group-hover:scale-110',
};

export const temaDoMenu = comMarca => (comMarca ? MARCA : PADRAO);
