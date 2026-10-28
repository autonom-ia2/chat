import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// O alto e os textos que mudam por etapa na conversa guiada (#2308, especificação 4 e 5.B): as etapas e a atual, o
// voltar (o texto diz para onde vai), o nome que as perguntas usam e o título de Ajustes.
const ETAPA_DO_PASSO = { escolha: 'ESCOLHA', confira: 'CONFIRA' };

export function useEtapasDaGuiada({
  modo,
  etapa,
  pronta,
  nome,
  comeco,
  mudou,
  podeEscolherPessoas,
  nomeDaPronta,
  voltarParaLista,
  pedirTroca,
}) {
  const { t } = useI18n();

  const etapas = computed(() =>
    modo.value === 'criar'
      ? ['ESCOLHA', 'AJUSTES', 'CONFIRA']
      : ['AJUSTES', 'CONFIRA']
  );
  const passo = computed(() => {
    if (etapa.value === 'sucesso') return etapas.value.length;
    return etapas.value.indexOf(ETAPA_DO_PASSO[etapa.value] || 'AJUSTES');
  });

  const irPara = proxima => () => {
    etapa.value = proxima;
  };
  // "Trocar a função pronta" com ajustes feitos pergunta antes: escolher outra pronta recomeça do zero.
  const trocarPronta = () => {
    if (mudou.value) pedirTroca();
    else etapa.value = 'escolha';
  };
  // No Sucesso sem poder pôr pessoas, o botão grande já volta para a lista: o alto não repete o mesmo caminho.
  const voltar = computed(() => {
    if (etapa.value === 'escolha')
      return { texto: 'VOLTAR_LISTA', ir: voltarParaLista };
    if (etapa.value === 'sucesso')
      return podeEscolherPessoas.value
        ? { texto: 'FAZER_DEPOIS', ir: voltarParaLista }
        : null;
    if (etapa.value !== 'ajustes')
      return { texto: 'VOLTAR_AJUSTES', ir: irPara('ajustes') };
    return modo.value === 'criar'
      ? { texto: 'TROCAR_PRONTA', ir: trocarPronta }
      : { texto: 'VOLTAR_LISTA', ir: voltarParaLista };
  });

  // Antes do Confira, a pronta dá nome às perguntas ("Com a função Atendente"); depois, o nome escolhido.
  const nomeNaFrase = computed(() => {
    const antesDoNome = !['confira', 'sucesso'].includes(etapa.value);
    if (modo.value === 'criar' && pronta.value && antesDoNome)
      return nomeDaPronta(pronta.value);
    return nome.value.trim();
  });

  const ajustes = computed(() => {
    if (modo.value === 'alterar')
      return {
        titulo: t('FUNCOES_EQUIPE.AJUSTES.TITULO_ALTERAR', {
          nome: comeco.value.nome,
        }),
        dica: t('FUNCOES_EQUIPE.AJUSTES.DICA_ALTERAR'),
      };
    const dica = pronta.value
      ? t('FUNCOES_EQUIPE.AJUSTES.DICA_PRONTA', {
          nome: nomeDaPronta(pronta.value),
        })
      : t('FUNCOES_EQUIPE.AJUSTES.DICA_ZERO');
    return {
      titulo: t('FUNCOES_EQUIPE.AJUSTES.TITULO'),
      dica:
        modo.value === 'duplicar'
          ? t('FUNCOES_EQUIPE.AJUSTES.DICA_ALTERAR')
          : dica,
    };
  });

  return { etapas, passo, voltar, nomeNaFrase, ajustes };
}
