import { formatarDinheiro } from '../ficha/compras';
import {
  COMPRAS,
  DIAS_DAS_COMPRAS,
  FIDELIDADE,
  PERIODOS_DE_CHEGADA,
  TOTAIS_ACIMA,
} from './filtros';

// #3168 — os filtros de cima de "Mais filtros" (tirados de
// components/lista/GavetaDeFiltros.vue), cada um com o rótulo e as opções já
// escritos: a gaveta mostra e a frase de quem entra no grupo
// (lista/resumoDoGrupo.js) lê. Na aba Empresas (`deEmpresas`), só a cidade e
// quando chegou; sem ver valor de venda (`veValores`), sem o total comprado.
// `opcoes`: o que a fonte devolve (empresas, etiquetas, cidades...).
const LF = 'RELACIONAMENTOS.LISTA.FILTROS';
const FC = 'RELACIONAMENTOS_COMPRAS.FILTROS';

const comTodas = (t, lista = []) => [
  { value: '', label: t(`${LF}.TODAS`) },
  ...lista,
];

const cidade = (t, lista) => ({
  chave: 'cidade',
  rotulo: t(`${LF}.CIDADE`),
  opcoes: comTodas(t, lista),
});

const chegouEm = t => ({
  chave: 'chegouEm',
  rotulo: t(`${LF}.CHEGOU_EM`),
  opcoes: [
    { value: '', label: t(`${LF}.QUALQUER_DATA`) },
    { value: PERIODOS_DE_CHEGADA.ULTIMOS_7, label: t(`${LF}.ULTIMOS_7`) },
    { value: PERIODOS_DE_CHEGADA.ULTIMOS_30, label: t(`${LF}.ULTIMOS_30`) },
    { value: PERIODOS_DE_CHEGADA.ULTIMOS_90, label: t(`${LF}.ULTIMOS_90`) },
  ],
});

const qualquer = t => ({ value: '', label: t(`${FC}.QUALQUER`) });

const compras = t => ({
  chave: 'compras',
  rotulo: t(`${FC}.COMPRAS`),
  opcoes: [
    qualquer(t),
    { value: COMPRAS.JA_COMPROU, label: t(`${FC}.JA_COMPROU`) },
    { value: COMPRAS.NUNCA, label: t(`${FC}.NUNCA_COMPROU`) },
    ...Object.entries(DIAS_DAS_COMPRAS).map(([value, dias]) => ({
      value,
      label: t(`${FC}.ULTIMOS`, { count: dias }),
    })),
  ],
});

// O total vai em faixas prontas: o leigo escolhe, não digita valor.
const totalAcima = (t, idioma) => ({
  chave: 'totalAcima',
  rotulo: t(`${FC}.TOTAL`),
  opcoes: [
    qualquer(t),
    ...TOTAIS_ACIMA.map(valor => ({
      value: String(valor),
      label: t(`${FC}.ACIMA`, {
        valor: formatarDinheiro(valor, 'BRL', idioma),
      }),
    })),
  ],
});

// #3100 — o cartão fidelidade (só em Pessoas, com cartão na conta): perto do
// prêmio ou cartão completo.
const FF = 'FIDELIDADE.FILTRO';
const fidelidade = t => ({
  chave: 'fidelidade',
  rotulo: t(`${FF}.ROTULO`),
  opcoes: [
    { value: '', label: t(`${FF}.QUALQUER`) },
    { value: FIDELIDADE.PERTO, label: t(`${FF}.PERTO`) },
    { value: FIDELIDADE.COMPLETO, label: t(`${FF}.COMPLETO`) },
  ],
});

export const camposDoTopo = ({
  t,
  idioma,
  opcoes = {},
  deEmpresas = false,
  veValores = false,
  comFidelidade = false,
}) => {
  if (deEmpresas) return [cidade(t, opcoes.cidades_das_empresas), chegouEm(t)];
  return [
    {
      chave: 'empresa',
      rotulo: t(`${LF}.EMPRESA`),
      opcoes: comTodas(t, opcoes.empresas),
    },
    {
      chave: 'etiqueta',
      rotulo: t(`${LF}.ETIQUETA`),
      opcoes: comTodas(t, opcoes.etiquetas),
    },
    cidade(t, opcoes.cidades),
    chegouEm(t),
    compras(t),
    ...(veValores ? [totalAcima(t, idioma)] : []),
    ...(comFidelidade ? [fidelidade(t)] : []),
  ];
};
