// Ajudantes dos specs de resultados (#677): card do lead, lote e CSV.
import { leadCard } from './searchPageHarness';

export const ADDRESS_SEPARATOR = 'PROSPECTING.SEARCH.ADDRESS_SEPARATOR';

export const leadCheckbox = (wrapper, name) =>
  leadCard(wrapper, name).find('input[type="checkbox"]');

export const linkWithText = (element, text) =>
  element.findAll('a').find(link => link.text().trim() === text);

export const readBlob = blob =>
  new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsText(blob);
  });

export const captureCsvDownload = () => {
  const download = { blob: null, fileName: null, clicks: 0 };
  URL.createObjectURL = vi.fn(blob => {
    download.blob = blob;
    return 'blob:csv';
  });
  URL.revokeObjectURL = vi.fn();
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
    function captureClick() {
      download.fileName = this.download;
      download.clicks += 1;
    }
  );
  return download;
};
