import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { ehSemAcesso } from './falhas';

// #3078 — a gaveta "Mais filtros" da lista (tirada de pages/ListaPage.vue):
// abrir lê o que cada filtro oferece (`lerOpcoes`, da fonte); "Ver resultado"
// e "Limpar" fecham e mudam a lista. A leitura que falha avisa: sem acesso,
// com a frase de quem não pode ver (`fraseSemAcesso`); o resto, com o erro
// genérico (`erroGenerico`).
// #3168 — `abrirParaGrupo(grupo)`: a gaveta abre no modo do grupo guardado
// escolhido (`doGrupo`: "Guardar no grupo" | "Ver sem guardar"), com os filtros
// que estão na tela. `abrir()` é a gaveta de sempre. `carregarOpcoes()` lê as
// opções sem abrir (a frase de quem entra no grupo usa os nomes delas).
export const OPCOES_VAZIAS = Object.freeze({
  empresas: [],
  etiquetas: [],
  cidades: [],
  cidades_das_empresas: [],
});

export const useGavetaDeFiltros = ({
  lista,
  lerOpcoes,
  fraseSemAcesso,
  erroGenerico,
}) => {
  const aberta = ref(false);
  const opcoes = ref(OPCOES_VAZIAS);
  const doGrupo = ref(null);

  const lerAsOpcoes = async () => {
    try {
      opcoes.value = await lerOpcoes();
    } catch (falha) {
      useAlert(ehSemAcesso(falha) ? fraseSemAcesso() : erroGenerico());
    }
  };
  const abrir = () => {
    doGrupo.value = null;
    aberta.value = true;
    return lerAsOpcoes();
  };
  const abrirParaGrupo = grupo => {
    doGrupo.value = grupo;
    aberta.value = true;
    return lerAsOpcoes();
  };
  const aplicar = novos => {
    aberta.value = false;
    lista.mudarFiltros(novos);
  };
  const limpar = () => {
    aberta.value = false;
    lista.limparFiltros();
  };

  return {
    aberta,
    opcoes,
    doGrupo,
    abrir,
    abrirParaGrupo,
    aplicar,
    limpar,
    carregarOpcoes: lerAsOpcoes,
  };
};
