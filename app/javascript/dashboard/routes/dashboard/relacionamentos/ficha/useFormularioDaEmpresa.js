// #2894 — o estado do formulário "Alterar" da empresa (nome, CNPJ e site). Mesmo
// desenho do da pessoa: cada mudança cria um formulário novo e os erros só
// aparecem depois da primeira tentativa de salvar.
import { computed, ref } from 'vue';
import { errosDaEmpresa } from './errosDoFormulario';
import { dadosDaEmpresaParaSalvar, formularioDaEmpresa } from './informacoes';

export const useFormularioDaEmpresa = () => {
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

  const erros = computed(() =>
    tentou.value && formulario.value
      ? errosDaEmpresa(inicial.value, formulario.value)
      : {}
  );

  // Os dados prontos para a fonte, ou `null` se algum campo precisa de conserto.
  const dadosSeValido = () => {
    tentou.value = true;
    const problemas = errosDaEmpresa(inicial.value, formulario.value);
    return Object.keys(problemas).length
      ? null
      : dadosDaEmpresaParaSalvar(formulario.value);
  };

  return { formulario, erros, abrir, mudar, dadosSeValido };
};
