import { ref } from 'vue';

// #2894 — as ações em grupo da lista, fora da página:
//  - "Marcar todas as N deste grupo": mostra que está carregando, não atende
//    clique duplo e descarta a resposta se aba, grupo, busca ou filtros mudaram
//    durante a espera (marcaria gente de outra consulta);
//  - `depoisDeAgir`: apagar, etiquetar ou criar cards mudam a base. Desmarca e
//    recarrega lista, contagens e resumo, para não sobrar gente que já se foi.
//    Se a ação parou no meio, `faltam` são as pessoas que ela não tentou: só
//    elas continuam marcadas, para a pessoa poder mandar de novo.
export const useAcoesEmGrupo = ({ lista, marcados, aba, aoFalhar }) => {
  const marcandoTodas = ref(false);

  const consultaAtual = () => [
    aba.value,
    lista.grupo.value,
    lista.busca.value,
    lista.filtros.value,
  ];
  const mesmaConsulta = (antes, agora) =>
    antes.every((valor, indice) => valor === agora[indice]);

  const marcarTodas = async () => {
    if (marcandoTodas.value) return;
    const consulta = consultaAtual();
    marcandoTodas.value = true;
    try {
      const todos = await lista.todosDoGrupo();
      if (mesmaConsulta(consulta, consultaAtual()))
        marcados.marcarVarias(todos);
    } catch {
      if (mesmaConsulta(consulta, consultaAtual())) aoFalhar();
    } finally {
      marcandoTodas.value = false;
    }
  };

  const depoisDeAgir = (faltam = []) => {
    marcados.marcarVarias(faltam);
    return lista.recarregar();
  };

  return { marcandoTodas, marcarTodas, depoisDeAgir };
};
