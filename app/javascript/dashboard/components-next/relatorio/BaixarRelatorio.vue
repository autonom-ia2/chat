<script setup>
import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useCrmPermissions } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';

// "Baixar relatório" comum (Anúncios #1960, Números › Origens #2001): um botão abre a escolha entre PDF (para
// mostrar ou mandar) e planilha (para trabalhar os números); "Baixar" pede o arquivo ao servidor, que monta com os
// mesmos números da tela. As listas de pessoas só vão no arquivo de quem pode exportar o CRM (crm_export, dado
// pessoal em lote); o diálogo avisa quem não pode. Cada tela passa os textos e como pedir o arquivo.
const props = defineProps({
  // { botao, titulo, descricao, confirmar, pdfTitulo, pdfDica, planilhaTitulo, planilhaDica, erro, semPessoas,
  //   comPessoas? } — comPessoas é opcional: sem ele, quem pode exportar não vê frase nenhuma.
  textos: { type: Object, required: true },
  // (formato: 'pdf' | 'planilha') => Promise<{ data: Blob, headers }>
  pedir: { type: Function, required: true },
  // Nome do arquivo quando o servidor não manda (formato => nome).
  nomeReserva: { type: Function, required: true },
});
// Os atributos (data-*) vão para o botão, não para o diálogo.
defineOptions({ inheritAttrs: false });

const { canExportCrm } = useCrmPermissions();
const dialog = ref(null);
const formato = ref('pdf');
const baixando = ref(false);

const REVOGAR_EM_MS = 60_000;

const OPCOES = [
  {
    key: 'pdf',
    icon: 'i-lucide-file-text',
    titulo: 'pdfTitulo',
    dica: 'pdfDica',
  },
  {
    key: 'planilha',
    icon: 'i-lucide-file-spreadsheet',
    titulo: 'planilhaTitulo',
    dica: 'planilhaDica',
  },
];

// "attachment; filename=\"anuncios-2026-10-20.pdf\"; filename*=..." → o nome entre aspas.
const nomeDoArquivo = (headers, reserva) => {
  const parte = String(headers?.['content-disposition'] || '')
    .split(';')
    .map(item => item.trim())
    .find(item => item.startsWith('filename="'));
  return parte ? parte.slice('filename="'.length, -1) : reserva;
};

const salvar = (blob, nome) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.setAttribute('href', url);
  link.setAttribute('download', nome);
  link.click();
  // Revogar na hora cancela o download no Safari: espera o navegador pegar o arquivo.
  setTimeout(() => URL.revokeObjectURL(url), REVOGAR_EM_MS);
};

const abrir = () => dialog.value?.open();
const fechar = () => dialog.value?.close();

const baixar = async () => {
  if (baixando.value) return;
  baixando.value = true;
  try {
    const { data, headers } = await props.pedir(formato.value);
    salvar(data, nomeDoArquivo(headers, props.nomeReserva(formato.value)));
    fechar();
  } catch {
    useAlert(props.textos.erro);
  } finally {
    baixando.value = false;
  }
};
</script>

<template>
  <Button
    v-bind="$attrs"
    icon="i-lucide-download"
    :label="textos.botao"
    slate
    faded
    class="!min-h-11 !rounded-xl"
    @click="abrir"
  />
  <Dialog
    ref="dialog"
    :title="textos.titulo"
    :description="textos.descricao"
    :confirm-button-label="textos.confirmar"
    :is-loading="baixando"
    @confirm="baixar"
  >
    <slot :fechar="fechar" />
    <div
      role="group"
      :aria-label="textos.titulo"
      class="grid gap-3 sm:grid-cols-2"
    >
      <button
        v-for="opcao in OPCOES"
        :key="opcao.key"
        type="button"
        :data-report-format="opcao.key"
        :aria-pressed="String(formato === opcao.key)"
        class="flex items-start gap-3 p-4 text-start bg-n-solid-1 border-0 rounded-xl min-h-11 ring-1 ring-inset focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
        :class="
          formato === opcao.key
            ? 'ring-2 ring-n-brand bg-n-blue-2'
            : 'ring-n-weak hover:ring-n-strong'
        "
        @click="formato = opcao.key"
      >
        <span
          class="flex items-center justify-center flex-none rounded-lg size-10 bg-n-alpha-1 text-n-slate-12"
          aria-hidden="true"
        >
          <span :class="opcao.icon" class="size-5" />
        </span>
        <span class="flex flex-col min-w-0 gap-1">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ textos[opcao.titulo] }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ textos[opcao.dica] }}
          </span>
        </span>
      </button>
    </div>
    <p
      v-if="!canExportCrm"
      data-report-no-people
      class="mt-3 text-sm text-n-slate-11"
    >
      {{ textos.semPessoas }}
    </p>
    <p
      v-else-if="textos.comPessoas"
      data-report-people
      class="mt-3 text-sm text-n-slate-11"
    >
      {{ textos.comPessoas }}
    </p>
  </Dialog>
</template>
