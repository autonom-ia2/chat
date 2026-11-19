// #2894 — o estado do formulário "Alterar informações". Cada mudança cria um
// formulário novo (nada é alterado no lugar). Os erros só aparecem depois da
// primeira tentativa de salvar e acompanham o que a pessoa corrige.
// #3062 — `mexido`: o formulário já não é o que abriu (quem fecha a gaveta com
// algo escrito ouve "Sair sem salvar?"). Escrever e apagar de volta não conta.
// #3075 — e a empresa cadastrada, a foto e os campos personalizados com tipo.
// `tiposDosCampos` ({ chave: tipo }) diz quais campos são link, para conferir.
import { computed, ref } from 'vue';
import { formularioDaPessoa, pedidoParaSalvar } from './informacoes';
import { errosDoFormulario } from './errosDoFormulario';

export const useFormularioDaPessoa = ({
  comEmpresas = () => false,
  tiposDosCampos = () => ({}),
} = {}) => {
  const inicial = ref(null);
  const formulario = ref(null);
  const tentou = ref(false);

  const abrir = pessoa => {
    inicial.value = formularioDaPessoa(pessoa);
    formulario.value = inicial.value;
    tentou.value = false;
  };

  const mudar = (campo, valor) => {
    formulario.value = { ...formulario.value, [campo]: valor };
  };
  const mudarRede = (rede, valor) =>
    mudar('redes', { ...formulario.value.redes, [rede]: valor });
  const mudarAtributo = (chave, valor) =>
    mudar('atributos', { ...formulario.value.atributos, [chave]: valor });
  // { id, nome, nova }: a escolhida da lista, a nova pelo nome, ou nenhuma.
  const mudarEmpresa = ({ id = null, nome = '', nova = false }) => {
    formulario.value = {
      ...formulario.value,
      empresa: nome,
      empresaId: id,
      empresaNova: nova,
    };
  };

  const problemas = () =>
    errosDoFormulario(inicial.value, formulario.value, tiposDosCampos());

  const erros = computed(() =>
    tentou.value && formulario.value ? problemas() : {}
  );

  const mexido = computed(
    () =>
      Boolean(inicial.value) &&
      JSON.stringify(formulario.value) !== JSON.stringify(inicial.value)
  );

  // O pedido pronto para a fonte, ou `null` se algum campo precisa de conserto.
  const dadosSeValido = () => {
    tentou.value = true;
    return Object.keys(problemas()).length
      ? null
      : pedidoParaSalvar(formulario.value, inicial.value, {
          comEmpresas: comEmpresas(),
        });
  };

  return {
    inicial,
    formulario,
    erros,
    mexido,
    abrir,
    mudar,
    mudarRede,
    mudarAtributo,
    mudarEmpresa,
    dadosSeValido,
  };
};
