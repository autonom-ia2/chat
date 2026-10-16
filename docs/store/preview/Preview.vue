<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import StoreCatalogPage from 'dashboard/routes/dashboard/financial/pages/StoreCatalogPage.vue';
import PanelStore from 'dashboard/routes/dashboard/autonomia/components/panel/PanelStore.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
const store = useStore();
const panel = ref(false);
const role = computed({
  get: () => store.state.type,
  set: value => store.commit('role', value),
});
const roles = [
  { value: 'SuperAdmin', label: 'Superadmin' },
  { value: 'User', label: 'Administrador da conta' },
];
</script>

<template>
  <div class="flex h-dvh min-w-0 bg-n-surface-1 text-n-slate-12">
    <aside class="hidden w-56 p-4 border-r border-n-weak md:block bg-n-solid-2">
      <h1 class="text-xl font-semibold">Chat2You</h1>
      <div class="mt-8 space-y-3 text-sm">
        <div>Financeiro</div>
        <button
          v-if="role === 'SuperAdmin'"
          class="block w-full py-2 text-left text-n-blue-11"
          @click="panel = false"
        >
          Loja
        </button>
        <div>Assinatura</div>
        <div>Faturas</div>
      </div>
    </aside>
    <div class="flex flex-col flex-1 min-w-0">
      <header
        class="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-n-weak"
      >
        <ChoiceSelect
          v-model="role"
          :options="roles"
          aria-label="Perfil de validação"
        />
        <button
          v-if="role === 'SuperAdmin'"
          class="text-sm text-n-blue-11"
          @click="panel = !panel"
        >
          {{ panel ? 'Catálogo' : 'Publicação do agente' }}
        </button>
      </header>
      <section
        v-if="panel && role === 'SuperAdmin'"
        class="flex-1 min-w-0 p-4 overflow-auto md:p-8"
      >
        <PanelStore :agent-id="10" />
      </section>
      <StoreCatalogPage v-else class="flex-1" />
    </div>
  </div>
</template>
