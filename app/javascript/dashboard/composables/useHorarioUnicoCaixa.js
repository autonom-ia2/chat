import { computed, getCurrentInstance } from 'vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { fusoDaConta, rotuloDoFuso } from 'dashboard/helper/fusoDaConta';

// #1619 — com a flag de conta `horario_unico_caixa`, o horário do canal (inbox.working_hours) é a
// única fonte do horário da caixa e vale no fuso da conta. `fuso` é o rótulo de Configurações
// (rotuloDoFuso), nunca o nome longo do navegador nem um fuso fixo; `fusoIana` é o nome para gravar.
// A store vem da instância (como no useStore), lida com cuidado: montado sem a store do painel, o
// componente lê a flag como desligada e a tela fica como sem a flag.
export function useHorarioUnicoCaixa() {
  const instancia = getCurrentInstance();
  const getter = nome => instancia?.proxy?.$store?.getters?.[nome];

  const conta = computed(() =>
    getter('accounts/getAccount')?.(getter('getCurrentAccountId'))
  );
  const ligado = computed(() =>
    Boolean(
      getter('accounts/isFeatureEnabledonAccount')?.(
        getter('getCurrentAccountId'),
        FEATURE_FLAGS.HORARIO_UNICO_CAIXA
      )
    )
  );
  const fusoIana = computed(() => fusoDaConta(conta.value));
  const fuso = computed(() => rotuloDoFuso(fusoIana.value));

  return { ligado, fuso, fusoIana };
}
