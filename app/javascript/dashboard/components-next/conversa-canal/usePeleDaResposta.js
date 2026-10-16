// O que a pele muda na caixa de resposta (#1702): a barra e o campo do app, o Enviar
// verde e o "+". Sem pele, classes vazias e a caixa de sempre.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { PELES, usePele } from './pele';
import { CAIXA_DE_RESPOSTA } from './visualWhatsapp';

const VAZIO = {
  barra: '',
  caixa: '',
  campo: '',
  painel: '',
  gravando: '',
  enviar: '',
  iconeEnviar: '',
};

export const usePeleDaResposta = () => {
  const pele = usePele();
  const { t } = useI18n();
  const ehWhatsapp = computed(() => pele.value === PELES.WHATSAPP);
  // Caixa híbrida fora das 24 h: a resposta sai pelo número reserva, só em texto.
  const conversa = useMapGetter('getSelectedChat');
  return {
    ehWhatsapp,
    soTexto: computed(
      () => ehWhatsapp.value && Boolean(conversa.value?.whatsapp_api_reply)
    ),
    classesDaResposta: computed(() =>
      ehWhatsapp.value ? CAIXA_DE_RESPOSTA : VAZIO
    ),
    // "Digite uma mensagem", como no app ("/" continua abrindo as respostas prontas).
    textoDoCampo: computed(() =>
      ehWhatsapp.value ? t('CONVERSA_CANAL.CAIXA.DIGITE') : ''
    ),
  };
};

// "Documento" e "Fotos e vídeos" do "+" abrem o mesmo seletor de arquivo do clipe.
// Com `filtro` (ex.: 'image/*,video/*'), o seletor só mostra esses arquivos; o
// filtro de sempre volta quando a pessoa escolhe ou desiste.
export const abrirSeletorDeArquivo = filtro => {
  const campo = document.querySelector('#conversationAttachment');
  if (!campo) return;
  if (filtro) {
    const deSempre = campo.getAttribute('accept');
    const devolver = () => {
      if (deSempre === null) campo.removeAttribute('accept');
      else campo.setAttribute('accept', deSempre);
      campo.removeEventListener('change', devolver);
      campo.removeEventListener('cancel', devolver);
    };
    campo.setAttribute('accept', filtro);
    campo.addEventListener('change', devolver);
    campo.addEventListener('cancel', devolver);
  }
  campo.click();
};
