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
];

export const TOM_DO_RAMO = {
  azul: 'bg-n-blue-3 text-n-blue-11',
  teal: 'bg-n-teal-3 text-n-teal-11',
  ambar: 'bg-n-amber-3 text-n-amber-11',
};

export const modeloDeRamo = chave =>
  MODELOS_DE_RAMO.find(modelo => modelo.chave === chave) || null;

// `?ramo=<chave>`: a escolha de um cartão da fileira. Chave que a tela não conhece não é escolha (null).
export const ramoDaQuery = (query = {}) =>
  modeloDeRamo(query.ramo)?.chave || null;

// Limites do servidor (ModelosDeRamo::ITENS_MAX e ITEM_MAX; FerramentasProntas::Incluir::MAX_USAR_QUANDO).
export const MAXIMO_DE_ITENS = 20;
export const MAXIMO_DE_LETRAS_DO_ITEM = 300;
export const MAXIMO_DE_LETRAS_DO_QUANDO = 500;
