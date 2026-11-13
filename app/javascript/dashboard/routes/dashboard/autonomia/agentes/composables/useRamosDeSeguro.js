import { computed, onMounted, ref } from 'vue';
import JornadaAPI from 'dashboard/api/autonomia/jornada';
import { MODELOS_DE_RAMO } from '../constants/modelosDeRamo';

// #2881 — a fileira "Prontos para o seu ramo" da página "Criar agente": quais agentes prontos esta conta pode usar.
// Quem decide é o servidor (o pacote de seguros e a flag da conta): a tela só mostra os cartões cuja chave veio na
// lista. Lista vazia ou leitura que falhou: nenhum cartão, e a página fica como sempre foi. A falha
// vai para o console (só o status), como nas outras leituras opcionais do módulo.
const resumoDoErro = erro => erro?.response?.status ?? erro?.name ?? 'erro';

export function useRamosDeSeguro() {
  const liberados = ref([]);

  const carregar = async () => {
    try {
      const { data } = await JornadaAPI.modelosDeRamo();
      liberados.value = Array.isArray(data?.modelos) ? data.modelos : [];
    } catch (erro) {
      // eslint-disable-next-line no-console
      console.warn('[agentes] ramos: leitura falhou', resumoDoErro(erro));
      liberados.value = [];
    }
  };

  onMounted(carregar);

  return {
    ramos: computed(() =>
      MODELOS_DE_RAMO.filter(modelo => liberados.value.includes(modelo.chave))
    ),
  };
}
