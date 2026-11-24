// #3100 — as abas da tela Fidelidade e os ids que ligam cada aba ao painel.
export const ABAS_DA_FIDELIDADE = ['cartao', 'cupons'];
export const PAINEL_DA_FIDELIDADE = 'painel-da-fidelidade';
export const idDaAbaDaFidelidade = aba => `aba-fidelidade-${aba}`;
export const abaValida = aba =>
  ABAS_DA_FIDELIDADE.includes(aba) ? aba : ABAS_DA_FIDELIDADE[0];
