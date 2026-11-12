// #2889 — os 20 modelos prontos de Automação, um por exemplo do épico #2414. O texto (título e frase) mora no i18n,
// em AUTOMACAO_MODELOS.ITENS.<id>, e o pacote do segmento da conta (#1550) troca o texto: a corretora e os planos de
// saúde têm versão própria. Aqui ficam só o grupo, o ícone e se o modelo usa IA, e o que muda por camada.
//
// Ícone por grupo e tom por grupo, como na vitrine de ferramentas (#2858); o modelo pode ter ícone próprio. As classes
// ficam escritas por inteiro no componente para o Tailwind encontrá-las.
export const GRUPOS = [
  { id: 'VENDAS', icone: 'i-lucide-trending-up', tom: 'azul' },
  { id: 'ATENDIMENTO', icone: 'i-lucide-headset', tom: 'ambar' },
  { id: 'POS_VENDA', icone: 'i-lucide-heart-handshake', tom: 'teal' },
  { id: 'RELACIONAMENTO', icone: 'i-lucide-repeat', tom: 'rosa' },
  { id: 'EQUIPE', icone: 'i-lucide-users-round', tom: 'violeta' },
];

const CORRETORA = 'seguros/corretora';
const SAUDE = 'seguros/saude_beneficios';

// `camadas`: o que muda no segmento (ícone, grupo ou IA), da camada mais geral para a mais específica.
export const MODELOS = [
  {
    id: 'M01',
    grupo: 'RELACIONAMENTO',
    icone: 'i-lucide-calendar-clock',
    ia: false,
    camadas: { [CORRETORA]: { icone: 'i-lucide-shield-check' } },
  },
  {
    id: 'M02',
    grupo: 'VENDAS',
    icone: 'i-lucide-megaphone',
    ia: false,
  },
  {
    id: 'M03',
    grupo: 'POS_VENDA',
    icone: 'i-lucide-heart-pulse',
    ia: true,
    camadas: {
      [CORRETORA]: { icone: 'i-lucide-file-badge', ia: false },
      [SAUDE]: { icone: 'i-lucide-id-card', ia: false },
    },
  },
  {
    id: 'M04',
    grupo: 'RELACIONAMENTO',
    icone: 'i-lucide-user-round-x',
    ia: false,
    camadas: {
      [CORRETORA]: { icone: 'i-lucide-receipt', grupo: 'ATENDIMENTO' },
      [SAUDE]: { icone: 'i-lucide-receipt', grupo: 'ATENDIMENTO' },
    },
  },
  {
    id: 'M05',
    grupo: 'POS_VENDA',
    icone: 'i-lucide-calendar-check',
    ia: true,
    camadas: {
      [CORRETORA]: { icone: 'i-lucide-car', ia: false },
      [SAUDE]: { icone: 'i-lucide-hourglass', ia: false },
    },
  },
  {
    id: 'M06',
    grupo: 'RELACIONAMENTO',
    icone: 'i-lucide-cake',
    ia: true,
  },
  {
    id: 'M07',
    grupo: 'VENDAS',
    icone: 'i-lucide-badge-percent',
    ia: false,
  },
  {
    id: 'M08',
    grupo: 'ATENDIMENTO',
    icone: 'i-lucide-list-checks',
    ia: true,
  },
  {
    id: 'M09',
    grupo: 'VENDAS',
    icone: 'i-lucide-radar',
    ia: true,
  },
  {
    id: 'M10',
    grupo: 'ATENDIMENTO',
    icone: 'i-lucide-siren',
    ia: true,
  },
  {
    id: 'M11',
    grupo: 'VENDAS',
    icone: 'i-lucide-gift',
    ia: true,
  },
  {
    id: 'M12',
    grupo: 'VENDAS',
    icone: 'i-lucide-map-pin-check',
    ia: true,
    camadas: {
      [CORRETORA]: { icone: 'i-lucide-file-text' },
      [SAUDE]: { icone: 'i-lucide-file-text' },
    },
  },
  {
    id: 'M13',
    grupo: 'POS_VENDA',
    icone: 'i-lucide-party-popper',
    ia: false,
    camadas: {
      [CORRETORA]: { icone: 'i-lucide-clipboard-check' },
      [SAUDE]: { icone: 'i-lucide-clipboard-check' },
    },
  },
  {
    id: 'M14',
    grupo: 'ATENDIMENTO',
    icone: 'i-lucide-file-check-2',
    ia: true,
  },
  {
    id: 'M15',
    grupo: 'VENDAS',
    icone: 'i-lucide-crown',
    ia: false,
  },
  {
    id: 'M16',
    grupo: 'RELACIONAMENTO',
    icone: 'i-lucide-undo-2',
    ia: false,
  },
  {
    id: 'M17',
    grupo: 'EQUIPE',
    icone: 'i-lucide-plane',
    ia: true,
  },
  {
    id: 'M18',
    grupo: 'EQUIPE',
    icone: 'i-lucide-user-search',
    ia: true,
  },
  {
    id: 'M19',
    grupo: 'ATENDIMENTO',
    icone: 'i-lucide-phone-off',
    ia: false,
  },
  {
    id: 'M20',
    grupo: 'POS_VENDA',
    icone: 'i-lucide-send',
    ia: true,
  },
];

// Os mais usados, na ordem em que aparecem. A camada mais específica que tiver a lista vence.
const DESTAQUE = {
  geral: ['M02', 'M10', 'M14', 'M03', 'M06', 'M20'],
  [CORRETORA]: ['M01', 'M04', 'M10', 'M14', 'M12', 'M16'],
  [SAUDE]: ['M01', 'M03', 'M05', 'M08', 'M10', 'M14'],
};

// O modelo como a conta o vê: o que a camada mais específica muda vence.
export const modeloNaConta = (modelo, camadas = []) =>
  camadas.reduce(
    (atual, camada) => ({ ...atual, ...(modelo.camadas?.[camada] || {}) }),
    modelo
  );

export const modelosDaConta = (camadas = []) =>
  MODELOS.map(modelo => modeloNaConta(modelo, camadas));

// A camada do segmento que tem destaque próprio, ou null (vale o geral).
export const camadaDoDestaque = (camadas = []) =>
  [...camadas].reverse().find(nome => DESTAQUE[nome]) || null;

export const emDestaque = (modelos, camadas = []) => {
  const ids = DESTAQUE[camadaDoDestaque(camadas)] || DESTAQUE.geral;
  return ids
    .map(id => modelos.find(modelo => modelo.id === id))
    .filter(Boolean);
};

export const tomDoGrupo = grupo =>
  GRUPOS.find(item => item.id === grupo)?.tom || 'cinza';
