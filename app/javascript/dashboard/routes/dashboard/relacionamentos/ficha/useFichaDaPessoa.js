// #2894 — tudo que a ficha da pessoa mostra e faz. A tela só liga as peças: este
// composable fala com a fonte e guarda o resultado. Cada ação devolve `true` se
// deu certo e `false` se falhou; quem chama decide o aviso. Só a leitura da
// pessoa decide o estado da ficha; as outras partes falham sozinhas (`falhas`).
import { computed, ref } from 'vue';
import { useEstadoDaFicha } from './useEstadoDaFicha';
import { usePartesDaFicha } from './usePartesDaFicha';

const PARTES_VAZIAS = {
  conversas: [],
  cards: [],
  notas: [],
  arquivos: [],
  origem: null,
};

export const useFichaDaPessoa = (fonte, id) => {
  const { estado, carregar, geracao } = useEstadoDaFicha();
  const pessoa = ref(null);
  const ocupado = ref('');
  const partes = usePartesDaFicha({
    leitores: Object.fromEntries(
      Object.keys(PARTES_VAZIAS).map(nome => [
        nome,
        () => fonte[nome](id.value),
      ])
    ),
    vazias: PARTES_VAZIAS,
    geracao,
  });

  const buscar = async aindaVale => {
    const [achada, lidas] = await Promise.all([
      fonte.pessoa(id.value),
      partes.lerTodas(),
    ]);
    if (!aindaVale()) return false;
    if (!achada) return false;
    pessoa.value = achada;
    partes.guardarTodas(lidas);
    return true;
  };

  // `acao` recebe `aindaVale()`: se a ficha trocou de pessoa durante a escrita,
  // o que foi gravado ficou gravado, mas a resposta velha não entra na pessoa
  // que está na tela.
  const executar = async (nome, acao) => {
    ocupado.value = nome;
    const geracaoDoPedido = geracao();
    try {
      await acao(() => geracaoDoPedido === geracao());
      return true;
    } catch {
      return false;
    } finally {
      ocupado.value = '';
    }
  };

  const marcarCliente = () =>
    executar('marcarCliente', async aindaVale => {
      const marcada = await fonte.marcarCliente(id.value);
      if (!aindaVale()) return;
      pessoa.value = marcada;
      await partes.reler('cards');
    });

  const guardarNota = texto =>
    executar('guardarNota', async aindaVale => {
      const nota = await fonte.guardarNota(id.value, texto);
      if (!aindaVale()) return;
      partes.trocar('notas', [nota, ...partes.valores.value.notas]);
    });

  const salvar = dados =>
    executar('salvar', async aindaVale => {
      const salva = await fonte.salvar(id.value, dados);
      if (aindaVale()) pessoa.value = salva;
    });

  const liberar = () =>
    executar('liberar', async aindaVale => {
      const liberada = await fonte.liberarMensagens(id.value);
      if (aindaVale()) pessoa.value = liberada;
    });

  return {
    estado,
    pessoa,
    conversas: computed(() => partes.valores.value.conversas),
    cards: computed(() => partes.valores.value.cards),
    notas: computed(() => partes.valores.value.notas),
    arquivos: computed(() => partes.valores.value.arquivos),
    origem: computed(() => partes.valores.value.origem),
    falhas: partes.falhas,
    ocupado,
    carregar: () => carregar(buscar),
    relerParte: partes.reler,
    marcarCliente,
    guardarNota,
    salvar,
    liberar,
  };
};
