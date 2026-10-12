import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import api from '../api/modelosWhatsapp';
import {
  CAMPOS_DO_PUBLICO,
  ligacaoDoCatalogo,
  rotuloDoCampo,
} from '../helpers/campos';
import { podeIrEmCampanha } from '../helpers/paraMeta';

// Ponte Modelos ↔ Campanha (auditoria de campanhas, §6; PRD §7). Com a flag
// whatsapp_templates_journey ligada, a Nova campanha pega daqui as caixas do
// WhatsApp oficial (inclusive as que precisam reconectar, desativadas), os
// modelos com nome amigável e situação (o "em análise" também, para agendar) e
// as variáveis já ligadas pelo catálogo de campos (#1331). O modelo que vai para
// a campanha é o mesmo que a Meta devolveu (`modelo.template`), nunca uma cópia
// remontada. Desligada — ou sem permissão para ver os modelos —, nada muda na
// campanha.
export function useModelosNaCampanha() {
  const { t } = useI18n();
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );

  const flagLigada = computed(() =>
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY
    )
  );
  // A ponte só liga depois de ler os modelos: quem não pode vê-los (a API
  // recusa) segue com a campanha de sempre.
  const lida = ref(false);
  const ativa = computed(() => flagLigada.value && lida.value);
  const caixas = ref([]);
  const modelos = ref([]);

  const carregar = async () => {
    if (!flagLigada.value) return;
    try {
      const [listaDeCaixas, listaDeModelos] = await Promise.all([
        api.listarCaixasDaCampanha(),
        api.listarModelos(),
      ]);
      caixas.value = listaDeCaixas;
      modelos.value = listaDeModelos;
      lida.value = true;
    } catch {
      lida.value = false;
    }
  };

  // A conta (e a flag) pode chegar depois da tela: carrega quando a flag liga.
  watch(flagLigada, ligada => {
    if (ligada && !lida.value) carregar();
  });

  const caixa = id => caixas.value.find(item => item.id === Number(id));
  const temCaixaConectada = computed(() =>
    caixas.value.some(item => item.situacao === 'conectada')
  );

  // Caixa que precisa reconectar aparece desativada, com o motivo.
  const opcoesDeCaixa = computed(() =>
    caixas.value.map(item => ({
      value: item.id,
      label:
        item.situacao === 'conectada'
          ? item.nome
          : t('MODELOS_WHATSAPP.PONTE.CAIXA_RECONECTAR', { nome: item.nome }),
      disabled: item.situacao !== 'conectada',
    }))
  );
  const caixasParaReconectar = computed(() =>
    caixas.value.filter(item => item.situacao !== 'conectada')
  );

  const modeloPorId = id =>
    (ativa.value && modelos.value.find(modelo => modelo.id === String(id))) ||
    null;

  // Modelos da conta do WhatsApp da caixa (o modelo vale para todas as caixas
  // da mesma conta).
  const modelosDaCaixa = inboxId => {
    const escolhida = caixa(inboxId);
    if (!escolhida) return [];
    return modelos.value.filter(modelo => modelo.conta === escolhida.conta.id);
  };

  const motivoDeNaoUsar = modelo => {
    if (!podeIrEmCampanha(modelo)) return 'FORMATO_NAO_VAI';
    if (modelo.situacao === 'recusado') return 'RECUSADO';
    if (modelo.situacao === 'pausado') return 'PAUSADO';
    if (modelo.situacao === 'desativado') return 'DESATIVADO';
    return '';
  };

  // O modelo como a Meta devolveu, com o id da Meta (o mesmo de `?modelo=`).
  const templates = inboxId =>
    modelosDaCaixa(inboxId).map(modelo => modelo.template);

  const opcoesDeModelo = inboxId =>
    modelosDaCaixa(inboxId).map(modelo => {
      const motivo = motivoDeNaoUsar(modelo);
      const extra = motivo
        ? t(`MODELOS_WHATSAPP.PONTE.NAO_VAI.${motivo}`)
        : modelo.situacao === 'em_analise' &&
          t('MODELOS_WHATSAPP.SITUACOES.em_analise.ROTULO');
      return {
        value: modelo.id,
        label: extra ? `${modelo.nome} · ${extra}` : modelo.nome,
        disabled: Boolean(motivo),
      };
    });

  // Variáveis com campo do catálogo que um Público preenche (cliente.primeiro_nome,
  // minha_empresa.nome…) já vêm ligadas a ele. As demais a pessoa escolhe.
  const ligacoesIniciais = templateId => {
    const modelo = modeloPorId(templateId);
    if (!modelo) return {};
    return Object.fromEntries(
      Object.entries(modelo.campos || {}).flatMap(([chave, campo]) => {
        const ligacao = ligacaoDoCatalogo(campo);
        return ligacao ? [[chave, ligacao]] : [];
      })
    );
  };

  // A variável do corpo ganha o nome do campo ("Data") no lugar de {{2}}.
  const rotular = (variaveis, templateId) => {
    const modelo = modeloPorId(templateId);
    if (!modelo) return variaveis;
    return variaveis.map(variavel =>
      variavel.part === 'body' && modelo.campos?.[variavel.variable]
        ? {
            ...variavel,
            label: rotuloDoCampo(t, modelo.campos[variavel.variable]),
            friendly: true,
          }
        : variavel
    );
  };

  // "De onde vem" ganha o grupo dos campos do catálogo que um Público preenche.
  const gruposDeCampos = computed(() =>
    ativa.value
      ? [
          {
            label: t('MODELOS_WHATSAPP.PONTE.GRUPO_CATALOGO'),
            options: CAMPOS_DO_PUBLICO.map(chave => ({
              value: `field:${chave}`,
              label: rotuloDoCampo(t, chave),
            })),
          },
        ]
      : []
  );

  const emAnalise = templateId =>
    modeloPorId(templateId)?.situacao === 'em_analise';

  return {
    ativa,
    flagLigada,
    carregar,
    caixas,
    temCaixaConectada,
    opcoesDeCaixa,
    caixasParaReconectar,
    modeloPorId,
    templates,
    opcoesDeModelo,
    ligacoesIniciais,
    rotular,
    gruposDeCampos,
    emAnalise,
  };
}
