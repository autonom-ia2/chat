import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import { ehSemAcesso } from './falhas';

// #3078 — a gaveta "Mais filtros" da lista (tirada de pages/ListaPage.vue):
// abrir lê o que cada filtro oferece (`lerOpcoes`, da fonte); "Ver resultado"
// e "Limpar" fecham e mudam a lista. A leitura que falha avisa: sem acesso,
// com a frase de quem não pode ver (`fraseSemAcesso`); o resto, com o erro
// genérico (`erroGenerico`).
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

  const abrir = async () => {
    aberta.value = true;
    try {
      opcoes.value = await lerOpcoes();
    } catch (falha) {
      useAlert(ehSemAcesso(falha) ? fraseSemAcesso() : erroGenerico());
    }
  };
  const aplicar = novos => {
    aberta.value = false;
    lista.mudarFiltros(novos);
  };
  const limpar = () => {
    aberta.value = false;
    lista.limparFiltros();
  };

  return { aberta, opcoes, abrir, aplicar, limpar };
};
