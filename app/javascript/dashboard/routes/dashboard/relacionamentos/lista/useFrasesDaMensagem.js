// #2894 — as frases do diálogo "Mandar mensagem", que a lista e a ficha da
// empresa dizem igual: "Vânia, Nádia e Bruno vão receber. 2 ficam de fora: …".
// Uma regra só (quemFicaDeFora.js) e as mesmas chaves de tradução
// (RELACIONAMENTOS.LISTA.MENSAGEM). `pessoas` é uma ref ou um getter.
import { computed, toValue } from 'vue';
import { useI18n } from 'vue-i18n';
import { motivosEmPalavras } from './motivosEmPalavras';
import { nomesDe, nomesQueRecebem } from './nomesQueRecebem';
import { contaDaMensagem, foraPorMotivo } from './quemFicaDeFora';

const MENSAGEM = 'RELACIONAMENTOS.LISTA.MENSAGEM';
// Até 3 de fora: o nome e o motivo, uma frase por motivo ("Bruno e Ana ficam de
// fora: estão sem telefone."). Mais que isso: só os números, sem repetir quem.
const MAX_DE_FORA_COM_NOME = 3;

export const useFrasesDaMensagem = pessoas => {
  const { t, locale } = useI18n();
  const lista = computed(() => toValue(pessoas) ?? []);
  const conta = computed(() => contaDaMensagem(lista.value));

  // "Vânia, Nádia e mais 40": o idioma da tela (pt_BR -> pt-BR) escolhe o "e".
  const opcoesDeNomes = computed(() => ({
    idioma: locale.value.replace('_', '-'),
    eMais: count => t(`${MENSAGEM}.E_MAIS`, { count }, count),
  }));

  const frasesDeQuemFicaDeFora = computed(() => {
    const { fora } = conta.value;
    if (fora > MAX_DE_FORA_COM_NOME) {
      const motivos = motivosEmPalavras(t, conta.value).join(', ');
      return [t(`${MENSAGEM}.FORA`, { count: fora, motivos }, fora)];
    }
    return foraPorMotivo(lista.value).map(([motivo, quem]) =>
      t(
        `${MENSAGEM}.FORA_NOMES_${motivo.toUpperCase()}`,
        { quem: nomesDe(quem, opcoesDeNomes.value) },
        quem.length
      )
    );
  });

  const frases = computed(() => {
    const { recebem, fora } = conta.value;
    if (recebem === 0) {
      return [
        t(`${MENSAGEM}.NINGUEM_PODE`, {
          motivos: motivosEmPalavras(t, conta.value).join(', '),
        }),
      ];
    }
    const base = t(
      `${MENSAGEM}.QUEM_RECEBE`,
      { quem: nomesQueRecebem(lista.value, opcoesDeNomes.value) },
      recebem
    );
    return fora ? [base, ...frasesDeQuemFicaDeFora.value] : [base];
  });

  // O próximo passo vale sempre que alguém vai receber, tenha gente de fora ou não.
  const alguemRecebe = computed(() => conta.value.recebem > 0);

  return { conta, frases, alguemRecebe };
};
