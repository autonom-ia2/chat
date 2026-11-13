// #2894 — os números da conferência, em funções puras: os contadores do topo e
// a frase deles. O cartão de cada linha só trava o campo vazio: o formato do
// e-mail, do telefone e do nome quem confere é o servidor.
export const SITUACAO_DO_PROBLEMA = {
  ABERTO: 'aberto',
  GUARDADO: 'guardado',
  DEIXADO: 'deixado',
};

const ZERO = 0;

// #2896 — a planilha enviada fica guardada por poucos dias. Depois disso o
// servidor manda os valores mascarados: dá para ver cada problema e deixar a
// linha de fora, mas não para consertar.
const VALORES_MASCARADOS = 'mascarados';
export const planilhaApagada = leitura =>
  leitura?.valores === VALORES_MASCARADOS;

const quantosEm = (problemas, situacao) =>
  problemas.filter(problema => problema.estado === situacao).length;

export const contarProblemas = (problemas = []) => ({
  abertos: quantosEm(problemas, SITUACAO_DO_PROBLEMA.ABERTO),
  guardados: quantosEm(problemas, SITUACAO_DO_PROBLEMA.GUARDADO),
  deixados: quantosEm(problemas, SITUACAO_DO_PROBLEMA.DEIXADO),
});

// As linhas com problema que ainda não vieram do servidor ("Mostrar mais").
export const problemasPorCarregar = leitura =>
  Math.max(
    ZERO,
    (leitura?.problemasTotal ?? ZERO) - (leitura?.problemas?.length ?? ZERO)
  );

// Os números do topo do Conferir. Quantas pessoas entram (`entram`), quantas
// são novas e quantas já estavam na conta quem diz é o servidor: a tela não
// refaz a conta nem chama de "nova" a linha consertada (não sabe se a pessoa já
// existe). Da tela saem só as linhas que precisam da pessoa (as abertas que já
// vieram mais as que ainda não vieram, que contam como abertas) e as que ela
// deixou de fora entre as que vieram. `juntadas` são as linhas que eram a mesma
// pessoa de outra e que a leitura já juntou (não entram no total). `clientes`
// (E3) são as que entram como cliente com as respostas de agora.
export const resumoDaTela = leitura => {
  const { abertos, deixados } = contarProblemas(leitura?.problemas);
  const resumo = leitura?.resumo ?? {};
  return {
    total: resumo.total ?? ZERO,
    novas: resumo.novas ?? ZERO,
    completadas: resumo.completadas ?? ZERO,
    precisamDeVoce: abertos + problemasPorCarregar(leitura),
    deixadas: deixados,
    juntadas: resumo.juntadas ?? ZERO,
    entram: resumo.entram ?? ZERO,
    clientes: resumo.clientes ?? ZERO,
  };
};

const PARTES_DA_FRASE = [
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
