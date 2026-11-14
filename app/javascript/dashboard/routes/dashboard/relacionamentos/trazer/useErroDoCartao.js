import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { chaveDaRecusa } from './recusaDoConserto';

// #2896, Fatia 2 — a frase de erro de uma linha de "Precisam de você"
// (components/trazer/problema/*.vue). Vem de dois lugares: a própria tela
// (`dizer`: o campo está vazio) e o servidor (`recusa`, `{ linha, motivo }`: ele
// não aceitou o valor, ou a escrita falhou). A frase aparece como alerta na
// linha e o foco vai ao primeiro controle dela: o campo, a primeira escolha da
// linha repetida, "Deixar de fora" ou, na linha recolhida, "Voltar atrás".
// `raiz` é a moldura da linha (o componente ou o elemento); `valor`, o que a
// pessoa escreve: mexeu no campo, a frase some. A frase do servidor também some
// quando a recusa some (a pessoa deixou a linha de fora, voltou atrás, ou a
// recusa passou a ser de outra linha); a da tela não depende da recusa.
// `ocupado` (opcional) é para a linha cujo controle é um botão que fica
// desligado enquanto a escrita não acaba: o foco espera o botão religar.
const ONDE_FOCAR = [
  'input',
  '[data-opcao]',
  '[data-relacionamentos="deixar-de-fora"]',
  '[data-relacionamentos="voltar-atras"]',
].join(', ');

export const useErroDoCartao = ({ recusa, campo, raiz, valor, ocupado }) => {
  const { t } = useI18n();
  const daTela = ref('');
  const doServidor = ref('');
  const erro = computed(() => daTela.value || doServidor.value);
  let devoOFoco = false;

  const focar = () => {
    const elemento = raiz.value?.$el ?? raiz.value;
    elemento?.querySelector(ONDE_FOCAR)?.focus();
  };

  const dizer = frase => {
    daTela.value = frase;
    focar();
  };

  const focarQuandoDer = async () => {
    if (!devoOFoco || ocupado?.()) return;
    devoOFoco = false;
    await nextTick();
    focar();
  };

  if (valor) {
    watch(valor, () => {
      daTela.value = '';
      doServidor.value = '';
    });
  }
  if (ocupado) watch(ocupado, focarQuandoDer);
  watch(
    recusa,
    nova => {
      doServidor.value = nova ? t(chaveDaRecusa(campo, nova.motivo)) : '';
      devoOFoco = Boolean(nova);
      if (!nova) return;
      daTela.value = '';
      focarQuandoDer();
    },
    { immediate: true }
  );

  return { erro, dizer };
};
