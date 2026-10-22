// O que a pele muda na caixa de resposta (#1702): a barra e o campo do app, o Enviar
// verde e o "+". Na conversa do Instagram (#2079), a pílula do Direct. Sem nenhuma das
// duas, classes vazias e a caixa de sempre.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { PELES, usePele } from './pele';
import { CAIXA_DE_RESPOSTA } from './visualWhatsapp';
import { useInstagramDaConversa } from './instagram/useConversaDoInstagram';
import { CAIXA_DO_INSTAGRAM } from './instagram/visualInstagram';

const VAZIO = {
  barra: '',
  caixa: '',
  campo: '',
  painel: '',
  gravando: '',
  enviar: '',
  iconeEnviar: '',
  enviarNota: '',
  soResposta: '',
  nota: '',
  microfone: '',
};

export const usePeleDaResposta = () => {
  const pele = usePele();
  const { t } = useI18n();
  const ehWhatsapp = computed(() => pele.value === PELES.WHATSAPP);
  const { ligado: ehInstagram } = useInstagramDaConversa();
  // Caixa híbrida fora das 24 h: a resposta sai pelo número reserva, só em texto.
  const conversa = useMapGetter('getSelectedChat');
  return {
    ehWhatsapp,
    ehInstagram,
    soTexto: computed(
      () => ehWhatsapp.value && Boolean(conversa.value?.whatsapp_api_reply)
    ),
    classesDaResposta: computed(() => {
      if (ehWhatsapp.value) return CAIXA_DE_RESPOSTA;
      return ehInstagram.value ? CAIXA_DO_INSTAGRAM : VAZIO;
    }),
    // "Digite uma mensagem", como no app ("/" continua abrindo as respostas prontas).
    textoDoCampo: computed(() =>
      ehWhatsapp.value ? t('CONVERSA_CANAL.CAIXA.DIGITE') : ''
    ),
  };
};

// "Documento" e "Fotos e vídeos" do "+": cada arquivo entra na caixa de resposta
// pelo caminho de sempre (limite de tamanho, envio direto). `comoDocumento`: sai
// como documento no WhatsApp, mesmo sendo foto ou vídeo.
export const anexarArquivos = ({ arquivos, comoDocumento }, onFileUpload) =>
  arquivos.forEach(file =>
    onFileUpload({
      name: file.name,
      type: file.type,
      size: file.size,
      file,
      comoDocumento,
    })
  );

// Posição (em files do envio) de cada anexo que sai como documento. A marca é por
// anexo: documento e foto no mesmo rascunho saem cada um com o seu tipo.
export const indicesDeDocumento = anexos =>
  anexos.flatMap((anexo, indice) => (anexo.comoDocumento ? [indice] : []));
