import { PRESETS } from '../customRoles/permissionMatrix';
import { LOCK_REASONS } from 'dashboard/helper/peopleAccess';
import { cuidadosDaFuncao } from './fraseDaFuncao';
import { podeCurto } from './podeCurto';
import { motivoDaTrava } from './motivoDaTrava';

// Os cartões de função pronta da Escolha e do vazio (#2308, especificação 5.B1 e 7.6). Cada um mostra até 3
// capacidades curtas (podeCurto do fraseDaFuncao) do corte: o preset sem as chaves que quem monta não pode dar.
export const PRONTAS = [
  {
    chave: 'AGENT',
    icone: 'i-lucide-headset',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    chave: 'SDR',
    icone: 'i-lucide-handshake',
    tom: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    chave: 'SUPERVISOR',
    icone: 'i-lucide-eye',
    tom: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    chave: 'SALES_MANAGER',
    icone: 'i-lucide-chart-no-axes-combined',
    tom: 'bg-n-iris-3 text-n-iris-11',
  },
  {
    chave: 'MARKETING',
    icone: 'i-lucide-megaphone',
    tom: 'bg-n-iris-3 text-n-iris-11',
  },
  {
    chave: 'OPERATIONS',
    icone: 'i-lucide-wrench',
    tom: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    chave: 'READ_ONLY',
    icone: 'i-lucide-book-open',
    tom: 'bg-n-alpha-2 text-n-slate-11',
  },
  // Sem ver os custos, não há Financeiro: o cartão sai e fica só o cadeado.
  {
    chave: 'FINANCE',
    icone: 'i-lucide-wallet',
    tom: 'bg-n-teal-3 text-n-teal-11',
    essenciais: ['financial_view'],
  },
];
export const DESTAQUES = ['AGENT', 'SDR', 'SUPERVISOR'];

// A ordem em que as travas do cartão citam as chaves; as outras vêm depois, na ordem do preset.
const ORDEM_DAS_TRAVAS = [
  'crm_export',
  'crm_metas_manage',
  'sales_value_view',
  'insurance_view',
  'insurance_manage',
];
const posicao = chave =>
  ORDEM_DAS_TRAVAS.includes(chave)
    ? ORDEM_DAS_TRAVAS.indexOf(chave)
    : ORDEM_DAS_TRAVAS.length;

const agrupar = (preset, motivos) =>
  [LOCK_REASONS.MISSING, LOCK_REASONS.DELEGATION]
    .map(motivo => ({
      motivo,
      chaves: preset
        .filter(chave => motivos.get(chave) === motivo)
        .sort((a, b) => posicao(a) - posicao(b)),
    }))
    .filter(trava => trava.chaves.length);

export const cartaoPronto = (pronta, giver) => {
  const preset = PRESETS[pronta.chave]();
  const motivos = new Map(
    preset.map(chave => [chave, motivoDaTrava(giver, chave)])
  );
  const corte = preset.filter(chave => !motivos.get(chave));
  return {
    ...pronta,
    corte,
    capacidades: podeCurto(corte),
    selo: cuidadosDaFuncao(corte),
    travas: agrupar(preset, motivos),
    fora: (pronta.essenciais || []).some(chave => motivos.get(chave)),
  };
};

export const cartoesProntos = giver =>
  PRONTAS.map(pronta => cartaoPronto(pronta, giver));
