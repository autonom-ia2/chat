import { computed, ref } from 'vue';
import { GRAVOU_EM_PARTE } from '../fonte/gravarPessoa';
import { camposRecusados } from './recusaDoContato';

// #3062 — "Nova pessoa" e "Editar" da linha, os dois na gaveta "Alterar
// informações" da ficha (components/ficha/GavetaDeInformacoes.vue). Nova pessoa
// abre a gaveta vazia; editar abre com o que a linha já trouxe. Salvar chama a
// fonte (criarPessoa ou salvarPessoa) e:
//  - deu certo: fecha e chama `aoCriar(criada)` ou `aoSalvar(dados)`;
//  - o servidor recusou e-mail ou telefone repetido: a gaveta fica aberta com
//    o aviso embaixo do campo (`errosDoServidor`);
//  - outra falha: a gaveta fica aberta e `aoFalhar(ehNova)` avisa.
// Clique duplo em "Salvar" não manda duas vezes.
// #3075 — o que a gaveta manda é o pedido inteiro (ficha/informacoes.js#
// pedidoParaSalvar): o contato, a empresa nova, a foto e os campos que saem.
// `aoSalvar` recebe o contato.
// Se uma parte ficou gravada e outra falhou (fonte/gravarPessoa.js), a gaveta
// fica aberta e guarda a `retomada`: o próximo "Salvar" repete só o que faltou,
// sem criar a pessoa nem cadastrar a empresa de novo. `empresaCadastrada` é a
// empresa que já existe, para a gaveta trocar "empresa nova" por ela. Com a
// pessoa já gravada, `aoFalhar(ehNova, { parcial: true })`.

// A pessoa nova não leva campo vazio: só o que foi escrito.
export const dadosDaPessoaNova = pedido => ({
  ...pedido,
  contato: {
    ...pedido.contato,
    additional_attributes: Object.fromEntries(
      Object.entries(pedido.contato.additional_attributes ?? {}).filter(
        ([, valor]) => valor !== ''
      )
    ),
  },
});

export const usePessoaNaGaveta = ({ acoes, aoCriar, aoSalvar, aoFalhar }) => {
  const aberta = ref(false);
  const pessoa = ref(null);
  const salvando = ref(false);
  const errosDoServidor = ref({});
  const retomada = ref(null);
  const ehNova = computed(() => Boolean(pessoa.value) && !pessoa.value.id);

  const abrir = alvo => {
    pessoa.value = alvo;
    errosDoServidor.value = {};
    retomada.value = null;
    aberta.value = true;
  };

  const gravar = pedido =>
    ehNova.value
      ? acoes.criarPessoa(dadosDaPessoaNova(pedido), retomada.value)
      : acoes.salvarPessoa(pessoa.value.id, pedido, retomada.value);

  const salvar = async pedido => {
    if (salvando.value) return;
    salvando.value = true;
    const nova = ehNova.value;
    try {
      const gravada = await gravar(pedido);
      retomada.value = null;
      aberta.value = false;
      if (nova) aoCriar(gravada);
      else aoSalvar(pedido.contato);
    } catch (falha) {
      if (falha?.name === GRAVOU_EM_PARTE) retomada.value = falha.retomada;
      const recusados = camposRecusados(falha);
      if (Object.keys(recusados).length) errosDoServidor.value = recusados;
      else aoFalhar(nova, { parcial: Boolean(retomada.value?.pessoa) });
    } finally {
      salvando.value = false;
    }
  };

  return {
    aberta,
    pessoa,
    salvando,
    errosDoServidor,
    empresaCadastrada: computed(() => retomada.value?.empresa ?? null),
    ehNova,
    abrirNova: () => abrir({}),
    abrirEdicao: abrir,
    fechar: () => {
      aberta.value = false;
    },
    salvar,
  };
};
