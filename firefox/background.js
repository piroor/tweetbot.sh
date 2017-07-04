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
  let url = aInfo.linkUrl || aInfo.pageUrl || aTab.url;
  log('procesing url = ' + url);

  let id = detectStatusId(url);
  if (!id) {
    log('not a tweet');
    return;
  }
  log('processing id = ' + id);

  switch (aInfo.menuItemId) {
    case 'fav':
      send_dm('fav', id).then(onResponse, onError);
      break;
    case 'rt':
      send_dm('rt', id).then(onResponse, onError);
      break;
    case 'rt-now':
      send_dm('rt!', id).then(onResponse, onError);
      break;
    case 'fav-and-rt':
      send_dm('fr', id).then(onResponse, onError);
      break;
    case 'fav-and-rt-now':
      send_dm('fr!', id).then(onResponse, onError);
      break;
  }
});

function detectStatusId(aUrl) {
  let match = aUrl.match(/^[^:]+:\/\/(?:[^/]*\.)?twitter.com\/(?:[^\/]+|i\/web)\/status\/([\d]+)/);
  return match ? match[1] : null;
}

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

