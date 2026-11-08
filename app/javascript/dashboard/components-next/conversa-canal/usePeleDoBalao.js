// O que a pele muda num balão (#1702). Sem pele, tudo vazio e o balão fica como sempre.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../message/provider.js';
import { MESSAGE_STATUS, ORIENTATION } from '../message/constants';
import { PELES, usePele, usePrimeiras } from './pele';
import { useModeloDaMensagem } from './useModeloDaMensagem';
import { useEcoDoCelular } from './useEcoDoCelular';
import { ehRobo, origemDaMensagem } from './origemDoEnvio';
import {
  CLASSES_DO_REMETENTE,
  classesDaHora,
  classesDoBalao,
  corDoBico,
  temBico,
} from './visualWhatsapp';

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
    if (ehRobo(tipo)) {
      return nome
        ? t('CONVERSA_CANAL.REMETENTE.AGENTE_COM_NOME', { nome })
        : t('CONVERSA_CANAL.REMETENTE.AGENTE');
    }
    // #2048: envio automático em nome da pessoa (follow-up, aviso do Agendamento) mostra a
    // origem, não a pessoa: foi a plataforma que mandou.
    const origem = origemDaMensagem(tipo, contentAttributes.value);
    if (origem) return t(origem);
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
