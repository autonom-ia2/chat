// #3101 — a ligação do "Mandar de novo" com a Nova campanha (§3.1 do desenho): o que a revisão (StepReview → prop
// `reenvio`) precisa e a segunda mensagem do WhatsApp Oficial no formato do servidor. As telas continuam só com props;
// esta peça monta.
//
// Os modelos da segunda mensagem são os da caixa que o passo 2 oferece (o mesmo nome amigável; o que não vai, apagado),
// menos o modelo da primeira. De cada um:
// - `variaveis`: as do modelo, rotuladas pela ponte de Modelos, como no passo 2;
// - `ligacoes`: as do catálogo (ponte.ligacoesIniciais) e, para a variável de mesmo nome na primeira mensagem (a mesma
//   chave e o mesmo rótulo), a ligação que a primeira usa;
// - `corpo`: o texto do modelo com a primeira pessoa do público, com as ligações que valem agora ("Como o cliente vê").
// Um modelo com cupom, oferta com prazo, carrossel ou catálogo (`pedeOferta`) fica apagado: pede o que a revisão do
// reenvio não tem (o servidor recusa também: reenvio_modelo_com_oferta).
import { computed } from 'vue';
import { CAMPAIGN_CHANNELS } from '../campaignChannels';
import {
  buildTemplateParams,
  previewMessage,
  templateVariables,
} from '../templateVariables';
import { MAXIMO_DO_TEXTO, mensagemDoCanal } from './reenvio';

const semSugestao = ligacao =>
  ligacao ? { source: ligacao.source, value: ligacao.value } : ligacao;

// `draft`: o rascunho. `ponte`: a ponte de Modelos (rotular, ligacoesIniciais, gruposDeCampos). `templates` e
// `templateOptions`: os modelos da caixa e as opções do passo 2. `variables`: as variáveis da primeira mensagem (já
// rotuladas). `sample`: a primeira pessoa do público. `columns`: as colunas do público. `placeholder(ligacao)`: o texto
// no lugar de um valor que falta. `pedeOferta(modelo)` e `motivoDaOferta`: o modelo que não vai e o porquê.
export const useReenvioNaCampanha = ({
  draft,
  ponte,
  templates,
  templateOptions,
  variables,
  sample,
  columns,
  placeholder,
  pedeOferta = () => false,
  motivoDaOferta = '',
}) => {
  const modeloPorId = id => templates.value.find(item => item.id === id);

  // A ligação da primeira mensagem vale para a variável de mesma chave e mesmo rótulo no segundo modelo.
  const ligacoesDaPrimeira = variaveis => {
    const primeiras = new Map(
      variables.value.map(variavel => [variavel.key, variavel.label])
    );
    return Object.fromEntries(
      variaveis
        .filter(
          ({ key, label }) =>
            primeiras.get(key) === label && draft.value.bindings?.[key]
        )
        .map(({ key }) => [key, semSugestao(draft.value.bindings[key])])
    );
  };

  const modeloDaOpcao = opcao => {
    const template = modeloPorId(opcao.value);
    if (!template) return null;
    const variaveis = ponte.rotular(templateVariables(template), template.id);
    const ligacoes = {
      ...ligacoesDaPrimeira(variaveis),
      ...ponte.ligacoesIniciais(template.id),
    };
    const escolhido = draft.value.reenvio?.modeloId === opcao.value;
    const comOferta = pedeOferta(template);
    return {
      value: opcao.value,
      label: comOferta ? `${opcao.label} · ${motivoDaOferta}` : opcao.label,
      disabled: Boolean(opcao.disabled) || comOferta,
      variaveis,
      ligacoes,
      corpo: previewMessage({
        template,
        bindings: escolhido ? draft.value.reenvio.ligacoes || {} : ligacoes,
        sample: sample.value,
        placeholder,
      }),
    };
  };

  const modelos = computed(() =>
    draft.value.channel === CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL
      ? templateOptions.value
          .filter(opcao => opcao.value !== draft.value.templateId)
          .map(modeloDaOpcao)
          .filter(Boolean)
      : []
  );

  // A prop `reenvio` do StepReview; null num canal sem reenvio (chat ao vivo).
  const reenvio = computed(() =>
    mensagemDoCanal(draft.value.channel)
      ? {
          canal: draft.value.channel,
          modelos: modelos.value,
          colunas: columns.value,
          gruposDeCampos: ponte.gruposDeCampos.value,
          maximoDoTexto: MAXIMO_DO_TEXTO,
        }
      : null
  );

  // WhatsApp Oficial: a segunda mensagem como o servidor guarda (CampaignJourney::Reenvio::Modelo), com o mesmo
  // buildTemplateParams da primeira. null sem modelo escolhido.
  const modeloParaEnvio = () => {
    const escolha = draft.value.reenvio;
    const template = escolha?.modeloId ? modeloPorId(escolha.modeloId) : null;
    if (!template) return null;
    const ligacoes = escolha.ligacoes || {};
    return {
      modelo_id: template.id,
      template_params: buildTemplateParams({ template, bindings: ligacoes }),
      ligacoes: Object.fromEntries(
        templateVariables(template).map(({ key }) => [
          key,
          semSugestao(ligacoes[key]),
        ])
      ),
    };
  };

  return { reenvio, modeloParaEnvio };
};
