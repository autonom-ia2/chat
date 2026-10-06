import { onActivated, onMounted } from 'vue';

// Campaign pages live under a <keep-alive> router view (CampaignsPageRouteView), so a
// page left and opened again is reactivated, not mounted. `callback` runs once on the
// first mount and again on every later return, so each visit starts from the current
// route and data. Inside keep-alive, Vue also fires onActivated right after the first
// mount; that one is skipped.
export function useOnEnter(callback) {
  let skipNextActivation = false;
  onMounted(() => {
    skipNextActivation = true;
    callback();
  });
  onActivated(() => {
    if (skipNextActivation) {
      skipNextActivation = false;
      return;
    }
    callback();
  });
}
