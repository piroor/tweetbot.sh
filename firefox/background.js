var menuItems = [
  'fav',
  'rt',
  'rt-now',
  'fav-and-rt',
  'fav-and-rt-now'
];

function installMenuItems() {
  for (let id of menuItems)
  {
    browser.contextMenus.create({
      id: id,
      title: browser.i18n.getMessage('contextMenu.' + id + '.label'),
      contexts: ['page', 'tab', 'link']
    });
  }
}

installMenuItems();

browser.contextMenus.onClicked.addListener(function(aInfo, aTab) {
  let url = aInfo.linkUrl;
  log('procesing url = ' + url);
  switch (aInfo.menuItemId) {
    case 'fav':
      send_dm('fav', url).then(onResponse, onError);
      break;
    case 'rt':
      send_dm('rt', url).then(onResponse, onError);
      break;
    case 'rt-now':
      send_dm('rt!', url).then(onResponse, onError);
      break;
    case 'fav-and-rt':
      send_dm('fr', url).then(onResponse, onError);
      break;
    case 'fav-and-rt-now':
      send_dm('fr!', url).then(onResponse, onError);
      break;
  }
});

function send_dm(...aArgs) {
  return browser.runtime.sendNativeMessage('com.add0n.node', {
    cmd: 'exec',
    command: configs.tweetsh_path,
    arguments: [
      'dm',
      configs.target_account,
      aArgs.join(' ')
    ]
  })
}

function onResponse(aResponse) {
  log('Received: ' + aResponse);
}

function onError(aError) {
  log('Error: ' + aError);
}

