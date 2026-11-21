import { ref } from 'vue';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { FAIXAS_PADRAO } from '../fonte/gruposDeCompra';

// #3097 — as faixas dos grupos de compra da conta (quantas compras faz um
// campeão, quantos dias até "em risco" e "perdido"). Até alguém ajustar, valem
// as do padrão. Na demonstração nada vai ao servidor: o ajuste fica na memória.
// `salvar` devolve true se gravou; quem chama decide o aviso. A resposta diz
// também se quem pede vê valor de venda (`veValores`): sem isso, a lista não
// oferece o filtro nem as ordens por valor (o servidor recusa). Até a leitura
// chegar, ou se ela falhar, não oferece; a demonstração mostra os valores.
const separar = ({ ve_valores: veValor = false, ...faixasLidas } = {}) => ({
  veValor,
  faixasLidas,
});

export const useFaixasDeCompra = ({ demo = false } = {}) => {
  const faixas = ref({ ...FAIXAS_PADRAO });
  const veValores = ref(demo);
  const guardar = data => {
    const { veValor, faixasLidas } = separar(data);
    faixas.value = { ...FAIXAS_PADRAO, ...faixasLidas };
    veValores.value = veValor;
  };

  const carregar = async () => {
    if (demo) return;
    try {
      const { data } = await RelacionamentosAPI.faixasDeCompra();
      guardar(data);
    } catch {
      // Sem a leitura, a tela segue com o padrão: os textos dos grupos só
      // descrevem as faixas, quem decide o grupo é o servidor.
    }
  };

  const salvar = async novas => {
    if (demo) {
      faixas.value = { ...novas };
      return true;
    }
    try {
      const { data } = await RelacionamentosAPI.salvarFaixasDeCompra(novas);
      guardar(data);
      return true;
    } catch {
      return false;
    }
  };

  return { faixas, veValores, carregar, salvar };
};
