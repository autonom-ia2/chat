import { frontendURL } from '../../../helper/URLHelper';
import FirstSteps from 'dashboard/components-next/onboarding/FirstSteps.vue';

// Trilha de onboarding (épico #485): a tela fica acessível a qualquer momento,
// não só enquanto a conta é nova.
export const routes = [
  {
    path: frontendURL('accounts/:accountId/primeiros-passos'),
    name: 'onboarding_first_steps',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: FirstSteps,
  },
];

export default { routes };
