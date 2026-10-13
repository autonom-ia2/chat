import { ref } from 'vue';
import fonte from './fonte';

// #1366/#1433 (protótipo) — onde cada agente trabalha quando não é pela porta de um canal: na equipe
// de um funil ou ajudando outro agente. `papelDe` devolve undefined enquanto não leu (a tela segue a
// regra de hoje) e null quando o agente não tem papel.
export function usePapeisDosAgentes() {
  const papeis = ref(null);
  const estado = ref('carregando');

  const carregar = async agentes => {
    estado.value = 'carregando';
    try {
      papeis.value = await fonte.listarPapeis(agentes);
      estado.value = 'pronto';
    } catch {
      papeis.value = null;
      estado.value = 'erro';
    }
  };

  const papelDe = agente => {
    if (!papeis.value) return undefined;
    return papeis.value[agente.id] ?? null;
  };

  const definir = async (agente, papel) => {
    const salvo = await fonte.definirPapel(agente, papel);
    papeis.value = { ...(papeis.value || {}), [agente.id]: salvo };
    return salvo;
  };

  return { papeis, estado, carregar, papelDe, definir };
}
