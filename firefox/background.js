browser.contextMenus.create({
  id: 'dm',
  title: browser.i18n.getMessage('contextMenu.dm.label'),
  contexts: ['link']
});

browser.contextMenus.onClicked.addListener(function(aInfo, aTab) {
  switch (aInfo.menuItemId) {
    case 'dm':
      console.log('URL:' + aInfo.linkUrl);
      break;
  }
})
