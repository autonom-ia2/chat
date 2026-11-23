import { computed } from 'vue';
import { catalogoDeInformacoes } from './informacoes';
import { resumoDoGrupo } from './resumoDoGrupo';

// #3168 — a frase de quem entra (lista/resumoDoGrupo.js) com o que a tela já
// tem: o idioma, as opções dos filtros (`opcoes`, um ref), os campos da conta
// (`definicoes()`), se a conta tem "Relação" (`comRelacao`, um ref) e o nome
// de cada pílula (`nomeDoGrupo`). Devolve `resumoDe({ grupo, busca, filtros })`.
export const useResumoDoGrupo = ({
  t,
  idioma,
  opcoes,
  definicoes,
  comRelacao,
  nomeDoGrupo,
}) => {
  const informacoes = computed(() =>
    catalogoDeInformacoes({
      t,
      idioma: idioma.value,
      definicoes: definicoes(),
      comRelacao: comRelacao.value,
      etiquetas: opcoes.value.etiquetas ?? [],
    })
  );
  return consulta =>
    resumoDoGrupo(consulta, {
      t,
      idioma: idioma.value,
      opcoes: opcoes.value,
      informacoes: informacoes.value,
      nomeDoGrupo,
    });
};
