import { computed, ref } from 'vue';
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
  const ehNova = computed(() => Boolean(pessoa.value) && !pessoa.value.id);

  const abrir = alvo => {
    pessoa.value = alvo;
    errosDoServidor.value = {};
    aberta.value = true;
  };

  const gravar = pedido =>
    ehNova.value
      ? acoes.criarPessoa(dadosDaPessoaNova(pedido))
      : acoes.salvarPessoa(pessoa.value.id, pedido);

  const salvar = async pedido => {
    if (salvando.value) return;
    salvando.value = true;
    const nova = ehNova.value;
    try {
      const gravada = await gravar(pedido);
      aberta.value = false;
      if (nova) aoCriar(gravada);
      else aoSalvar(pedido.contato);
    } catch (falha) {
      const recusados = camposRecusados(falha);
      if (Object.keys(recusados).length) errosDoServidor.value = recusados;
      else aoFalhar(nova);
    } finally {
      salvando.value = false;
    }
  };

  return {
    aberta,
    pessoa,
    salvando,
    errosDoServidor,
    ehNova,
    abrirNova: () => abrir({}),
    abrirEdicao: abrir,
    fechar: () => {
      aberta.value = false;
    },
    salvar,
  };
};
