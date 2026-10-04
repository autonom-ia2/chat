import { computed, ref } from 'vue';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import { useMapGetter } from 'dashboard/composables/store';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// #935 — os avisos novos do Guia, comuns às duas entradas (barra lateral e bolinha do
// celular) e ao painel. A bolinha mostra quantos; abrir o Guia traz os avisos para a
// conversa e marca como vistos. O número sobe sozinho pelo ActionCable.
// Só administrador recebe aviso: para os outros, nada é buscado.
const novos = ref([]);
let carregadoPara = null;
let ouvindo = false;

const chegou = ({ id } = {}) => {
  if (id && !novos.value.includes(id)) novos.value = [...novos.value, id];
};

export function useAvisosDoGuia() {
  const papel = useMapGetter('getCurrentRole');
  const isAdmin = computed(() => papel.value === 'administrator');
  const accountId = useMapGetter('getCurrentAccountId');

  if (!ouvindo) {
    emitter.on(BUS_EVENTS.GUIDE_AVISO_CREATED, chegou);
    ouvindo = true;
  }

  const quantidade = computed(() => (isAdmin.value ? novos.value.length : 0));

  // Uma busca por conta, mesmo com as duas entradas montadas.
  const carregar = async () => {
    const conta = accountId.value;
    if (!isAdmin.value || !conta || carregadoPara === conta) return;
    carregadoPara = conta;
    novos.value = [];
    try {
      const { data } = await AutonomiaGuideAPI.avisos('novo');
      if (accountId.value === conta) {
        novos.value = (data?.avisos || []).map(aviso => aviso.id);
      }
    } catch {
      // Sem a contagem, a bolinha só não aparece; o Guia segue funcionando.
      carregadoPara = null;
    }
  };

  const marcarVistos = async () => {
    const ids = novos.value;
    if (!ids.length) return;
    novos.value = [];
    await Promise.allSettled(
      ids.map(id => AutonomiaGuideAPI.marcarAviso(id, 'visto'))
    );
  };

  return { quantidade, carregar, marcarVistos };
}
