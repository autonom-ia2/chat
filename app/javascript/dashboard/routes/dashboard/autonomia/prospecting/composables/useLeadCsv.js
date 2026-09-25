// Exportação CSV dos leads (selecionados ou todos os visíveis). As colunas
// saem de CSV_COLUMNS, na ordem do objeto: cada frente acrescenta a sua
// coluna com o próprio leitor, sem mexer na montagem do arquivo.
import { formatLeadAddress } from '../utils/searchFormatters';

const plainValue = key => lead => lead[key] || '';

const CSV_COLUMNS = {
  name: plainValue('name'),
  phone: plainValue('phone'),
  website: plainValue('website'),
  address: (lead, t) => formatLeadAddress(lead, t),
  status: plainValue('status'),
  source: lead => lead.source_label || lead.provider,
};

const csvCell = value => `"${String(value).replaceAll('"', '""')}"`;

export const useLeadCsv = (state, t) => {
  const { selectedLeadObjects, sortedLeads, selectedSearchId } = state;

  const exportCsv = () => {
    const rows = selectedLeadObjects.value.length
      ? selectedLeadObjects.value
      : sortedLeads.value;
    const header = Object.keys(CSV_COLUMNS);
    const csvRows = rows.map(lead =>
      header.map(key => csvCell(CSV_COLUMNS[key](lead, t))).join(',')
    );
    const blob = new Blob([[header.join(','), ...csvRows].join('\n')], {
      type: 'text/csv;charset=utf-8;',
    });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `prospeccao-${selectedSearchId.value || 'leads'}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
  };

  return { exportCsv };
};
