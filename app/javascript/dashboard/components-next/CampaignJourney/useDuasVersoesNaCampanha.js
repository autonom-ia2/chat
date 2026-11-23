// #3099 (F3 do épico #3095) — a ligação das "Duas versões da mensagem" com a Nova campanha: o que o cartão do passo
// Mensagem (DuasVersoesMensagem) e o resumo da revisão (ResumoDuasVersoes) precisam, tirado do rascunho, dos modelos
// da caixa, do e-mail já criado e do "Vão receber" do servidor. As telas continuam só com props; esta peça monta.
//
// O plano do teste (quantos testam, quantos ficam para depois) vem do servidor, no mesmo POST recipient_previews do
// "Vão receber" (journeyChannelPayloads#planoNoPreview). Enquanto ele não chega, a tela faz a mesma conta
// (duasVersoes.js#planoDoTeste) com o "Vão receber" sem o grupo de controle.
import { computed } from 'vue';
import { CAMPAIGN_CHANNELS } from './campaignChannels';
import {
  duasVersoesVazias,
  motivoDaSegunda,
  planoDoTeste,
} from './duasVersoes';
import { templateVariables } from './templateVariables';

// Partes do modelo que não pedem informação na campanha: o texto já entra pelas variáveis, e esses botões não levam
// nada da campanha. Qualquer outra parte (topo com arquivo, oferta com prazo, carrossel, catálogo, cupom) precisa ser a
// mesma nas duas versões, para a ligação das informações da versão 1 servir às duas (D3).
const PARTES_SEM_INFORMACAO = ['HEADER', 'BODY', 'FOOTER', 'BUTTONS'];
const BOTOES_SEM_INFORMACAO = ['QUICK_REPLY', 'PHONE_NUMBER', 'URL'];

const assinaturaDoModelo = modelo => {
  const partes = modelo?.components || [];
  const topo = partes.find(parte => parte.type === 'HEADER');
  const botoes = partes.find(parte => parte.type === 'BUTTONS')?.buttons || [];
  return JSON.stringify({
    chaves: templateVariables(modelo)
      .map(({ key }) => key)
      .sort(),
    topo: topo?.format || '',
    partes: partes
      .map(parte => parte.type)
      .filter(tipo => !PARTES_SEM_INFORMACAO.includes(tipo))
      .sort(),
    botoes: botoes
      .map(botao => botao.type)
      .filter(tipo => !BOTOES_SEM_INFORMACAO.includes(tipo))
      .sort(),
  });
};

// As mesmas informações que a versão 1 pede (o servidor confere de novo na criação: segunda_versao_outras_informacoes).
export const mesmasInformacoes = (modelo, primeiro) =>
  Boolean(modelo && primeiro) &&
  assinaturaDoModelo(modelo) === assinaturaDoModelo(primeiro);

const aprovado = modelo =>
  String(modelo?.status || '').toLowerCase() === 'approved';

// `draft`, `update`: o rascunho da Nova campanha. `templates`, `templateOptions`, `template`: os modelos da caixa, as
// opções da escolha (com o nome bonito da ponte de Modelos) e o modelo da versão 1. `corpoDoModelo(modelo)`: o texto
// do modelo com as mesmas ligações da versão 1. `emailCampaign`: o e-mail criado no passo 2. `preview`: o "Vão
// receber" do servidor. `reach`: o público no canal, enquanto o servidor não responde.
export const useDuasVersoesNaCampanha = ({
  draft,
  update,
  templates,
  templateOptions,
  template,
  corpoDoModelo,
  emailCampaign,
  preview,
  reach,
}) => {
  const canal = computed(() => draft.value.channel);
  const ehOficial = computed(
    () => canal.value === CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL
  );
  const ehEmail = computed(() => canal.value === CAMPAIGN_CHANNELS.EMAIL);
  const guardadas = computed(
    () => draft.value.duasVersoes || duasVersoesVazias()
  );

  // No e-mail, a versão 1 é o e-mail criado no passo 2: sem ele ainda não há o que testar.
  const disponivel = computed(
    () => !ehEmail.value || Boolean(draft.value.emailCampaignId)
  );

  const opcaoDe = id =>
    templateOptions.value.find(opcao => String(opcao.value) === String(id));
  const rotuloDe = id => opcaoDe(id)?.label || '';
  // Só os aprovados que a campanha consegue mandar (a ponte de Modelos apaga, com o motivo, os que não vão).
  const serveNaCampanha = modelo =>
    aprovado(modelo) && !opcaoDe(modelo.id)?.disabled;
  const modelos = computed(() =>
    ehOficial.value
      ? templates.value.filter(serveNaCampanha).map(modelo => ({
          value: modelo.id,
          label: rotuloDe(modelo.id) || modelo.name,
          corpo: corpoDoModelo(modelo),
          mesmasInformacoes: mesmasInformacoes(modelo, template.value),
        }))
      : []
  );
  // Modelo da versão 2 que não serve mais (outra caixa, outro modelo na versão 1, deixou de ser aprovado): a escolha
  // volta a ficar vazia, e a campanha só segue depois de escolher de novo.
  const modeloQueServe = computed(() => {
    const id = guardadas.value.templateId;
    const opcao = modelos.value.find(
      modelo => String(modelo.value) === String(id)
    );
    if (!opcao || !opcao.mesmasInformacoes) return null;
    return String(id) === String(draft.value.templateId) ? null : opcao;
  });
  const modeloDaSegunda = computed(() =>
    modeloQueServe.value
      ? templates.value.find(
          modelo => String(modelo.id) === String(modeloQueServe.value.value)
        ) || null
      : null
  );

  const versoes = computed(() =>
    ehOficial.value && guardadas.value.templateId && !modeloQueServe.value
      ? { ...guardadas.value, templateId: null }
      : guardadas.value
  );
  const ligadas = computed(() => disponivel.value && versoes.value.ligado);

  const primeira = computed(() => ({
    texto: draft.value.messageBody || '',
    templateId: draft.value.templateId,
    assunto: emailCampaign.value?.subject || '',
  }));
  const motivo = computed(() =>
    ligadas.value
      ? motivoDaSegunda(canal.value, versoes.value, primeira.value)
      : null
  );
  const pronta = computed(() => motivo.value === null);

  const regra = computed(() => ({
    criterio: versoes.value.criterio,
    divisao: versoes.value.divisao,
    espera: versoes.value.espera,
  }));
  // O "Vão receber" sem o grupo de controle (o mesmo arredondamento do servidor, CampaignJourney::GrupoDeControle).
  const publico = computed(() => {
    const recebem = preview.value?.receive ?? reach.value;
    return (
      recebem - Math.floor((recebem * (draft.value.grupoDeControle || 0)) / 100)
    );
  });
  const plano = computed(
    () =>
      preview.value?.duas_versoes ||
      planoDoTeste(publico.value, { divisao: regra.value.divisao })
  );

  // O que a revisão mostra de cada versão: o texto, o nome do modelo ou o assunto.
  const resumo = computed(() => {
    if (ehOficial.value)
      return [
        rotuloDe(draft.value.templateId) || template.value?.name || '',
        modeloQueServe.value?.label || '',
      ];
    if (ehEmail.value) return [primeira.value.assunto, versoes.value.assunto];
    return [primeira.value.texto, versoes.value.texto];
  });

  const email = computed(() => ({
    sugestoes: emailCampaign.value?.ai_subject_variants || [],
    remetente:
      emailCampaign.value?.from_name || emailCampaign.value?.from_email || '',
    previa: emailCampaign.value?.preheader || '',
  }));

  const mudar = novas => update({ duasVersoes: novas });

  return {
    disponivel,
    versoes,
    ligadas,
    primeira,
    modelos,
    modeloDaSegunda,
    motivo,
    pronta,
    regra,
    publico,
    plano,
    resumo,
    email,
    mudar,
  };
};
