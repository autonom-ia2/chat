// #2894 — tudo que a ficha da pessoa mostra e faz. A tela só liga as peças: este
// composable fala com a fonte e guarda o resultado. Cada ação devolve `true` se
// deu certo e `false` se falhou; quem chama decide o aviso. Só a leitura da
// pessoa decide o estado da ficha; as outras partes falham sozinhas (`falhas`).
// #3071 — e as ações que vieram da ficha antiga. `motivo` guarda a frase que o
// servidor mandou na última falha (o DELETE do contato diz por que não apagou,
// por exemplo), ou vazio: quem chama mostra a frase dele no lugar da genérica.
// `ocupadoEm(nome)` diz se aquela ação está gravando; duas ações diferentes
// podem estar no ar ao mesmo tempo sem uma soltar o "ocupado" da outra.
// Só a falha do servidor (a resposta, a rede, o "não achei") vira `false`: um
// defeito da tela vai para o Sentry, sem dado da pessoa, e também devolve
// `false`, para a tela dizer que não deu.
import { computed, ref } from 'vue';
import { reportarSemDados } from 'dashboard/helper/sentryPrivacy';
import { GRAVOU_EM_PARTE } from '../fonte/gravarPessoa';
import { NAO_ACHEI, SEM_ACESSO } from './falhas';
import { useEstadoDaFicha } from './useEstadoDaFicha';
import { usePartesDaFicha } from './usePartesDaFicha';

const ONDE_FALHOU = { tela: 'relacionamentos_ficha_pessoa' };
const FALHAS_COM_NOME = [NAO_ACHEI, SEM_ACESSO];

const veioDoServidor = falha =>
  Boolean(
    falha?.isAxiosError ||
      falha?.response ||
      falha?.cause?.response ||
      falha?.cause?.isAxiosError ||
      FALHAS_COM_NOME.includes(falha?.name)
  );

const fraseDoServidor = falha => {
  const frase =
    falha?.cause?.response?.data?.message ?? falha?.response?.data?.message;
  return typeof frase === 'string' ? frase : '';
};

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
  const ocupados = ref(new Set());
  const motivo = ref('');
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
  const marcarOcupado = (nome, sim) => {
    const novos = new Set(ocupados.value);
    if (sim) novos.add(nome);
    else novos.delete(nome);
    ocupados.value = novos;
  };

  const executar = async (nome, acao) => {
    marcarOcupado(nome, true);
    motivo.value = '';
    const geracaoDoPedido = geracao();
    try {
      await acao(() => geracaoDoPedido === geracao());
      return true;
    } catch (falha) {
      if (!veioDoServidor(falha)) reportarSemDados(falha, ONDE_FALHOU);
      motivo.value = fraseDoServidor(falha);
      return false;
    } finally {
      marcarOcupado(nome, false);
    }
  };

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
    if (ocupados.value.has('salvar')) return false;
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
    falhas: partes.falhas,
    ocupadoEm: nome => ocupados.value.has(nome),
    algumOcupado: computed(() => ocupados.value.size > 0),
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
