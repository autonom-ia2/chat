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

// Envio numa mensagem só (WAHA, híbrida): a marca de documento vale para todos os
// anexos, então só vai quando todos são documento. Rascunho com os dois tipos sai
// um anexo por mensagem, cada um com o seu tipo.
export const todosComoDocumento = anexos =>
  anexos.length > 0 && anexos.every(anexo => anexo.comoDocumento);

export const documentoMisturadoComMidia = anexos =>
  anexos.some(anexo => anexo.comoDocumento) && !todosComoDocumento(anexos);
