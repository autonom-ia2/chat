// O que a pele muda num balão (#1702). Sem pele, tudo vazio e o balão fica como sempre.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../message/provider.js';
import {
  MESSAGE_STATUS,
  ORIENTATION,
  SENDER_TYPES,
} from '../message/constants';
import { PELES, usePele, usePrimeiras } from './pele';
import { useModeloDaMensagem } from './useModeloDaMensagem';
import { useEcoDoCelular } from './useEcoDoCelular';
import {
  CLASSES_DO_REMETENTE,
  classesDaHora,
  classesDoBalao,
  corDoBico,
  temBico,
} from './visualWhatsapp';

const ROBOS = [SENDER_TYPES.AGENT_BOT, SENDER_TYPES.CAPTAIN_ASSISTANT];

export const usePeleDoBalao = nomeDoBalao => {
  const pele = usePele();
  const primeiras = usePrimeiras();
  const { t } = useI18n();
  const {
    id,
    variant,
    orientation,
    sender,
    senderType,
    contentAttributes,
    additionalAttributes,
    inboxId,
    status,
  } = useMessageContext();
  // Modelo com botões: a hora fica numa linha só dela, acima dos botões.
  const { botoes: botoesDoModelo } = useModeloDaMensagem(
    computed(() => ({
      additionalAttributes: additionalAttributes?.value,
      inboxId: inboxId?.value,
    }))
  );

  // #1941: eco do celular leva o nome de quem estava atribuído quando chegou.
  const eco = useEcoDoCelular(contentAttributes);

  const ativa = computed(() => pele.value === PELES.WHATSAPP);
  const estado = computed(() => ({
    variante: variant.value,
    lado: orientation.value,
    primeira: primeiras.value.has(id.value),
    // Modelo que não saiu não mostra botões (BotoesDoModelo): fica o balão de texto.
    nomeDoBalao:
      botoesDoModelo.value.length && status?.value !== MESSAGE_STATUS.FAILED
        ? 'modelo'
        : nomeDoBalao,
  }));

  // Nome de quem mandou, só no 1º balão enviado da sequência.
  const remetente = computed(() => {
    if (!ativa.value || !estado.value.primeira) return '';
    if (orientation.value !== ORIENTATION.RIGHT) return '';
    // Nunca o remetente do eco: no WAHA é o dono da chave de conexão.
    if (eco.ehEco.value) return eco.nomeDoAutor.value;
    const tipo = sender.value?.type ?? senderType.value;
    const nome = sender.value?.available_name || sender.value?.name || '';
    if (ROBOS.includes(tipo)) {
      return nome
        ? t('CONVERSA_CANAL.REMETENTE.AGENTE_COM_NOME', { nome })
        : t('CONVERSA_CANAL.REMETENTE.AGENTE');
    }
    // Follow-up que a plataforma mandou sozinha (crm_follow_up_id): o nome é de quem criou,
    // mas não foi ela que digitou.
    if (nome && contentAttributes.value?.crmFollowUpId) {
      return t('CONVERSA_CANAL.REMETENTE.AUTOMATICO', { nome });
    }
    return nome;
  });

  return {
    ativa,
    remetente,
    classesDoRemetente: CLASSES_DO_REMETENTE,
    classesDoBalao: computed(() =>
      ativa.value ? classesDoBalao(estado.value) : ''
    ),
    classesDaHora: computed(() =>
      ativa.value ? classesDaHora(estado.value) : ''
    ),
    bico: computed(() =>
      ativa.value && temBico(estado.value) ? corDoBico(estado.value) : ''
    ),
  };
};
