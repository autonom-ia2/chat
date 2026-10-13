import { computed, reactive, ref, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import WhatsappApiMessageTemplatesAPI from 'dashboard/api/whatsappApiMessageTemplates';

// #1423 — o retorno novo do card: o que fazer, quando, a mensagem que sai e,
// fora das 24 horas, a mensagem pronta (aprovada). As regras são as da gaveta
// antiga (#1349): a janela é calculada para o dia escolhido; na caixa oficial
// com o WhatsApp pelo API pronto, a mensagem pronta fica opcional.
const MODOS = ['reminder_only', 'snooze_conversation', 'auto_send_message'];

// O nome começa vazio, com exemplos no campo ("Ligar dia 30 às 10h"): um
// nome pronto ("Falar com o cliente") virava o nome de tudo.
const formularioVazio = (modo = 'reminder_only') => ({
  title: '',
  dueAt: '',
  automationMode: modo,
  description: '',
  messageBody: '',
  whatsappApiTemplateId: '',
  nativeTemplateKey: '',
  templateName: '',
  templateLanguage: 'pt_BR',
  templateNamespace: '',
});

const textoDoModeloNativo = modelo =>
  (modelo?.components || []).find(parte => parte.type === 'BODY')?.text || '';

export const useCardRetorno = ({
  t,
  store,
  card,
  emit,
  podeGerenciar,
  formato,
}) => {
  const form = reactive(formularioVazio());
  const foto = ref('');
  const janela = ref(null);
  const carregandoJanela = ref(false);
  const modelosApi = ref([]);
  const carregandoModelos = ref(false);

  const conversaId = computed(
    () => card.value?.conversation_id || card.value?.conversation?.id || ''
  );
  const caixaId = computed(
    () => card.value?.inbox_id || card.value?.inbox?.id || ''
  );
  const temConversa = computed(() => Boolean(conversaId.value));
  const caixaApi = computed(() => janela.value?.whatsapp_api_inbox === true);
  const caixaOficial = computed(
    () => janela.value?.whatsapp_native_inbox === true
  );
  const foraDas24h = computed(() => janela.value?.requires_template === true);
  // Fora das 24 h na caixa oficial com o WhatsApp pelo API pronto: o texto
  // sai pelo API e a mensagem pronta passa a ser opcional (chat#1349).
  const textoLivreForaDas24h = computed(
    () =>
      caixaOficial.value &&
      foraDas24h.value &&
      janela.value?.whatsapp_api_available === true
  );
  const prontaObrigatoria = computed(
    () => foraDas24h.value && !textoLivreForaDas24h.value
  );
  const modelosNativos = computed(() => {
    if (!caixaOficial.value || !caixaId.value) return [];
    return (
      store.getters['inboxes/getFilteredWhatsAppTemplates'](caixaId.value) || []
    );
  });

  // Cada mensagem pronta vira um cartão de escolha com o texto que sai.
  const prontas = computed(() => {
    if (!foraDas24h.value) return [];
    if (caixaApi.value)
      return modelosApi.value.map(modelo => ({
        chave: String(modelo.id),
        nome: modelo.name,
        texto: modelo.body || '',
      }));
    if (caixaOficial.value)
      return modelosNativos.value.map(modelo => ({
        chave: `${modelo.name}::${modelo.language}`,
        nome: modelo.name,
        idioma: modelo.language,
        texto: textoDoModeloNativo(modelo),
      }));
    return [];
  });
  // Outra caixa fora das 24 h: o nome e o idioma da mensagem pronta são
  // digitados, como hoje.
  const prontaDigitada = computed(
    () => foraDas24h.value && !caixaApi.value && !caixaOficial.value
  );
  // Na outra caixa a pessoa digita o nome da mensagem pronta (RT-10): a
  // prévia mostra esse nome.
  const prontaEscolhida = computed(() => {
    if (prontaDigitada.value)
      return form.templateName.trim()
        ? { chave: 'digitada', nome: form.templateName.trim(), texto: '' }
        : null;
    const chave = caixaApi.value
      ? String(form.whatsappApiTemplateId || '')
      : form.nativeTemplateKey;
    return prontas.value.find(item => item.chave === chave) || null;
  });
  const escolherPronta = chave => {
    if (caixaApi.value) {
      form.whatsappApiTemplateId = chave ? Number(chave) : '';
      return;
    }
    form.nativeTemplateKey = chave || '';
    const modelo = modelosNativos.value.find(
      item => `${item.name}::${item.language}` === chave
    );
    form.templateName = modelo?.name || '';
    form.templateLanguage = modelo ? modelo.language || 'pt_BR' : '';
    form.templateNamespace = modelo?.namespace || '';
  };

  // A prévia mostra exatamente o que sai: o texto da mensagem pronta quando
  // ela é obrigatória; senão, o texto escrito. O nome da mensagem pronta nunca
  // vai para o balão: não é o que o cliente lê.
  const mensagemQueSai = computed(() => {
    if (form.automationMode !== 'auto_send_message') return '';
    if (prontaObrigatoria.value) return prontaEscolhida.value?.texto || '';
    return form.messageBody.trim();
  });
  // Outra caixa: só sabemos o nome que a pessoa escreveu, não o texto.
  const prontaSemTexto = computed(
    () =>
      form.automationMode === 'auto_send_message' &&
      prontaObrigatoria.value &&
      Boolean(prontaEscolhida.value) &&
      !prontaEscolhida.value.texto
  );

  // Fora das 24 horas sem a mensagem pronta: a prévia não pode mostrar o
  // balão do texto livre, porque ele não sai. Diz o que falta ('digitar' na
  // outra caixa, 'escolher' nas que têm lista).
  const prontaFalta = computed(() => {
    if (form.automationMode !== 'auto_send_message') return '';
    if (!prontaObrigatoria.value || prontaEscolhida.value) return '';
    return prontaDigitada.value ? 'digitar' : 'escolher';
  });

  const modos = computed(() =>
    MODOS.map(valor => ({
      valor,
      desligado: valor !== 'reminder_only' && !temConversa.value,
    }))
  );

  const sujo = computed(() => JSON.stringify({ ...form }) !== foto.value);
  const reiniciar = modo => {
    Object.assign(form, formularioVazio(modo));
    janela.value = null;
    modelosApi.value = [];
    foto.value = JSON.stringify({ ...form });
  };

  const carregarJanela = async () => {
    if (!conversaId.value) {
      janela.value = null;
      return;
    }
    carregandoJanela.value = true;
    try {
      const quando = form.dueAt
        ? new Date(form.dueAt).toISOString()
        : undefined;
      const resposta = await CrmKanbanAPI.getFollowUpMessagingWindow(
        conversaId.value,
        quando
      );
      janela.value = resposta.data;
    } catch {
      janela.value = null;
    } finally {
      carregandoJanela.value = false;
    }
  };
  const carregarModelosApi = async () => {
    if (!caixaId.value) {
      modelosApi.value = [];
      return;
    }
    carregandoModelos.value = true;
    try {
      const resposta = await WhatsappApiMessageTemplatesAPI.get(caixaId.value);
      modelosApi.value = resposta.data.payload || [];
    } catch {
      modelosApi.value = [];
    } finally {
      carregandoModelos.value = false;
    }
  };
  // A janela é a do dia escolhido, não a de agora.
  const atualizarJanela = async () => {
    if (form.automationMode !== 'auto_send_message' || !conversaId.value)
      return;
    await carregarJanela();
    if (caixaApi.value && foraDas24h.value) await carregarModelosApi();
  };
  watch(() => form.automationMode, atualizarJanela);
  watch(() => form.dueAt, atualizarJanela);

  const temPronta = () =>
    caixaApi.value
      ? Boolean(form.whatsappApiTemplateId)
      : Boolean(form.templateName.trim()) &&
        Boolean(form.templateLanguage.trim());

  const metadata = () => {
    const dados = { message_body: form.messageBody.trim() };
    if (caixaApi.value && form.whatsappApiTemplateId) {
      dados.whatsapp_api_message_template_id = Number(
        form.whatsappApiTemplateId
      );
    } else if (form.templateName.trim()) {
      dados.template_name = form.templateName.trim();
      dados.template_language = form.templateLanguage.trim() || 'pt_BR';
      if (form.templateNamespace.trim())
        dados.template_namespace = form.templateNamespace.trim();
    }
    return dados;
  };

  // O que ainda falta para marcar, na ordem da tela. O rodapé diz isso ao
  // lado do botão desligado, para ninguém ficar sem saber o motivo.
  const faltaDaPronta = () => {
    if (!prontaDigitada.value) return 'PRONTA_ESCOLHER';
    return form.templateName.trim() ? 'PRONTA_IDIOMA' : 'PRONTA_NOME';
  };
  const falta = computed(() => {
    const envia = form.automationMode === 'auto_send_message';
    return [
      !form.title.trim() && 'NOME',
      !form.dueAt && 'QUANDO',
      envia && !form.messageBody.trim() && 'MENSAGEM',
      envia && prontaObrigatoria.value && !temPronta() && faltaDaPronta(),
    ].filter(Boolean);
  });
  const pronto = computed(() => falta.value.length === 0);

  const criar = () => {
    if (!podeGerenciar.value || !card.value?.id) return false;
    if (!form.title.trim() || !form.dueAt) return false;
    const envia = form.automationMode === 'auto_send_message';
    if (envia && !form.messageBody.trim()) {
      useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_MESSAGE_BODY_REQUIRED'));
      return false;
    }
    if (envia && prontaObrigatoria.value && !temPronta()) {
      useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_TEMPLATE_REQUIRED'));
      return false;
    }
    emit('createFollowUp', {
      card_id: card.value.id,
      conversation_id: conversaId.value || null,
      title: form.title.trim(),
      description: form.description.trim(),
      follow_up_type: 'task',
      automation_mode: form.automationMode,
      due_at: new Date(form.dueAt).toISOString(),
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
      ...(envia ? { metadata: metadata() } : {}),
    });
    return true;
  };

  // O que falta para marcar, numa frase ("falta escolher quando e escrever o
  // nome da mensagem pronta").
  const faltaFrase = computed(() =>
    falta.value.length
      ? t('CRM_CARD.RETORNO.FALTA.FRASE', {
          itens: formato.juntar(
            falta.value.map(chave => t(`CRM_CARD.RETORNO.FALTA.${chave}`))
          ),
        })
      : ''
  );
  // A prévia do lado ("Como vai acontecer").
  const previa = computed(() => ({
    modo: form.automationMode,
    titulo: form.title,
    quando: form.dueAt ? formato.quando(form.dueAt) : '',
    mensagem: mensagemQueSai.value,
    prontaSemTexto: prontaSemTexto.value,
    prontaFalta: prontaFalta.value,
    pronta: prontaObrigatoria.value ? prontaEscolhida.value?.nome || '' : '',
  }));
  // Adiar na linha do retorno (data e hora ali mesmo).
  const adiar = async ({ item, quando }) => {
    if (!podeGerenciar.value) return;
    try {
      await store.dispatch('crmKanban/rescheduleFollowUp', {
        id: item.id,
        dueAt: quando,
      });
      useAlert(t('CRM_CARD.RETORNOS.ADIADO'));
      emit('refreshCard');
    } catch {
      useAlert(t('CRM_KANBAN.CALENDAR.RESCHEDULE_ERROR'));
    }
  };

  return {
    form,
    sujo,
    faltaFrase,
    previa,
    adiar,
    reiniciar,
    criar,
    pronto,
    modos,
    temConversa,
    janela,
    carregandoJanela,
    carregandoModelos,
    foraDas24h,
    textoLivreForaDas24h,
    prontaObrigatoria,
    prontaDigitada,
    prontas,
    prontaEscolhida,
    escolherPronta,
    mensagemQueSai,
    prontaSemTexto,
    prontaFalta,
    falta,
    atualizarJanela,
  };
};
