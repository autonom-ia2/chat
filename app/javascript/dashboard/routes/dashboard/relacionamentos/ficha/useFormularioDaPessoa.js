// #2894 — o estado do formulário "Alterar informações". Cada mudança cria um
// formulário novo (nada é alterado no lugar). Os erros só aparecem depois da
// primeira tentativa de salvar e acompanham o que a pessoa corrige.
import { computed, ref } from 'vue';
import { dadosParaSalvar, formularioDaPessoa } from './informacoes';
import { errosDoFormulario } from './errosDoFormulario';

export const useFormularioDaPessoa = () => {
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
  const mudarExtra = (chave, valor) =>
    mudar('extras', { ...formulario.value.extras, [chave]: valor });

  const erros = computed(() =>
    tentou.value && formulario.value
      ? errosDoFormulario(inicial.value, formulario.value)
      : {}
  );

  // Os dados prontos para a fonte, ou `null` se algum campo precisa de conserto.
  const dadosSeValido = () => {
    tentou.value = true;
    const problemas = errosDoFormulario(inicial.value, formulario.value);
    return Object.keys(problemas).length
      ? null
      : dadosParaSalvar(formulario.value);
  };

  return {
    formulario,
    erros,
    abrir,
    mudar,
    mudarRede,
    mudarExtra,
    dadosSeValido,
  };
};
