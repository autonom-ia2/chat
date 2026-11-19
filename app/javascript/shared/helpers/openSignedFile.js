// Open synchronously in the click so browsers do not block the tab after the authenticated request.
// The short-lived link is requested only when opening, never cached in component/store state.
export const openSignedFile = async (requestLink, browserWindow = window) => {
  const tab = browserWindow.open('', '_blank');
  if (tab) tab.opener = null;
  try {
    const link = await requestLink();
    if (tab) tab.location.replace(link);
    else browserWindow.location.assign(link);
    return null;
  } catch (error) {
    tab?.close();
    return error;
  }
};
