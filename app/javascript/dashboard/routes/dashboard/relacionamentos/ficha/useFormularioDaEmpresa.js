// #2894 — o estado do formulário "Alterar" da empresa. Mesmo desenho do da
// pessoa: cada mudança cria um formulário novo e os erros só aparecem depois da
// primeira tentativa de salvar.
// #3078 — e o que a ficha antiga de Empresas tinha: cidade, "O que a empresa faz",
// foto e os campos personalizados com tipo. `mexido`: o formulário já não é o
// que abriu (fechar com algo escrito pergunta antes). `tiposDosCampos`
// ({ chave: tipo }) diz quais campos são link. Empresa nova abre com `{}`.
import { computed, ref } from 'vue';
import { errosDaEmpresa } from './errosDoFormulario';
import { formularioDaEmpresa, pedidoDaEmpresa } from './informacoesDaEmpresa';

export const useFormularioDaEmpresa = ({
  tiposDosCampos = () => ({}),
} = {}) => {
  const inicial = ref(null);
  const formulario = ref(null);
  const tentou = ref(false);

  const abrir = empresa => {
    inicial.value = formularioDaEmpresa(empresa);
    formulario.value = inicial.value;
    tentou.value = false;
  };

  const mudar = (campo, valor) => {
    formulario.value = { ...formulario.value, [campo]: valor };
  };
  const mudarAtributo = (chave, valor) =>
    mudar('atributos', { ...formulario.value.atributos, [chave]: valor });

  const problemas = () =>
    errosDaEmpresa(inicial.value, formulario.value, tiposDosCampos());

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
      : pedidoDaEmpresa(formulario.value, inicial.value, {
          tipos: tiposDosCampos(),
        });
  };

  return {
    inicial,
    formulario,
    erros,
    mexido,
    abrir,
    mudar,
    mudarAtributo,
    dadosSeValido,
  };
};
