// #2894 — tudo que a ficha da pessoa mostra e faz. A tela só liga as peças: este
// composable fala com a fonte e guarda o resultado. Cada ação devolve `true` se
// deu certo e `false` se falhou; quem chama decide o aviso. Só a leitura da
// pessoa decide o estado da ficha; as outras partes falham sozinhas (`falhas`).
// #3071 — e as ações que vieram da ficha antiga. `motivo` guarda a frase que o
// servidor mandou na última falha (o DELETE do contato diz por que não apagou,
// por exemplo), ou vazio: quem chama mostra a frase dele no lugar da genérica.
// `ocupadoEm(nome)` diz se aquela ação está gravando (ficha/useAcoesComOcupado.js).
import { computed, ref } from 'vue';
import { GRAVOU_EM_PARTE } from '../fonte/gravarPessoa';
import { useAcoesComOcupado } from './useAcoesComOcupado';
import { useEstadoDaFicha } from './useEstadoDaFicha';
import { usePartesDaFicha } from './usePartesDaFicha';

const PARTES_VAZIAS = {
  conversas: [],
  cards: [],
  notas: [],
  arquivos: [],
  origem: null,
  // #3097 — o resumo das compras (cards ganhos nos funis de Vender).
  compras: null,
};

export const useFichaDaPessoa = (fonte, id) => {
  const { estado, carregar, geracao } = useEstadoDaFicha();
  const pessoa = ref(null);
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

  const { executar, motivo, ocupadoEm, algumOcupado } = useAcoesComOcupado({
    geracao,
    tela: 'relacionamentos_ficha_pessoa',
  });

  const marcarCliente = () =>
    executar('marcarCliente', async aindaVale => {
      const marcada = await fonte.marcarCliente(id.value);
      if (!aindaVale()) return;
      pessoa.value = marcada;
      await partes.reler('cards');
    });

  const desmarcarCliente = () =>
    executar('desmarcarCliente', async aindaVale => {
      const desmarcada = await fonte.desmarcarCliente(id.value);
      if (aindaVale()) pessoa.value = desmarcada;
    });

  const guardarNota = texto =>
    executar('guardarNota', async aindaVale => {
      const nota = await fonte.guardarNota(id.value, texto);
      if (!aindaVale()) return;
      partes.trocar('notas', [nota, ...partes.valores.value.notas]);
    });

  // #3075 — `retomada` guarda o que a última tentativa de salvar já gravou
  // (fonte/gravarPessoa.js): a próxima repete só o que faltou. Se a pessoa
  // ficou gravada e a foto (ou um campo que sai) falhou, a ficha já mostra a
  // pessoa como ficou, e a tela avisa que uma parte não entrou. Um segundo
  // "Salvar" enquanto o primeiro está no ar não faz nada.
  const retomada = ref(null);
  const guardarRetomada = (falha, aindaVale) => {
    if (falha?.name !== GRAVOU_EM_PARTE || !aindaVale()) return;
    const { pessoaNaFicha, ...feito } = falha.retomada;
    retomada.value = feito;
    if (pessoaNaFicha) pessoa.value = pessoaNaFicha;
  };
  const salvar = async dados => {
    if (ocupadoEm('salvar')) return false;
    return executar('salvar', async aindaVale => {
      try {
        const salva = await fonte.salvar(id.value, dados, retomada.value);
        if (!aindaVale()) return;
        pessoa.value = salva;
        retomada.value = null;
      } catch (falha) {
        guardarRetomada(falha, aindaVale);
        throw falha;
      }
    });
  };

  const liberar = () =>
    executar('liberar', async aindaVale => {
      const liberada = await fonte.liberarMensagens(id.value);
      if (aindaVale()) pessoa.value = liberada;
    });

  // As escritas que devolvem a pessoa como ficou.
  const trocarPessoa = (nome, escrever) =>
    executar(nome, async aindaVale => {
      const nova = await escrever();
      if (aindaVale()) pessoa.value = nova;
    });

  const marcarNaoQuer = () =>
    trocarPessoa('marcarNaoQuer', () => fonte.marcarNaoQuer(id.value));
  const bloquear = () =>
    trocarPessoa('bloquear', () => fonte.bloquear(id.value));
  const desbloquear = () =>
    trocarPessoa('desbloquear', () => fonte.desbloquear(id.value));
  // { por, tirar }: só o que mudou.
  const alterarEtiquetas = mudanca =>
    trocarPessoa('etiquetas', () => fonte.alterarEtiquetas(id.value, mudanca));

  // Depois de apagar, a página sai da ficha: não há o que guardar.
  const apagar = () => executar('apagar', () => fonte.apagar(id.value));

  // A outra pessoa trouxe conversas, notas, cards e arquivos: a ficha relê tudo.
  const juntar = outraId =>
    executar('juntar', async aindaVale => {
      const junta = await fonte.juntar(id.value, outraId);
      if (!aindaVale()) return;
      pessoa.value = junta;
      const lidas = await partes.lerTodas();
      if (aindaVale()) partes.guardarTodas(lidas);
    });

  const apagarNota = notaId =>
    executar('apagarNota', async aindaVale => {
      await fonte.apagarNota(id.value, notaId);
      if (!aindaVale()) return;
      partes.trocar(
        'notas',
        partes.valores.value.notas.filter(nota => nota.id !== notaId)
      );
    });

  return {
    estado,
    pessoa,
    conversas: computed(() => partes.valores.value.conversas),
    cards: computed(() => partes.valores.value.cards),
    notas: computed(() => partes.valores.value.notas),
    arquivos: computed(() => partes.valores.value.arquivos),
    origem: computed(() => partes.valores.value.origem),
    compras: computed(() => partes.valores.value.compras),
    falhas: partes.falhas,
    ocupadoEm,
    algumOcupado,
    motivo,
    carregar: () => carregar(buscar),
    relerParte: partes.reler,
    marcarCliente,
    desmarcarCliente,
    guardarNota,
    salvar,
    retomada,
    esquecerRetomada: () => {
      retomada.value = null;
    },
    liberar,
    marcarNaoQuer,
    bloquear,
    desbloquear,
    alterarEtiquetas,
    apagar,
    juntar,
    apagarNota,
  };
};
