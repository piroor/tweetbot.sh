var twitterMatchingPattenr = [
  '*://twitter.com/*',
  '*://*.twitter.com/*'
];
var tweetMatchingPattenr = [
  '*://twitter.com/*/status/*',
  '*://twitter.com/*/*/status/*',
  '*://*.twitter.com/*/status/*',
  '*://*.twitter.com/*/*/status/*'
];

var baseMenuItems = [
  { id: 'fav',
    matching: tweetMatchingPattenr },
  { id: 'rt',
    matching: tweetMatchingPattenr },
  { id: 'fav-and-rt',
    matching: tweetMatchingPattenr },
  { id: 'follow',
    matching: twitterMatchingPattenr.concat(tweetMatchingPattenr) },
  { id: '--separator-regular-items--',
    matching: twitterMatchingPattenr.concat(tweetMatchingPattenr) },
  { id: 'rt-now',
    matching: tweetMatchingPattenr },
  { id: 'fav-and-rt-now',
    matching: tweetMatchingPattenr },
  { id: '--separator-now-items--',
    matching: tweetMatchingPattenr },
  { id: 'unrt',
    matching: tweetMatchingPattenr },
  { id: 'unfav',
    matching: tweetMatchingPattenr },
  { id: 'unfollow',
    matching: twitterMatchingPattenr.concat(tweetMatchingPattenr) }
];
var debugMenuItems = [
  { id: '--separator-test--',
    matching: twitterMatchingPattenr.concat(tweetMatchingPattenr) },
  { id: 'test',
    matching: twitterMatchingPattenr.concat(tweetMatchingPattenr) }
];

function installMenuItems() {
  var menuItems = configs.debug ? baseMenuItems.concat(debugMenuItems) : baseMenuItems;
  for (let item of menuItems)
  {
    let isSeparator = item.id.charAt(0) == '-';
    let type = isSeparator ? 'separator' : 'normal';
    let title = isSeparator ? null : browser.i18n.getMessage('contextMenu.' + item.id + '.label');
    browser.contextMenus.create({
      id: item.id + ':page',
      type,
      title,
      contexts: ['page', 'tab'],
      documentUrlPatterns: item.matching
    });
    browser.contextMenus.create({
      id: item.id + ':link',
      type,
      title,
      contexts: ['link'],
      targetUrlPatterns: item.matching
    });
  }
}

configs.$load().then(installMenuItems);
configs.$addObserver((aKey) => {
  if (aKey == 'debug') {
    browser.contextMenus.removeAll();
    installMenuItems();
  } 
});

browser.contextMenus.onClicked.addListener(function(aInfo, aTab) {
  let url = aInfo.linkUrl || aInfo.pageUrl || aTab.url;
  log('procesing url = ' + url);

  let target = detectStatusId(url) || url;
  log('processing target = ' + target);

  switch (aInfo.menuItemId.split(';')[0]) {
    case 'fav':
      dmCommand('fav', target);
      break;
    case 'unfav':
      dmCommand('unfav', target);
      break;

    case 'rt':
      dmCommand('rt', target);
      break;
    case 'unrt':
      dmCommand('unrt', target);
      break;
    case 'rt-now':
      dmCommand('rt!', target);
      break;
    case 'fav-and-rt':
      dmCommand('fr', target);
      break;
    case 'fav-and-rt-now':
      dmCommand('fr!', target);
      break;

    case 'follow':
      dmCommand('follow', target);
      break;
    case 'unfollow':
      dmCommand('unfollow', target);
      break;

    case 'test':
      dmCommand('test', target);
      break;
  }
});

function detectStatusId(aUrl) {
  let match = aUrl.match(/^[^:]+:\/\/(?:[^/]*\.)?twitter.com\/(?:[^\/]+|i\/web)\/status\/([\d]+)/);
  return match ? match[1] : null;
}

function dmCommand(...aArgs) {
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
      // To communicate with Bash on Ubuntu on Windows, we have to execute the bash.exe via cmd.exe... why?
      message.command = 'cmd.exe';
      message.arguments = [
        '/Q',
        '/C',
        'bash.exe',
        '-c',
        [configs.tweetsh_path].concat(commandArgs).map((aPart) => {
          return '"' + aPart.replace(/"/g, '\\"') + '"';
        }).join(' ')
      ];
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

