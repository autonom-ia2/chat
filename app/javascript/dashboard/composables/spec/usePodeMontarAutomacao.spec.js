import { ref } from 'vue';
import { usePodeMontarAutomacao } from '../usePodeMontarAutomacao';

let flagLigada = false;
const temAChave = ref(false);
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flag === 'automacao_fundacao' && flagLigada,
  }),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => temAChave,
}));

describe('usePodeMontarAutomacao', () => {
  it('sem a flag, monta como antes, mesmo sem a chave', () => {
    flagLigada = false;
    temAChave.value = false;

    expect(usePodeMontarAutomacao().value).toBe(true);
  });

  it('com a flag e sem a chave, não monta', () => {
    flagLigada = true;
    temAChave.value = false;

    expect(usePodeMontarAutomacao().value).toBe(false);
  });

  it('com a flag e a chave, monta', () => {
    flagLigada = true;
    temAChave.value = true;

    expect(usePodeMontarAutomacao().value).toBe(true);
  });
});
