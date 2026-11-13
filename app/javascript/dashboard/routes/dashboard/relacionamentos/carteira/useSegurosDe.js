// #2897 — os seguros de uma pessoa ou de uma empresa, com o estado de quem
// carrega: carregando, pronto, erro ou escondido. `buscar` é o método da fonte
// (`daPessoa` ou `daEmpresa`) já com o id. Resposta de pedido antigo nunca pisa
// na de um mais novo. Quem não pode ver os seguros (ou a conta que não tem a
// leitura: a ficha da empresa sem Empresas ligada) não vê erro: o bloco some.
import { ref } from 'vue';
import { NAO_ACHEI, SEM_ACESSO } from '../ficha/falhas';

export const ESTADOS_DOS_SEGUROS = {
  CARREGANDO: 'carregando',
  PRONTO: 'pronto',
  ERRO: 'erro',
  ESCONDIDO: 'escondido',
};

const SEM_O_BLOCO = [NAO_ACHEI, SEM_ACESSO];

export const useSegurosDe = buscar => {
  const estado = ref(ESTADOS_DOS_SEGUROS.CARREGANDO);
  const seguros = ref([]);
  let pedido = 0;

  const ler = async silencioso => {
    pedido += 1;
    const meu = pedido;
    if (!silencioso) estado.value = ESTADOS_DOS_SEGUROS.CARREGANDO;
    try {
      const lista = await buscar();
      if (meu !== pedido) return;
      seguros.value = lista;
      estado.value = ESTADOS_DOS_SEGUROS.PRONTO;
    } catch (falha) {
      if (meu !== pedido) return;
      estado.value = SEM_O_BLOCO.includes(falha?.name)
        ? ESTADOS_DOS_SEGUROS.ESCONDIDO
        : ESTADOS_DOS_SEGUROS.ERRO;
    }
  };

  return {
    estado,
    seguros,
    carregar: () => ler(false),
    // Depois de uma ação na gaveta: troca a lista sem piscar o esqueleto.
    atualizar: () => ler(true),
  };
};
