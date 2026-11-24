// #3099 — as frases do plano das duas versões, traduzidas e com os números formatados. Usada no "Como escolher a
// melhor" (DuasVersoesRegra) e no resumo da revisão (ResumoDuasVersoes), para as duas dizerem a mesma coisa. Na revisão
// (`naRevisao`), a primeira frase diz que só o teste sai na hora do "Enviar agora" ("Ao enviar, só 270 pessoas…").
// `plano`: o plano contado pelo servidor (recipient_previews, #3099), quando já chegou; sem ele, a mesma conta na tela.
import { computed, unref } from 'vue';
import { useI18n } from 'vue-i18n';
import { frasesDaAutomacao, frasesDoPlano, planoDoTeste } from './duasVersoes';

export const useFrasesDoPlano = (
  regra,
  publico,
  naAutomacao = false,
  naRevisao = false,
  plano = null
) => {
  const { t, locale } = useI18n();
  const inteiro = numero =>
    new Intl.NumberFormat(locale.value.replace('_', '-')).format(numero);
  const horas = n => t('DUAS_VERSOES.REGRA.HORAS', { n }, n);
  const formatar = (nome, valor) =>
    nome === 'horas' ? horas(valor) : inteiro(valor);
  const chaveDa = chave =>
    chave === 'TESTE' && unref(naRevisao) ? 'TESTE_AO_ENVIAR' : chave;

  return computed(() => {
    const atual = unref(regra);
    const lista = unref(naAutomacao)
      ? frasesDaAutomacao(atual)
      : frasesDoPlano(
          unref(plano) ||
            planoDoTeste(unref(publico), { divisao: atual.divisao }),
          atual
        );
    return lista.map(({ chave, params }) =>
      t(
        `DUAS_VERSOES.PLANO.${chaveDa(chave)}`,
        Object.fromEntries(
          Object.entries(params).map(([nome, valor]) => [
            nome,
            formatar(nome, valor),
          ])
        )
      )
    );
  });
};
