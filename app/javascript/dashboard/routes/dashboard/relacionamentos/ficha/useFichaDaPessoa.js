// #2894 — tudo que a ficha da pessoa mostra e faz. A tela só liga as peças: este
// composable fala com a fonte e guarda o resultado. Cada ação devolve `true` se
// deu certo e `false` se falhou; quem chama decide o aviso.
import { ref } from 'vue';
import { useEstadoDaFicha } from './useEstadoDaFicha';

export const useFichaDaPessoa = (fonte, id) => {
  const { estado, carregar } = useEstadoDaFicha();
  const pessoa = ref(null);
  const conversas = ref([]);
  const cards = ref([]);
  const notas = ref([]);
  const arquivos = ref([]);
  const origem = ref(null);
  const ocupado = ref('');

  const buscar = async aindaVale => {
    const [achada, cc, kk, nn, aa, oo] = await Promise.all([
      fonte.pessoa(id.value),
      fonte.conversas(id.value),
      fonte.cards(id.value),
      fonte.notas(id.value),
      fonte.arquivos(id.value),
      fonte.origem(id.value),
    ]);
    if (!aindaVale()) return false;
    if (!achada) return false;
    pessoa.value = achada;
    conversas.value = cc;
    cards.value = kk;
    notas.value = nn;
    arquivos.value = aa;
    origem.value = oo;
    return true;
  };

  const executar = async (nome, acao) => {
    ocupado.value = nome;
    try {
      await acao();
      return true;
    } catch {
      return false;
    } finally {
      ocupado.value = '';
    }
  };

  const marcarCliente = () =>
    executar('marcarCliente', async () => {
      pessoa.value = await fonte.marcarCliente(id.value);
      cards.value = await fonte.cards(id.value);
    });

  const guardarNota = texto =>
    executar('guardarNota', async () => {
      const nota = await fonte.guardarNota(id.value, texto);
      notas.value = [nota, ...notas.value];
    });

  const salvar = dados =>
    executar('salvar', async () => {
      pessoa.value = await fonte.salvar(id.value, dados);
    });

  const liberar = () =>
    executar('liberar', async () => {
      pessoa.value = await fonte.liberarMensagens(id.value);
    });

  return {
    estado,
    pessoa,
    conversas,
    cards,
    notas,
    arquivos,
    origem,
    ocupado,
    carregar: () => carregar(buscar),
    marcarCliente,
    guardarNota,
    salvar,
    liberar,
  };
};
