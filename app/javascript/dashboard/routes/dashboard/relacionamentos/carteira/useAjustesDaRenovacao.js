// #2897 — o estado de "Como as renovações andam": o que a conta escolheu, o
// rascunho que a pessoa está mexendo e o salvar. Fala só com a fonte
// (fonte/renovacoesFonte.js); quem desenha é a página.
import { computed, ref } from 'vue';
import { useEstadoDaFicha } from '../ficha/useEstadoDaFicha';
import { ajustesMudaram, quemCotaNaConta } from './ajustesDaRenovacao';

export const useAjustesDaRenovacao = fonte => {
  const { estado, carregar } = useEstadoDaFicha();
  // O que a tela precisa além das escolhas: funis, vencimentos, quem atende…
  const conta = ref(null);
  const salvos = ref(null);
  const rascunho = ref(null);
  const salvando = ref(false);

  const buscar = async aindaVale => {
    const { ajustes, ...resto } = await fonte.ajustes();
    if (!aindaVale()) return false;
    conta.value = resto;
    // Quem cota só pode ser uma opção que a conta tem.
    salvos.value = {
      ...ajustes,
      quemCota: quemCotaNaConta(ajustes.quemCota, resto),
    };
    rascunho.value = { ...salvos.value };
    return true;
  };

  // `true` se salvou; as escolhas continuam como estão quando falha.
  const salvar = async () => {
    salvando.value = true;
    try {
      salvos.value = await fonte.salvar(rascunho.value);
      rascunho.value = { ...salvos.value };
      return true;
    } catch {
      return false;
    } finally {
      salvando.value = false;
    }
  };

  return {
    estado,
    conta,
    rascunho,
    salvando,
    mudou: computed(() => ajustesMudaram(salvos.value, rascunho.value)),
    carregar: () => carregar(buscar),
    salvar,
  };
};
