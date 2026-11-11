// #2894 — as contas da conferência, em funções puras: quantas pessoas vão
// chegar, a frase do topo e a checagem dos campos de conserto. Conferir texto
// digitado é método de string, sem regex.
export const SITUACAO_DO_PROBLEMA = {
  ABERTO: 'aberto',
  GUARDADO: 'guardado',
  DEIXADO: 'deixado',
};

const ZERO = 0;
const ARROBA = '@';
const PONTO = '.';
const ESPACO = ' ';

const quantosEm = (problemas, situacao) =>
  problemas.filter(problema => problema.estado === situacao).length;

// novas + completadas + consertadas − deixadas de fora. "Consertadas" são as
// linhas de que a pessoa já cuidou (guardou ou deixou de fora); as que ela
// deixou de fora saem da conta em seguida.
export const totalATrazer = ({
  novas = ZERO,
  completadas = ZERO,
  consertadas = ZERO,
  deixadasDeFora = ZERO,
}) => Math.max(ZERO, novas + completadas + consertadas - deixadasDeFora);

export const contarProblemas = (problemas = []) => ({
  abertos: quantosEm(problemas, SITUACAO_DO_PROBLEMA.ABERTO),
  guardados: quantosEm(problemas, SITUACAO_DO_PROBLEMA.GUARDADO),
  deixados: quantosEm(problemas, SITUACAO_DO_PROBLEMA.DEIXADO),
});

export const totalDaLeitura = leitura => {
  const { guardados, deixados } = contarProblemas(leitura?.problemas);
  return totalATrazer({
    novas: leitura?.resumo?.novas ?? ZERO,
    completadas: leitura?.resumo?.completadas ?? ZERO,
    consertadas: guardados + deixados,
    deixadasDeFora: deixados,
  });
};

// Os números da frase "Achei 200 pessoas…": quem foi consertado vira "nova" e
// quem ficou de fora ganha a sua parte.
export const resumoAoVivo = leitura => {
  const { abertos, guardados, deixados } = contarProblemas(leitura?.problemas);
  const resumo = leitura?.resumo ?? {};
  return {
    total: resumo.total ?? ZERO,
    novas: (resumo.novas ?? ZERO) + guardados,
    completadas: resumo.completadas ?? ZERO,
    precisamDeVoce: abertos,
    deixadas: deixados,
  };
};

export const PARTES_DA_FRASE = [
  { chave: 'NOVAS', campo: 'novas' },
  { chave: 'COMPLETADAS', campo: 'completadas' },
  { chave: 'PRECISAM', campo: 'precisamDeVoce' },
  { chave: 'DEIXADAS', campo: 'deixadas' },
];

// Cada parte vira uma chave do catálogo com plural; parte zerada some.
export const partesDaFrase = resumo =>
  PARTES_DA_FRASE.filter(({ campo }) => resumo[campo] > ZERO).map(
    ({ chave, campo }) => ({ chave, count: resumo[campo] })
  );

export const nomeValido = valor => String(valor ?? '').trim().length > ZERO;

export const emailValido = valor => {
  const texto = String(valor ?? '').trim();
  const posicao = texto.indexOf(ARROBA);
  if (posicao < 1 || posicao !== texto.lastIndexOf(ARROBA)) return false;
  if (texto.includes(ESPACO)) return false;
  const dominio = texto.slice(posicao + 1);
  return (
    dominio.includes(PONTO) &&
    !dominio.startsWith(PONTO) &&
    !dominio.endsWith(PONTO)
  );
};
