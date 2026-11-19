// #2894 — tudo que a ficha da empresa mostra: ela, as pessoas dela, as conversas
// e os cards. Só a leitura da empresa decide o estado da ficha; as outras partes
// falham sozinhas (`falhas`).
// #3078 — e o que a ficha antiga de Empresas tinha: as notas das pessoas, as
// mídias (só com `comMidias`, a chave relationships_company_media), salvar com
// foto e campos, apagar, e pôr e tirar pessoa. Cada ação devolve `true` se deu
// certo e `false` se falhou (ficha/useAcoesComOcupado.js); quem chama decide o
// aviso. Pôr e tirar pessoa releem a empresa (o número de pessoas e de
// clientes) e as partes que dependem de quem está nela.
import { computed, ref } from 'vue';
import { GRAVOU_EM_PARTE } from '../fonte/gravarPessoa';
import { useAcoesComOcupado } from './useAcoesComOcupado';
import { useEstadoDaFicha } from './useEstadoDaFicha';
import { usePartesDaFicha } from './usePartesDaFicha';

const MIDIAS_VAZIAS = { itens: [], total: 0 };
const PARTES_VAZIAS = {
  pessoas: [],
  conversas: [],
  cards: [],
  notas: [],
  midias: MIDIAS_VAZIAS,
};
// O que muda quando alguém entra ou sai da empresa.
const PARTES_DAS_PESSOAS = ['pessoas', 'conversas', 'cards', 'notas', 'midias'];

export const useFichaDaEmpresa = (
  fonte,
  id,
  { comMidias = () => false } = {}
) => {
  const { estado, carregar, geracao } = useEstadoDaFicha();
  const empresa = ref(null);
  const partes = usePartesDaFicha({
    leitores: {
      pessoas: () => fonte.pessoasDaEmpresa(id.value),
      conversas: () => fonte.conversasDaEmpresa(id.value),
      cards: () => fonte.cardsDaEmpresa(id.value),
      notas: () => fonte.notasDaEmpresa(id.value),
      midias: () =>
        comMidias() ? fonte.midiasDaEmpresa(id.value) : MIDIAS_VAZIAS,
    },
    vazias: PARTES_VAZIAS,
    geracao,
  });
  const { executar, motivo, ocupadoEm, algumOcupado } = useAcoesComOcupado({
    geracao,
    tela: 'relacionamentos_ficha_empresa',
  });

  const buscar = async aindaVale => {
    const [achada, lidas] = await Promise.all([
      fonte.empresa(id.value),
      partes.lerTodas(),
    ]);
    if (!aindaVale()) return false;
    if (!achada) return false;
    empresa.value = achada;
    partes.guardarTodas(lidas);
    return true;
  };

  // Se a empresa ficou gravada e só a foto (ou um campo que sai) falhou, a
  // ficha já a mostra como ficou; `salvouEmParte` diz isso à tela.
  const salvouEmParte = ref(false);
  const salvar = pedido => {
    if (ocupadoEm('salvar')) return Promise.resolve(false);
    salvouEmParte.value = false;
    return executar('salvar', async aindaVale => {
      try {
        const salva = await fonte.salvarEmpresa(id.value, pedido);
        if (aindaVale()) empresa.value = salva;
      } catch (falha) {
        const naFicha = falha?.retomada?.empresaNaFicha;
        if (falha?.name === GRAVOU_EM_PARTE && aindaVale()) {
          salvouEmParte.value = true;
          if (naFicha) empresa.value = naFicha;
        }
        throw falha;
      }
    });
  };

  // Depois de apagar, a página sai da ficha: não há o que guardar.
  const apagar = () => executar('apagar', () => fonte.apagarEmpresa(id.value));

  const releituraDasPessoas = async aindaVale => {
    const [relida, lidas] = await Promise.all([
      // A pessoa já entrou ou saiu: a releitura que falha não desfaz isso.
      fonte.empresa(id.value).catch(() => null),
      Promise.all(PARTES_DAS_PESSOAS.map(nome => partes.reler(nome))),
    ]);
    if (aindaVale() && relida) empresa.value = relida;
    return lidas;
  };

  const porPessoa = pessoaId =>
    executar('porPessoa', async aindaVale => {
      await fonte.porPessoaNaEmpresa(id.value, pessoaId);
      await releituraDasPessoas(aindaVale);
    });

  const tirarPessoa = pessoaId =>
    executar('tirarPessoa', async aindaVale => {
      await fonte.tirarPessoaDaEmpresa(id.value, pessoaId);
      await releituraDasPessoas(aindaVale);
    });

  return {
    estado,
    empresa,
    pessoas: computed(() => partes.valores.value.pessoas),
    conversas: computed(() => partes.valores.value.conversas),
    cards: computed(() => partes.valores.value.cards),
    notas: computed(() => partes.valores.value.notas),
    midias: computed(() => partes.valores.value.midias),
    falhas: partes.falhas,
    ocupadoEm,
    algumOcupado,
    motivo,
    salvouEmParte,
    carregar: () => carregar(buscar),
    relerParte: partes.reler,
    salvar,
    apagar,
    porPessoa,
    tirarPessoa,
    buscarPessoas: termo => fonte.buscarPessoasParaEmpresa(id.value, termo),
  };
};
