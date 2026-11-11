// #2894 — tudo que a ficha da empresa mostra: ela, as pessoas dela, as conversas
// e os cards. Só a leitura da empresa decide o estado da ficha; as outras partes
// falham sozinhas (`falhas`).
import { computed, ref } from 'vue';
import { useEstadoDaFicha } from './useEstadoDaFicha';
import { usePartesDaFicha } from './usePartesDaFicha';

const PARTES_VAZIAS = { pessoas: [], conversas: [], cards: [] };

export const useFichaDaEmpresa = (fonte, id) => {
  const { estado, carregar, geracao } = useEstadoDaFicha();
  const empresa = ref(null);
  const ocupado = ref('');
  const partes = usePartesDaFicha({
    leitores: {
      pessoas: () => fonte.pessoasDaEmpresa(id.value),
      conversas: () => fonte.conversasDaEmpresa(id.value),
      cards: () => fonte.cardsDaEmpresa(id.value),
    },
    vazias: PARTES_VAZIAS,
    geracao,
  });

  const buscar = async aindaVale => {
    const [achada, lidas] = await Promise.all([
      fonte.empresa(id.value),
      partes.lerTodas(),
    ]);
    if (!aindaVale()) return false;
    if (!achada) return false;
    empresa.value = achada;
    partes.guardarTodas(lidas);
    return true;
  };

  // Devolve `true` se deu certo e `false` se falhou; a tela decide o aviso. Se a
  // ficha trocou de empresa durante o salvamento, o que foi salvo ficou salvo,
  // mas a resposta velha não sobrescreve a empresa que está na tela.
  const salvar = async dados => {
    ocupado.value = 'salvar';
    const geracaoDoPedido = geracao();
    try {
      const salva = await fonte.salvarEmpresa(id.value, dados);
      if (geracaoDoPedido === geracao()) empresa.value = salva;
      return true;
    } catch {
      return false;
    } finally {
      ocupado.value = '';
    }
  };

  return {
    ocupado,
    salvar,
    estado,
    empresa,
    pessoas: computed(() => partes.valores.value.pessoas),
    conversas: computed(() => partes.valores.value.conversas),
    cards: computed(() => partes.valores.value.cards),
    falhas: partes.falhas,
    carregar: () => carregar(buscar),
    relerParte: partes.reler,
  };
};
