// O gatilho recorrente (#2635 G7, G39): o dia da semana só no semanal, o do mês
// só no mensal e a data só no "uma vez". Escolhida a frequência, o que ela pede
// é obrigatório: o catálogo não marca (o esquema pede só naquela frequência).
const DIA_DA_FREQUENCIA = {
  dia_da_semana: 'semanal',
  dia_do_mes: 'mensal',
  data: 'uma_vez',
};

const vazio = valor => valor === undefined || valor === null || valor === '';

export const mostraNaFrequencia = (nome, frequencia) =>
  !DIA_DA_FREQUENCIA[nome] || DIA_DA_FREQUENCIA[nome] === frequencia;

export const faltaDaFrequencia = gatilho =>
  Object.entries(DIA_DA_FREQUENCIA).some(
    ([nome, frequencia]) =>
      gatilho?.frequencia === frequencia && vazio(gatilho[nome])
  );
