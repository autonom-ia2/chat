import { onMounted, ref } from 'vue';
import ContratadosAPI from 'dashboard/api/autonomia/contratados';

// #3211 — quais agentes prontos para contratar esta conta pode ver ('seguro_viagem_universal'...). Quem decide é o
// servidor (a flag da conta, as consultas prontas e o cofre): a tela só mostra o que veio na lista. Lista vazia ou
// leitura que falhou: nada de cartão, e a página fica como sempre foi. A falha vai para o console (só o status), como
// em useRamosDeSeguro.
const resumoDoErro = erro => erro?.response?.status ?? erro?.name ?? 'erro';

export function useContratados() {
  const modelos = ref([]);

  const carregar = async () => {
    try {
      const { data } = await ContratadosAPI.lista();
      modelos.value = Array.isArray(data?.modelos) ? data.modelos : [];
    } catch (erro) {
      // eslint-disable-next-line no-console
      console.warn('[agentes] contratados: leitura falhou', resumoDoErro(erro));
      modelos.value = [];
    }
  };

  onMounted(carregar);

  return { modelos };
}
