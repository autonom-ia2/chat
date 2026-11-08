import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import {
  useCanManage,
  usePermissionGranted,
} from 'dashboard/composables/useCanManage';
import { useMapGetter } from 'dashboard/composables/store';
import { criarFonte, demoPedido } from '../utils/acharFonte';
import { papelValido, permissoesDoPapel } from '../utils/acharPapeis';

// #2692 — o que toda tela da Prospecção nova precisa: de onde ler (API ou
// demonstração), o que a pessoa pode e como andar entre as telas. Na
// demonstração, cada passo da jornada vira um `?demo=<estado>` no endereço,
// para dar para abrir qualquer estado direto e clicar a jornada inteira; o
// `&papel=` segue junto.
export const useAcharTela = () => {
  const route = useRoute();
  const router = useRouter();
  const demo = computed(() => demoPedido(route.query));
  // O &papel= do endereço é da demonstração; fora dela, as permissões vêm da
  // conta e o endereço não é lido.
  const papel = computed(() =>
    demo.value ? papelValido(route.query.papel, demo.value) : null
  );
  const contaId = useMapGetter('getCurrentAccountId');
  const usuario = useMapGetter('getCurrentUser');
  const usuarioId = computed(() => usuario.value?.id);
  const fonte = computed(() =>
    criarFonte({ demo: demo.value, usuarioId: usuarioId.value })
  );
  const podeBuscarNaConta = useCanManage('prospecting_manage');
  // Espelho de Visibility#all_searches?: administrador ou "Ver buscas de todos".
  const veTodasNoServidor = usePermissionGranted(
    'prospecting_view_all_searches'
  );
  const ajustes = ref(null);

  // Fora da demonstração: Editar busca e escolhe; mandar ao funil é o que o
  // servidor diz (can_send_to_crm). Público e dono escolhido na hora são
  // backend novo (v4, fases 2 e 3): até lá ficam desligados.
  const permissoes = computed(() => {
    if (fonte.value.usaDemo) return permissoesDoPapel(papel.value);
    return {
      buscar: podeBuscarNaConta.value,
      funil: podeBuscarNaConta.value && ajustes.value?.podeFunil === true,
      lista: false,
      trocarDono: false,
      verTodas: veTodasNoServidor.value,
    };
  });

  const carregarAjustes = async () => {
    if (fonte.value.usaDemo) return;
    try {
      ajustes.value = await fonte.value.configuracoes();
    } catch {
      ajustes.value = null;
    }
  };

  const queryDaDemo = (estado, extra = {}) => ({
    ...extra,
    demo: estado,
    ...(route.query.papel ? { papel: route.query.papel } : {}),
    // A empresa já mandada pela gaveta segue junto (rodada 4).
    ...(route.query.mandada ? { mandada: route.query.mandada } : {}),
  });

  // Vai para outra tela (`name`), levando o estado da demonstração quando há.
  const irPara = (name, { params = {}, query = {}, estado } = {}) =>
    router.push({
      name,
      params: { ...route.params, ...params },
      query: demo.value ? queryDaDemo(estado || demo.value, query) : query,
    });

  // Fica na mesma tela e troca o estado (só na demonstração).
  const mudarEstado = (estado, extra = {}) => {
    if (!demo.value) return Promise.resolve();
    return router.push({
      name: route.name,
      params: route.params,
      query: queryDaDemo(estado, extra),
    });
  };

  return {
    route,
    router,
    demo,
    papel,
    fonte,
    permissoes,
    ajustes,
    carregarAjustes,
    irPara,
    mudarEstado,
    contaId,
    usuarioId,
  };
};
