// #2894 — tudo que a ficha da empresa mostra: ela, as pessoas dela, as conversas
// e os cards. Só leitura.
import { ref } from 'vue';
import { useEstadoDaFicha } from './useEstadoDaFicha';

export const useFichaDaEmpresa = (fonte, id) => {
  const { estado, carregar } = useEstadoDaFicha();
  const empresa = ref(null);
  const pessoas = ref([]);
  const conversas = ref([]);
  const cards = ref([]);
  const ocupado = ref('');

  const buscar = async aindaVale => {
    const [achada, gente, cc, kk] = await Promise.all([
      fonte.empresa(id.value),
      fonte.pessoasDaEmpresa(id.value),
      fonte.conversasDaEmpresa(id.value),
      fonte.cardsDaEmpresa(id.value),
    ]);
    if (!aindaVale()) return false;
    if (!achada) return false;
    empresa.value = achada;
    pessoas.value = gente;
    conversas.value = cc;
    cards.value = kk;
    return true;
  };

  // Devolve `true` se deu certo e `false` se falhou; a tela decide o aviso.
  const salvar = async dados => {
    ocupado.value = 'salvar';
    try {
      empresa.value = await fonte.salvarEmpresa(id.value, dados);
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
    pessoas,
    conversas,
    cards,
    carregar: () => carregar(buscar),
  };
};
