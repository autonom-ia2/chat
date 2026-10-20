// O eco do celular (#1941) visto por um balão: se é eco e quem estava atribuído quando
// chegou. As regras ficam em ecoDoCelular.js; aqui só o store de agentes da conta.
import { computed, toValue } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { autorDoEco, ehEcoDoCelular, nomeDoAgente } from './ecoDoCelular';

export const useEcoDoCelular = atributos => {
  const agentePorId = useMapGetter('agents/getAgentById');
  const ehEco = computed(() => ehEcoDoCelular(toValue(atributos)));
  const autor = computed(() =>
    autorDoEco(toValue(atributos), id => agentePorId.value?.(id))
  );
  const nomeDoAutor = computed(() => nomeDoAgente(autor.value));
  return { ehEco, autor, nomeDoAutor };
};
