// Exportação dos leads da busca pelo servidor (#682), em CSV ou Excel, com as
// colunas do Orth (empresa, decisor, nota e faixa). A tela manda os mesmos
// leads que exportava antes: os selecionados ou, sem seleção, os visíveis
// depois do filtro, na ordem em que aparecem.
import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';

const saveFile = (blob, fileName) => {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(link.href);
};

export const useLeadExport = (state, t) => {
  const { selectedLeadObjects, sortedLeads, selectedSearchId } = state;
  const isExporting = ref(false);

  const exportLeads = async format => {
    const rows = selectedLeadObjects.value.length
      ? selectedLeadObjects.value
      : sortedLeads.value;
    isExporting.value = true;
    try {
      const { data } = await AutonomiaProspectingAPI.exportSearch(
        selectedSearchId.value,
        { format, leadIds: rows.map(lead => lead.id) }
      );
      saveFile(data, `prospeccao-${selectedSearchId.value}.${format}`);
    } catch {
      useAlert(t('PROSPECTING.SEARCH.EXPORT_ERROR'));
    } finally {
      isExporting.value = false;
    }
  };

  return { exportLeads, isExporting };
};
