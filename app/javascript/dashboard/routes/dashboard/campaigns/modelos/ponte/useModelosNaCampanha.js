import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import api from '../api/modelosWhatsapp';
import { paraTemplateDaMeta, podeIrEmCampanha } from '../helpers/paraMeta';

// Ponte Modelos ↔ Campanha (auditoria de campanhas, §6). Com a flag
// whatsapp_templates_journey ligada, a Nova campanha pega daqui as caixas do
// WhatsApp oficial (inclusive as que precisam reconectar, desativadas), os
// modelos com nome amigável e situação (o "em análise" também, para agendar) e
// as ligações automáticas das variáveis. Desligada, nada muda na campanha.
// Os dados vêm de api/modelosWhatsapp.js (hoje, o adaptador falso).
const CAMPO_DO_CONTATO = { nome_cliente: 'first_name' };

export function useModelosNaCampanha() {
  const { t } = useI18n();
  const { currentAccount } = useAccount();
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter(
    'accounts/isFeatureEnabledonAccount'
  );

  const ativa = computed(() =>
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.WHATSAPP_TEMPLATES_JOURNEY
    )
  );
  const caixas = ref([]);
  const modelos = ref([]);

  const carregar = async () => {
    if (!ativa.value) return;
    const [listaDeCaixas, listaDeModelos] = await Promise.all([
      api.listarCaixasDaCampanha(),
      api.listarModelos(),
    ]);
    caixas.value = listaDeCaixas;
    modelos.value = listaDeModelos;
  };

  // A conta (e a flag) pode chegar depois da tela: carrega quando a ponte liga.
  watch(ativa, ligada => {
    if (ligada && !caixas.value.length) carregar();
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
    modelos.value.find(modelo => modelo.id === String(id)) || null;

  // Modelos da conta do WhatsApp da caixa (o modelo vale para todas as caixas
  // da mesma conta).
  const modelosDaCaixa = inboxId => {
    const escolhida = caixa(inboxId);
    if (!escolhida) return [];
    return modelos.value.filter(modelo => modelo.conta === escolhida.conta.id);
  };

  const motivoDeNaoUsar = modelo => {
    if (!podeIrEmCampanha(modelo)) return 'FORMATO_NAO_VAI';
    if (['recusado', 'pausado'].includes(modelo.situacao)) {
      return modelo.situacao === 'recusado' ? 'RECUSADO' : 'PAUSADO';
    }
    return '';
  };

  const templates = inboxId =>
    modelosDaCaixa(inboxId).map(modelo => paraTemplateDaMeta(modelo).template);

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

  // "Nome do cliente" → primeiro nome do contato; "Nome da empresa" → nome da
  // conta no Chat2You, como texto fixo. Os demais ficam para a pessoa escolher.
  const ligacoesIniciais = templateId => {
    const modelo = ativa.value && modeloPorId(templateId);
    if (!modelo) return {};
    const { campos } = paraTemplateDaMeta(modelo);
    return Object.fromEntries(
      Object.entries(campos).flatMap(([chave, campo]) => {
        if (CAMPO_DO_CONTATO[campo]) {
          return [
            [
              chave,
              {
                source: 'contact',
                value: CAMPO_DO_CONTATO[campo],
                suggested: true,
              },
            ],
          ];
        }
        if (campo === 'nome_empresa') {
          return [
            [
              chave,
              {
                source: 'fixed',
                value: currentAccount.value?.name || '',
                suggested: true,
              },
            ],
          ];
        }
        return [];
      })
    );
  };

  // A variável do corpo ganha o nome da etiqueta ("Data") no lugar de {{2}}.
  const rotular = (variaveis, templateId) => {
    const modelo = ativa.value && modeloPorId(templateId);
    if (!modelo) return variaveis;
    const { campos } = paraTemplateDaMeta(modelo);
    return variaveis.map(variavel =>
      variavel.part === 'body' && campos[variavel.variable]
        ? {
            ...variavel,
            label: t(
              `MODELOS_WHATSAPP.CAMPOS.${campos[variavel.variable]}.ROTULO`
            ),
            friendly: true,
          }
        : variavel
    );
  };

  const emAnalise = templateId =>
    modeloPorId(templateId)?.situacao === 'em_analise';

  return {
    ativa,
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
    emAnalise,
  };
}
