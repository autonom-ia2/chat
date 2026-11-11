// #2897 — perguntar de novo, de tempo em tempo, até acabar (a leitura dos PDFs,
// a busca no Agger, o andamento do que está sendo trazido). `aoChegar` recebe
// cada resposta e devolve `true` quando acabou; `parar()` encerra sem avisar.
export const acompanhar = ({ consultar, aoChegar, aoFalhar, intervalo }) => {
  let relogio = null;
  let vivo = true;

  const perguntar = async () => {
    try {
      const resposta = await consultar();
      if (!vivo) return;
      if (!aoChegar(resposta)) relogio = setTimeout(perguntar, intervalo);
    } catch {
      if (vivo) aoFalhar();
    }
  };
  perguntar();

  return {
    parar: () => {
      vivo = false;
      clearTimeout(relogio);
    },
  };
};
