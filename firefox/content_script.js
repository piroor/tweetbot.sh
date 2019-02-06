var buttons = [
  { id: 'fav',
    label: '❤️',
    target: 'tweet' },
  { id: 'rt',
    label: '🔃',
    target: 'tweet' },
  { id: 'fav_and_rt',
    label: '💞',
    target: 'tweet' },
  { id: 'follow',
    label: '🔔',
    target: 'user' },
  { id: '--separator-regular-items--' },
  { id: 'rt_now',
    label: '🔃',
    style: 'now',
    target: 'tweet' },
  { id: 'fav_and_rt_now',
    label: '💞',
    style: 'now',
    target: 'tweet' },
  { id: '--separator-now-items--' },
  { id: 'unrt',
    label: '🔃',
    style: 'cancel',
    target: 'tweet' },
  { id: 'unfav',
    label: '❤️',
    style: 'cancel',
    target: 'tweet' },
  { id: 'unfollow',
    label: '🔔',
    style: 'cancel',
    target: 'user' }
];

function updateTweets(node) {
  const tweets = node.querySelectorAll('div.tweet');
  for (const tweet of tweets) {
    if (tweet.dataset.tweetbotRemoteControllerProcessed)
      continue;
    tweet.dataset.tweetbotRemoteControllerProcessed = true;
    const id = tweet.dataset.tweetId;
    const userId = tweet.dataset.userId;
    if (!id)
      continue;
    const footer = tweet.querySelector('.stream-item-footer');
    if (!footer)
      continue;
    const wrapper = document.createElement('small');
    wrapper.style.float = 'right';
    wrapper.style.marginTop = '1em';
    for (const button of buttons) {
      addButton(button, wrapper, { id, userId });
    }
    footer.insertBefore(wrapper, footer.firstChild);
  }
}

function addButton(definition, container, params) {
  if (definition.id.startsWith('-')) {
    const separator = container.appendChild(document.createElement('span'));
    separator.appendChild(document.createTextNode('|'));
    separator.style.margin = '0.25em';
    separator.style.opacity = '0.5';
    return;
  }
  const button = container.appendChild(document.createElement('a'));
  button.appendChild(document.createTextNode(definition.label));
  button.setAttribute('title', browser.i18n.getMessage('menu_' + definition.id + '_label').replace(/\(&.\)/g, '').replace(/&(.)/g, '$1'));

  switch (definition.style) {
    case 'now':
      button.style.border = 'thin solid';
      button.style.borderRadius = '50%';
      break;
    case 'cancel':
      button.style.textDecoration = 'line-through';
      break;
  }

  button.style.filter = 'grayscale(100%)';
  button.style.margin = '0.25em';
  button.style.opacity = 0.45;

  button.onmouseover = () => {
    button.style.opacity = 1;
    button.style.filter = '';
  };
  button.onmouseout = () => {
    button.style.opacity = 0.45;
    button.style.filter = 'grayscale(100%)';
  };
  button.onclick = () => {
    browser.runtime.sendMessage({
      type:   definition.id,
      target: definition.target == 'user' ? params.userId : params.id
    });
  };
}

updateTweets(document.body);

const observer = new MutationObserver(records => {
  for (const record of records) {
    if (record.removedNodes.length > 0) {
      updateTweets(document.body);
    }
    for (const addedNode of record.addedNodes) {
      updateTweets(addedNode);
    }
  }
});
observer.observe(document.body, { childList : true, subtree : true });

window.addEventListener('unload', () => {
  observer.disconnect();
}, { once: true });

