// #3075 — as definições dos campos personalizados da conta e o que o
// configurador de campos (components-next/Relationships/FieldConfigurator.vue)
// pôs na ficha. Nenhuma leitura nova:
//  - as definições vêm do store (`attributes`), que o menu do painel carrega
//    ao abrir; o configurador as atualiza lá quando cria ou muda um campo;
//  - a escolha da ficha é a área `contact_details` (a mesma da ficha antiga),
//    lida por useRelationships, só na conta com as chaves
//    `relationships_attributes` e `custom_attributes` (sem elas não há
//    configurador). `comConfiguracao` falso (a lista) não a lê: lá os campos
//    aparecem pela ordem da conta.
// `podeEscolher`: quem pode mudar os campos da ficha ("Escolher campos"), a
// mesma regra do botão "Configurar" da ficha antiga (can_manage do servidor).
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useRelationships } from 'dashboard/composables/useRelationships';
import { selectDefinitions } from 'dashboard/components-next/Relationships/presentation';

const AREA_DA_FICHA = 'contact_details';
const MODELO = 'contact_attribute';

const daConfiguracao = () => {
  const { attributesEnabled, state } = useRelationships();
  const escolhidos = computed(() =>
    selectDefinitions(
      state.value.definitions,
      state.value.configuration,
      AREA_DA_FICHA
    ).map(definicao => definicao.id)
  );
  const podeEscolher = computed(
    () => attributesEnabled.value && Boolean(state.value.can_manage)
  );
  return { escolhidos, podeEscolher };
};

const semConfiguracao = () => ({
  escolhidos: computed(() => []),
  podeEscolher: computed(() => false),
});

export const useCamposDaConta = ({ comConfiguracao = true } = {}) => {
  // Todas as da conta, já sem as internas da WAHA; aqui ficam as da pessoa.
  const daConta = useMapGetter('attributes/getAttributes');
  const definicoes = computed(() =>
    (daConta.value ?? []).filter(
      definicao => definicao.attribute_model === MODELO
    )
  );
  const { isCloudFeatureEnabled } = useAccount();
  const comConfigurador =
    comConfiguracao &&
    isCloudFeatureEnabled(FEATURE_FLAGS.RELATIONSHIPS_ATTRIBUTES) &&
    isCloudFeatureEnabled(FEATURE_FLAGS.CUSTOM_ATTRIBUTES);
  const { escolhidos, podeEscolher } = comConfigurador
    ? daConfiguracao()
    : semConfiguracao();
  return { definicoes, escolhidos, podeEscolher };
};
