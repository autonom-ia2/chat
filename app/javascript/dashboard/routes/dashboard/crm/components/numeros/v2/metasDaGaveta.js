// #1991 — regras da gaveta "Metas do mês", em funções puras (testadas sem
// montar a tela). Os campos guardam texto, como o Input entrega; vazio = sem meta.

export const paraCampo = valor =>
  valor === null || valor === undefined ? '' : String(valor);

// Só algarismos: vazio é "sem meta" (null); ponto, vírgula, sinal ou letra é
// inválido (NaN). "8.000" não pode virar 8 em silêncio.
const ALGARISMOS = '0123456789';
export const numero = texto => {
  const valor = String(texto);
  if (valor === '') return null;
  const soAlgarismos = [...valor].every(c => ALGARISMOS.includes(c));
  return soAlgarismos ? Number(valor) : NaN;
};

export const invalido = texto => Number.isNaN(numero(texto));

// Guarda a meta do funil como chegou: ela só volta ao servidor se mudar (a do
// painel pode ter centavos, que a gaveta não mostra).
export const doServidor = funis =>
  funis.map(funil => ({
    ...funil,
    metaFunil: paraCampo(funil.metaFunil),
    metaFunilInicial: paraCampo(funil.metaFunil),
    pessoas: funil.pessoas.map(p => ({ ...p, meta: paraCampo(p.meta) })),
  }));

export const paraOServidor = funis =>
  funis.map(f => ({
    id: f.id,
    ...(f.metaFunil === f.metaFunilInicial
      ? {}
      : { metaFunil: numero(f.metaFunil) }),
    pessoas: f.pessoas.map(p => ({ id: p.id, meta: numero(p.meta) })),
  }));

// "Repetir o mês anterior": quem não tinha meta no mês anterior fica como está.
export const repetirAnterior = funil => ({
  ...funil,
  pessoas: funil.pessoas.map(p =>
    p.anterior === null || p.anterior === undefined
      ? p
      : { ...p, meta: paraCampo(p.anterior) }
  ),
});

// Divide a meta do funil em partes inteiras, de 100 em 100 quando cada parte
// passa de 100; a sobra vai para a primeira pessoa, para a soma bater. Sem meta
// do funil, nada muda.
export const PASSO_DA_DIVISAO = 100;
export const dividirIgualmente = funil => {
  const quantas = funil.pessoas.length;
  const total = numero(funil.metaFunil);
  if (!quantas || !total) return funil;
  const bruta = Math.floor(total / quantas);
  const passo = bruta >= PASSO_DA_DIVISAO ? PASSO_DA_DIVISAO : 1;
  const parte = Math.floor(bruta / passo) * passo;
  const sobra = total - parte * quantas;
  return {
    ...funil,
    pessoas: funil.pessoas.map((p, i) => ({
      ...p,
      meta: String(i === 0 ? parte + sobra : parte),
    })),
  };
};

// A soma das pessoas com meta, quando é diferente da meta do funil (senão null).
export const somaDiferente = funil => {
  const metas = funil.pessoas.map(p => numero(p.meta)).filter(n => n > 0);
  const metaFunil = numero(funil.metaFunil);
  if (!metas.length || !metaFunil) return null;
  const soma = metas.reduce((s, n) => s + n, 0);
  return soma === metaFunil ? null : { soma, meta: metaFunil };
};

export const temErro = funis =>
  funis.some(
    f => invalido(f.metaFunil) || f.pessoas.some(p => invalido(p.meta))
  );
