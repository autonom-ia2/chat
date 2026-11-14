// #2881 — os agentes prontos por ramo de seguro, na fileira "Prontos para o seu ramo" da página "Criar agente". A
// chave é a do servidor (config/agentes_por_pacote/seguros/modelos/<chave>.yml): quem diz quais a conta pode usar é
// ele (GET autonomia/modelos_de_ramo), e a chave vai na query `ramo` da rota do Construtor. Aqui fica só o que é da
// tela: o ícone, a cor e a hora da conversa de exemplo. Os textos do cartão ficam em AGENTS.JORNADA.RAMOS.ITENS.<I18N>.
// O modelo de ramo é uma camada acima do agente de vendas (`sdr`): não existe tipo novo de agente.
export const TIPO_DO_MODELO_DE_RAMO = 'sdr';

export const MODELOS_DE_RAMO = [
  {
    chave: 'seguro_auto',
    i18n: 'AUTO',
    icone: 'i-lucide-car',
    tom: 'ambar',
    horario: '09:41',
  },
  {
    chave: 'seguro_garantia',
    i18n: 'GARANTIA',
    icone: 'i-lucide-file-check-2',
    tom: 'azul',
    horario: '11:08',
  },
  {
    chave: 'transporte_carga',
    i18n: 'CARGA',
    icone: 'i-lucide-truck',
    tom: 'teal',
    horario: '15:22',
  },
  {
    chave: 'seguro_condominio',
    i18n: 'CONDOMINIO',
    icone: 'i-lucide-building-2',
    tom: 'iris',
    horario: '10:17',
  },
  {
    chave: 'seguro_residencial',
    i18n: 'RESIDENCIAL',
    icone: 'i-lucide-house',
    tom: 'teal',
    horario: '08:52',
  },
  {
    chave: 'vida_individual',
    i18n: 'VIDA',
    icone: 'i-lucide-heart-handshake',
    tom: 'iris',
    horario: '14:05',
  },
  {
    chave: 'planos_de_saude',
    i18n: 'SAUDE',
    icone: 'i-lucide-heart-pulse',
    tom: 'azul',
    horario: '10:31',
  },
  {
    chave: 'seguro_empresarial',
    i18n: 'EMPRESARIAL',
    icone: 'i-lucide-store',
    tom: 'ambar',
    horario: '09:14',
  },
  {
    chave: 'seguro_aluguel',
    i18n: 'ALUGUEL',
    icone: 'i-lucide-key-round',
    tom: 'teal',
    horario: '16:40',
  },
  {
    chave: 'seguro_viagem',
    i18n: 'VIAGEM',
    icone: 'i-lucide-plane',
    tom: 'azul',
    horario: '19:22',
  },
  {
    chave: 'seguro_celular',
    i18n: 'CELULAR',
    icone: 'i-lucide-smartphone',
    tom: 'iris',
    horario: '12:48',
  },
  {
    chave: 'seguro_bike',
    i18n: 'BIKE',
    icone: 'i-lucide-bike',
    tom: 'teal',
    horario: '07:35',
  },
  {
    chave: 'vida_em_grupo',
    i18n: 'VIDA_GRUPO',
    icone: 'i-lucide-users',
    tom: 'ambar',
    horario: '11:26',
  },
  {
    chave: 'acidentes_pessoais',
    i18n: 'ACIDENTES',
    icone: 'i-lucide-bandage',
    tom: 'azul',
    horario: '13:17',
  },
  {
    chave: 'rc_profissional',
    i18n: 'RC_PROFISSIONAL',
    icone: 'i-lucide-scale',
    tom: 'iris',
    horario: '17:03',
  },
  {
    chave: 'rc_geral',
    i18n: 'RC_GERAL',
    icone: 'i-lucide-shield-check',
    tom: 'ambar',
    horario: '15:49',
  },
  {
    chave: 'seguro_cibernetico',
    i18n: 'CIBERNETICO',
    icone: 'i-lucide-lock-keyhole',
    tom: 'azul',
    horario: '10:58',
  },
  {
    chave: 'riscos_de_engenharia',
    i18n: 'ENGENHARIA',
    icone: 'i-lucide-hard-hat',
    tom: 'ambar',
    horario: '08:16',
  },
  {
    chave: 'seguro_rural',
    i18n: 'RURAL',
    icone: 'i-lucide-tractor',
    tom: 'teal',
    horario: '06:48',
  },
  {
    chave: 'aviacao',
    i18n: 'AVIACAO',
    icone: 'i-lucide-plane-takeoff',
    tom: 'iris',
    horario: '18:10',
  },
];

export const TOM_DO_RAMO = {
  azul: 'bg-n-blue-3 text-n-blue-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  ambar: 'bg-n-amber-3 text-n-amber-11',
  iris: 'bg-n-iris-3 text-n-iris-11',
};

export const modeloDeRamo = chave =>
  MODELOS_DE_RAMO.find(modelo => modelo.chave === chave) || null;

// `?ramo=<chave>`: a escolha de um cartão da fileira. Chave que a tela não conhece não é escolha (null).
export const ramoDaQuery = (query = {}) =>
  modeloDeRamo(query.ramo)?.chave || null;

// Limites do servidor (ModelosDeRamo::ITENS_MAX e ITEM_MAX; FerramentasProntas::Incluir::MAX_USAR_QUANDO). No modelo em
// blocos (#3020) o limite de 20 vale para as perguntas que o dono escreve; as do modelo têm teto próprio no servidor.
export const MAXIMO_DE_ITENS = 20;
export const MAXIMO_DE_LETRAS_DO_ITEM = 300;
export const MAXIMO_DE_LETRAS_DO_QUANDO = 500;
