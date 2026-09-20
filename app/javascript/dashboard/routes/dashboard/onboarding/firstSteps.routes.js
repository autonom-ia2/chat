import { frontendURL } from '../../../helper/URLHelper';
import FirstSteps from 'dashboard/components-next/onboarding/FirstSteps.vue';

// Trilha de onboarding (épico #485): a tela fica acessível a qualquer momento,
// não só enquanto a conta é nova. Só administrador: é ele quem configura a conta,
// e só ele vê a entrada no menu e na tela inicial. Sem isto, um agente abriria a
// tela pela URL e veria uma lista que não pode executar.
export const routes = [
  {
    path: frontendURL('accounts/:accountId/primeiros-passos'),
    name: 'onboarding_first_steps',
    meta: {
      permissions: ['administrator'],
    },
    component: FirstSteps,
  },
];

export default { routes };
