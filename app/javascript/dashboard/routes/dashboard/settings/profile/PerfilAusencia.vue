<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import authAPI from 'dashboard/api/auth';
import Button from 'dashboard/components-next/button/Button.vue';
import CampoAusenteAte from 'dashboard/components/ausencia/CampoAusenteAte.vue';

// #2414 G23 (#2737) — a própria pessoa marca até quando fica ausente nesta conta (POST /profile/ausencia, só a conta
// dela, como a disponibilidade). Na Equipe, quem cuida das pessoas marca a dos outros.
const store = useStore();
const { t } = useI18n();
const usuario = useMapGetter('getCurrentUser');
const contaId = useMapGetter('getCurrentAccountId');

const salva = computed(
  () =>
    (usuario.value?.accounts || []).find(conta => conta.id === contaId.value)
      ?.ausente_ate ?? null
);
const ausenteAte = ref(salva.value);
watch(salva, valor => {
  ausenteAte.value = valor;
});

const salvando = ref(false);
const salvar = async () => {
  salvando.value = true;
  try {
    const { data } = await authAPI.updateAusencia(
      contaId.value,
      ausenteAte.value
    );
    await store.dispatch('setCurrentUser', data);
    useAlert(t('AUSENCIA.PERFIL.SALVO'));
  } catch {
    useAlert(t('AUSENCIA.PERFIL.ERRO'));
  } finally {
    salvando.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-3" data-perfil-ausencia>
    <CampoAusenteAte v-model="ausenteAte" />
    <Button
      data-ausencia-salvar
      type="button"
      class="w-fit"
      :label="t('AUSENCIA.PERFIL.SALVAR')"
      :is-loading="salvando"
      :disabled="salvando || ausenteAte === salva"
      @click="salvar"
    />
  </div>
</template>
