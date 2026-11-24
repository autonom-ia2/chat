// #3100 — cada movimento do cartão fidelidade na ficha vira uma frase curta.
// O servidor manda `quantos` com sinal: ganho positivo, saída negativa.
export const TIPOS_DE_MOVIMENTO = [
  'compra',
  'presente',
  'ajuste',
  'premio',
  'venceu',
  'estorno',
];

// A chave da frase (FIDELIDADE.FICHA.MOV.<chave>) e os valores dela.
export const fraseDoMovimento = (movimento, { unidade, dinheiro, tipo }) => {
  const quantos = unidade(Math.abs(movimento.quantos || 0), tipo);
  const base = { quantos, quem: movimento.quem || '' };
  switch (movimento.tipo) {
    case 'compra':
      return movimento.valor
        ? {
            chave: 'compra',
            valores: {
              ...base,
              valor: dinheiro(movimento.valor.total, movimento.valor.moeda),
            },
          }
        : { chave: 'compra_sem_valor', valores: base };
    case 'presente':
      return movimento.motivo
        ? { chave: 'presente', valores: { ...base, motivo: movimento.motivo } }
        : { chave: 'presente_sem_motivo', valores: base };
    case 'ajuste':
      return {
        chave: movimento.quantos < 0 ? 'ajuste_menos' : 'ajuste_mais',
        valores: base,
      };
    case 'premio':
      return {
        chave: movimento.quem ? 'premio' : 'premio_sem_quem',
        valores: base,
      };
    case 'venceu':
      return { chave: 'venceu', valores: base };
    case 'estorno':
      return { chave: 'estorno', valores: base };
    default:
      return { chave: 'outro', valores: base };
  }
};

export const sinalDoMovimento = quantos =>
  quantos > 0 ? `+${quantos}` : `−${Math.abs(quantos || 0)}`;
