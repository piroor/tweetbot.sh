var menuItems = [
  'fav',
  'rt',
  'fav-and-rt',
  '--separator-now--',
  'rt-now',
  'fav-and-rt-now'
];

function installMenuItems() {
  for (let id of menuItems)
  {
    let isSeparator = id.charAt(0) == '-';
     browser.contextMenus.create({
      id: id,
      type: isSeparator ? 'separator' : 'normal',
      title: isSeparator ? null : browser.i18n.getMessage('contextMenu.' + id + '.label'),
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
    notify(
      browser.i18n.getMessage('notTweetError.title'),
      browser.i18n.getMessage('notTweetError.message', url)
    );
    log('not a tweet');
    return;
  }
  log('processing id = ' + id);

  switch (aInfo.menuItemId) {
    case 'fav':
      send_dm('fav', id);
      break;
    case 'rt':
      send_dm('rt', id);
      break;
    case 'rt-now':
      send_dm('rt!', id);
      break;
    case 'fav-and-rt':
      send_dm('fr', id);
      break;
    case 'fav-and-rt-now':
      send_dm('fr!', id);
      break;
  }
});

function detectStatusId(aUrl) {
  let match = aUrl.match(/^[^:]+:\/\/(?:[^/]*\.)?twitter.com\/(?:[^\/]+|i\/web)\/status\/([\d]+)/);
  return match ? match[1] : null;
}

function send_dm(...aArgs) {
  if (!configs.tweetsh_path || !configs.target_account) {
    notify(
      browser.i18n.getMessage('notConfiguredError.title'),
      browser.i18n.getMessage('notConfiguredError.message')
    );
    return;
  }

  let commandArgs = [
    'dm',
    configs.target_account,
    aArgs.join(' ')
  ];
  let message = {
    cmd: 'exec',
    command: configs.tweetsh_path,
    arguments: commandArgs
  };
  browser.runtime.getPlatformInfo().then((aInfo) => {
    if (aInfo.os == browser.runtime.PlatformOs.WIN) {
      message.arguments = [
        '-c',
        [configs.tweetsh_path].concat(commandArgs).map((aPart) => {
          return '"' + aPart.replace(/"/g, '\\"') + '"';
        }).join(' ')
      ];
      message.command = 'C:\\Windows\\System32\\bash.exe';
    }
    log('sending message: ', message);
    return browser.runtime.sendNativeMessage('com.add0n.node', message).then(
      (aResponse) => {
        notify(
          browser.i18n.getMessage('onResponse.title'),
          browser.i18n.getMessage('onResponse.message', commandArgs.join(' '))
        );
        log('Received: ', aResponse);
      },
      (aError) => {
        notify(
          browser.i18n.getMessage('onError.title'),
          browser.i18n.getMessage('onError.message', [commandArgs.join(' '), String(aError)])
        );
        log('Error: ', aError);
      }
    );
  });
}

function notify(aTitle, aMessage) {
  browser.notifications.create({
    type:    'basic',
    title:   aTitle,
    message: aMessage
  }).then((aId) => {
    setTimeout(() => browser.notifications.clear(aId), 3000);
  });
}

